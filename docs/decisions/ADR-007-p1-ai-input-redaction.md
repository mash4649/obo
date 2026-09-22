# ADR-007: P1外部AI入力の直接識別子境界

## Status

Accepted（provider/data contractとD07-R実装契約。activation evidenceとredaction実装テストは参加者traffic前のrelease gate）

## Date

2026-09-13

## Context

P1は低リスクのテキスト入力だけを扱い、D06の`PRIVATE`判定とactive consentの後に外部AIを利用する。既存の契約はPush、ログ、analytics、crash breadcrumbsへのRaw/PII混入を禁止しているが、外部AIのpromptに個人名などの直接識別子を含めない境界は明示されていなかった。

参加者データを扱うP1では、providerのtraining opt-outやZDRだけに依存せず、送信前にアプリ側で直接識別子を処理する必要がある。

D07-A/BのP1 provider/modelはOpenAI APIの`gpt-5.6-luna`、endpointは`/v1/chat/completions`（`store:false`）、regionはprovider default globalとする。purposeはtext-onlyのexpected-state/date extraction、1件のclarification question、next-evaluation proposalに限定し、completion確定や外部アクションは許可しない。timeoutは1試行8秒・総期限15秒、retryはtimeout/408/429/5xxに対する1回のみ（250-1000ms jitter）、provider fallbackなし。input 2,500 tokens、output 256 tokens、per-capture $0.002、月額alert $5、hard stop $10、`cost_per_eligible_capture`/`cost_per_valid_soc`のwarning/hard-stopは$0.05/$0.10とする。

OpenAIのデータ制御仕様では、APIデータは明示的なopt-inがない限り学習・改善に使われず、Chat Completions/Responsesは通常最大30日のabuse-monitoring retentionがあり、ZDRは事前承認が必要とされる。したがって、data-sharing opt-in無効化、ZDR承認、保持条件のプロジェクト設定確認は参加者通信のactivation evidenceとする。ZDR承認前は合成・匿名化fixtureのみ許可する。

参照: [GPT-5.6 Luna model specification](https://developers.openai.com/api/docs/models/gpt-5.6-luna)、[OpenAI API data controls](https://developers.openai.com/api/docs/guides/your-data)

## Decision

外部AIへはRawをそのまま送信しない。Rawからローカルで直接識別子を除去または置換したテキストだけを、D06の`PRIVATE`判定・active consent・D07 provider approvalの後に送信する。

参加者の実データは、後述のD07-R契約とactivation evidenceが揃うまで外部providerへ送信しない。

## Direct-Identifier Taxonomy (P1 R1 decision)

| Category | P1 detection status | External-AI rule |
|---|---|---|
| Email address | Supported by deterministic syntax | Replace locally, then continue only if the post-redaction contract passes |
| Phone number | Supported for the explicitly accepted domestic/international syntax set | Replace locally, then continue only if the post-redaction contract passes |
| URL credentials/query tokens and known identifier-bearing URL parts | Supported only for the explicitly accepted syntax set | Replace the identifier-bearing part; otherwise deny |
| Account/user/device IDs | Supported only for UUID or an explicitly accepted app-ID grammar | Replace locally; opaque or unknown formats are denied |
| Personal names | Not guaranteed in P1 free-form text | Unsupported category; external-AI route is denied unless already removed by an approved local transform |
| Free-form postal addresses | Not guaranteed in P1 free-form text | Unsupported category; external-AI route is denied unless already removed by an approved local transform |
| Other quasi-identifiers (for example exact dates, workplace, or unique facts) | Not part of R1 taxonomy | Governed by D06/D11; never silently treated as safe by this ADR |

The supported syntax sets and the remove-versus-placeholder operation are fixed by the D07-R contract below. The important invariant is that an unsupported or unknown category is not an implicit allow.

## D07-R Implementation Contract

### Supported syntax and replacement

- Emailは、`local-part@domain`として構文解析できるtokenを検出する。表示名付き、壊れたdomain、複数候補が重なる場合は`DENY`とする。配送可否は判定しない。
- Phoneは、`+`で始まる国際形式、または`0`で始まる国内形式で、区切り文字を除いた数字が10–15桁のtokenを検出する。候補が日付・注文番号等とも解釈できる場合は`DENY`とする。
- UUIDはcanonical UUID形式を検出する。アプリIDは`obo_[a-z0-9]{16,64}`だけを許可し、それ以外のopaque IDは`DENY`とする。
- `http`/`https` URLは構文解析する。userinfo、query、fragment、UUID/app-IDを含むpath segmentは該当部分を置換し、opaqueなpath segmentや不正URLは`DENY`とする。hostだけの公開URLは識別子候補がなければ許可する。
- POSIX、Windows、UNCの絶対pathはpath全体を置換する。pathを伴わないfilenameはidentifier-like tokenであれば`DENY`、判定不能なら`DENY`とする。
- 個人名、自由記述住所、日本語の自然文に埋まる未知の識別子はP1で自動検出・安全化を保証しない。候補が残る可能性がある場合は`DENY`とする。手動overrideは設けない。

検出した値は削除ではなく、構造を保つ固定placeholderへ置換する。placeholderは`<EMAIL_1>`、`<PHONE_1>`、`<ID_1>`、`<URL_TOKEN_1>`、`<PATH_1>`の形式とし、番号は1リクエスト内の出現順で付ける。元値との対応表はリクエスト中のメモリに限り、保存・ログ・telemetry・retry payload以外へ渡さない。`policyVersion`は`d07-r/1`とする。

### Ambiguity and false-positive policy

- 判定不能、複数カテゴリに一致、未対応カテゴリ、検出例外はすべて`DENY`とする。
- false positive（安全側の過剰置換）は許容する。false negative（直接識別子の外部送信）は許容しない。
- 置換で文脈品質が低下した場合も、セキュリティ閾値を緩和せず、fixture品質評価またはP1再検討で扱う。

### Fixture acceptance threshold

- 必須fixtureの全ケースを100%合格とする。統計的な見逃し率の推定で代替しない。
- `ALLOW`はadapterへ`ApprovedAdapterInput`だけを渡し、元のidentifier literalを0件とする。
- `DENY`、曖昧、未対応、例外、D06 deny、inactive consentはadapter到達0回とする。
- retryは同一のredacted payloadを再利用し、Raw・元prompt・placeholder対応表を再生成しない。
- 同一入力を2回処理してもplaceholder形式とdeny/allow結果が変わらないことを確認する。

## Redaction-to-Adapter Boundary (P1 R2 decision)

The provider adapter accepts only a redacted value; it has no parameter or fallback path for Raw.

```ts
type ExternalAiInput =
  | { status: 'ALLOW'; redactedText: string; policyVersion: string }
  | { status: 'DENY'; reasonCode: string };

type ApprovedAdapterInput = Extract<ExternalAiInput, { status: 'ALLOW' }>;
```

The server pipeline is ordered as `D06 preflight + active consent → R2 redaction once → adapter`. Provider retries reuse the same `ApprovedAdapterInput`; they never reintroduce Raw. `DENY`, an unknown result, or a redaction exception produces zero adapter calls, keeps the capture local/held, and returns only a generic re-entry outcome to the user.

Audit/telemetry may record policy version and reason code, but never Raw text, the original prompt, redacted text, or provider response content. P1 has no second-provider fallback for a redaction or policy failure.

## Fixture and Verification Contract (P1 R3 decision)

All fixtures are synthetic; use `.invalid` domains, reserved/fake phone values, and non-user UUIDs. No participant or production value is allowed in the fixture set.

| Fixture | Redaction result | Adapter calls | Observable requirement |
|---|---|---:|---|
| plain low-risk text with no candidate identifier | `ALLOW` | 1 | Adapter receives only `ApprovedAdapterInput` |
| synthetic email/phone/approved-ID text | `ALLOW` | 1 | Adapter input contains no original identifier literal |
| personal-name/free-form-address/opaque-ID fixture | `DENY` | 0 | Capture is local/held; user sees generic re-entry |
| ambiguous or unsupported URL/ID syntax | `DENY` | 0 | No provider request or Raw fallback |
| redaction exception/unknown result | `DENY` | 0 | Exception is converted to generic failure; no prompt is emitted |
| any fixture with D06 deny or inactive consent | `DENY` | 0 | R2 cannot override D06 or consent |

The verification harness must spy on the adapter and assert the call count and received shape. Provider retry tests must assert that every retry reuses the same redacted payload and never receives Raw.

## Alternatives Considered

### Providerのtraining opt-out/ZDRだけに依存する

却下。保持・学習制御は必要だが、外部providerへ直接識別子を送る境界そのものを解決しない。

### `PRIVATE`ならRawをそのまま送る

却下。D06の低リスク判定は、個人名等の直接識別子が存在しないことを保証しない。

### P1では外部AIを使わない

保留。匿名化境界を確定できない場合の安全側フォールバックとして、D07-Bで再評価する。

## Consequences

- provider/modelの比較は、匿名化済みの合成またはde-identified fixtureで実施できる。
- 置換による文脈欠損や誤検知を測るテストが必要になる。
- 直接識別子の対象・方式・失敗時動作が決まるまで、P1の実データ経路はブロックされる。
- Rawの保存・削除・監査はD11の契約で別途定義する。
