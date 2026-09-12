# ADR-007: P1外部AI入力の直接識別子境界

## Status

Proposed（直接識別子を外部AIへ送らない方針は合意済み。provider/modelを含むD07全体は未完了）

## Date

2026-09-13

## Context

P1は低リスクのテキスト入力だけを扱い、D06の`PRIVATE`判定とactive consentの後に外部AIを利用する。既存の契約はPush、ログ、analytics、crash breadcrumbsへのRaw/PII混入を禁止しているが、外部AIのpromptに個人名などの直接識別子を含めない境界は明示されていなかった。

参加者データを扱うP1では、providerのtraining opt-outやZDRだけに依存せず、送信前にアプリ側で直接識別子を処理する必要がある。

## Decision

外部AIへはRawをそのまま送信しない。Rawからローカルで直接識別子を除去または置換したテキストだけを、D06の`PRIVATE`判定・active consent・D07 provider approvalの後に送信する。

次の項目はこのADRでは決めず、D07-Bの未決事項として残す。

- 直接識別子の対象一覧（個人名、メールアドレス、電話番号など）
- 除去か置換か、置換時のプレースホルダー形式
- 検出不能・曖昧・処理失敗時のfail-closed挙動
- 置換後テキストの品質評価とテスト閾値

上記が確定するまで、参加者の実データを外部providerへ送信しない。

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
