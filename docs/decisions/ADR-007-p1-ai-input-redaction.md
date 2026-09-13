# ADR-007: P1外部AI入力の直接識別子境界

## Status

Proposed（provider/modelは選択済み。直接識別子境界とD07-Bデータ契約の最終受入前）

## Date

2026-09-13

## Context

P1は低リスクのテキスト入力だけを扱い、D06の`PRIVATE`判定とactive consentの後に外部AIを利用する。既存の契約はPush、ログ、analytics、crash breadcrumbsへのRaw/PII混入を禁止しているが、外部AIのpromptに個人名などの直接識別子を含めない境界は明示されていなかった。

参加者データを扱うP1では、providerのtraining opt-outやZDRだけに依存せず、送信前にアプリ側で直接識別子を処理する必要がある。

D07-AのP1 provider/modelは、OpenAI APIの`gpt-5.6-luna`を使用する。公式モデル仕様では、テキスト入出力、`/v1/chat/completions`、`/v1/responses`、および入力単価$0.20/1M tokens・出力単価$1.20/1M tokensが示されている。P1で採用するendpoint、region、purpose、timeout/retry、保持および運用上の上限はD07-Bで別途確定する。

OpenAIのデータ制御仕様では、APIデータは明示的なopt-inがない限り学習・改善に使われず、Chat Completions/Responsesは通常最大30日のabuse-monitoring retentionがあり、ZDRは事前承認が必要とされる。したがって、training opt-outの運用確認、ZDR承認、保持条件の受入は参加者通信のactivation evidenceとしてD07-Bに残す。

参照: [GPT-5.6 Luna model specification](https://developers.openai.com/api/docs/models/gpt-5.6-luna)、[OpenAI API data controls](https://developers.openai.com/api/docs/guides/your-data)

## Decision

外部AIへはRawをそのまま送信しない。Rawからローカルで直接識別子を除去または置換したテキストだけを、D06の`PRIVATE`判定・active consent・D07 provider approvalの後に送信する。

次の項目はこのADRでは決めず、D07-Bの未決事項として残す。

- 除去か置換か、置換時のプレースホルダー形式
- 検出不能・曖昧・処理失敗時の具体的なhold/re-entry UX
- 置換後テキストの品質評価とテスト閾値

上記が確定するまで、参加者の実データを外部providerへ送信しない。

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

The supported syntax sets and the remove-versus-placeholder operation remain R2 implementation decisions. The important R1 invariant is that an unsupported or unknown category is not an implicit allow.

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
