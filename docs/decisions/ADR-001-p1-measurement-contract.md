# ADR-001: P1測定契約を固定する

## Status

Accepted

## Date

2026-09-12

## Context

P1 Core Promise checkpoint は 10 genuine eligible Open Loops、5 participants、5 matured contexts を要求する。一方、P1 固有の成熟期限、eligible predicate、Activation 分母、legitimate Retire の証跡は未定義だった。

`OBO Source of Truth v0.9.4` は製品意味の最上位権限だが、30日成熟とその分母は formal F-1 の契約である。P1 は directional proof であり、F-1 の期間を暗黙に流用してはならない。

## Decision

### Eligible Open Loop

次をすべて満たす Loop を `eligible_open_loop` とする。

- 認証済み成人の有効な同意に紐づく。
- P1 対象の日常事務テキストがサーバーに永続化され、感度 preflight を通過している。
- 必要な確認を完了し、現在の basis revision で `ACTIVE` な Open Loop が作成されている。
- テスト、重複、合成データではない。

`eligible_at` はこの条件を満たした時点で固定する。観測開始前に確定した技術的または適格性除外だけは、理由を記録して除外できる。

### Activation

P1 Activation の分母は、`eligible_at` で固定した全 `eligible_open_loop` とする。Receipt 未表示、未 ACK、処理失敗を後から分母から外してはならない。

Activation 成功は、`eligible_at` から7日以内に、current basis revision の有効な `OFFLOAD_RECEIPT_ACKED` を持つこととする。Activation は引き続き、`ACTIVE` Loop、`OFFLOAD_READY` Capture、durable ACK を要求する。

### Matured Context

`activated_at` から7日が経過した Context を P1 で matured とする。成熟判定時点の Current Valid Fact が valid SOC または legitimate Retire であり、未解決の material correction または critical trust incident がない場合に限り、matured-success と数える。

### Legitimate Retire

legitimate Retire は、本人が `END_CONTEXT` を明示実行し、理由を `NO_LONGER_REQUIRED` と記録した場合にのみ成立する。記録は Loop ID、current revision、actor、理由、時刻を append-only で保持する。

AI 推論、Push 開封、時間経過、Raw 削除、同意撤回は Retire でも SOC でもない。

## Alternatives Considered

### F-1 の30日成熟をP1へ流用する

却下。P1 は formal F-1 ではなく、その観測期間を継承する根拠がない。

### Receipt を表示した Loop だけを Activation 分母にする

却下。Receipt 前の失敗や離脱を分母から除くため、Core Promise の検証を選択的に良く見せられる。

## Consequences

- P1 Exit Artifact は最後の Activation から少なくとも7日後にのみ最終判定できる。
- P1は5件以上の matured-success を報告するが、未解決/失敗 Loop も固定分母の集計に残る。
- formal F-1 の30日契約、24 product-evaluable units、Ownership Coverage 80%をP1の数値要件へ読み替えない。

## Verification

- 同一の P1 fixture で、分母確定後の Receipt 未ACK/処理失敗が分母に残ることを検証する。
- 7日未満の SOC/Retire が matured-success に数えられないことを検証する。
- AI/Push/時間経過/削除/同意撤回だけでは SOC/Retire が作られないことを検証する。
