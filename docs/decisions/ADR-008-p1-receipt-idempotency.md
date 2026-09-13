# ADR-008: P1 Receipt revision と配信冪等性

## Status

Accepted（2026-09-13。実装fixture evidenceはrelease gate）

## Context

P1のActivationは、現行basis revisionのOffload Receiptをユーザーが永続ACKした場合だけ成立する。Receiptの再表示・再送、ユーザー訂正、Schedulerの再実行が重複ACKやstale配信を作らないことをDBとCommand境界で証明する必要がある。

## Decision

- Loopの`basis_revision`は1から始まる単調増加整数とし、expected state/date/conditionまたはReceiptの意味が変わる訂正時だけ増やす。retryとduplicate ACKでは増やさない。
- Receipt識別子は`(loop_id, basis_revision)`。`ACK_OFFLOAD_RECEIPT`は両値を受け取り、current ACTIVE revisionだけを受理する。
- `OFFLOAD_RECEIPT_ACKED`は`(loop_id, basis_revision)`につき1件へ冪等収束する。同一ACKの再送は既存成功を返し、stale revisionはgeneric stale outcome・無変更とする。
- 訂正は新revisionを作り、旧ACKをActivation判定上無効化する。append-only履歴は書き換えない。旧revisionのpending deliveryはcancelまたは送信直前のstale再検証で抑止する。
- `deliveries`の`scheduled_evaluation_at`はUTC・非NULLとし、`(loop_id, basis_revision, reason_code, scheduled_evaluation_at)`に一意制約を置く。
- 配信作成・送信直前に`ACTIVE`、current revision、新しいdecisionの不存在、channel permissionを再検証する。stale行は送信せず成功扱いにしない。

## Verification

Deterministic fixtures must prove duplicate ACK、stale ACK、correction invalidation、duplicate delivery insertion、stale-send suppression. Rendering alone must never create an ACK or Activation.

## Implementation gate

実装時のSQL制約・Command戻り値・cancel表現のfixture evidenceが必要。これらの証跡が揃うまで実配信を開始しない。
