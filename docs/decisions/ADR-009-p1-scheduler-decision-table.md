# ADR-009: P1 Scheduler と ACT/SILENCE/DEFER

## Status

Accepted（2026-09-13。実装integration evidenceはrelease gate）

## Context

P1は未来の評価をスケジュールし、通知そのものを予約しない。評価の再実行、同時実行、provider一時障害、Loop訂正が、stale通知や無制限retryを生まないScheduler境界が必要である。

## Decision

- Supabase Cronを5分間隔で実行し、`next_evaluation_at`が期限に達したACTIVE Loopを最大25件、`next_evaluation_at`→`loop_id`順で取得する。
- Loop単位のtransaction lockを取得できない対象はその実行ではskipする。1対象あたり評価は初回+retry 1回まで、retryは1-5秒jitter。失敗時は`DEFER`、`next_evaluation_at`を15分後へ進め、deliveryは作らない。
- `ACT`はLoopがACTIVE、D08のcurrent revisionが一致、effective stateが`UNSATISFIED`、同等のpending deliveryがない場合だけ許可する。`ACT`だけがdeliveryを作れる。
- `SILENCE`はLoopがACTIVEでない、またはeffective stateが`SATISFIED`/`NO_LONGER_REQUIRED`の場合。decision eventだけを記録しdeliveryは作らない。終端Loopは次回評価を持たない。
- `DEFER`はeffective stateが`UNKNOWN`/`CONFLICT`、一時的なprovider/evaluation failure、安全な送信条件を確認できない場合。decision eventを記録し、deliveryは作らない。
- `ACT`のdelivery作成・送信直前にはD08のstatus、current revision、新しいdecision、channel permissionを再検証する。stale/closed/satisfied/retired Loopは送信しない。

## Verification

Deterministic scheduler fixtures must prove bounded batch、lock contention、retry exhaustion、ACT/SILENCE/DEFER各行、stale loop、SILENCE/DEFER zero-delivery. Rendering or evaluation success alone must not imply Activation or completion.

## Implementation gate

Cron/batch/lock/retry値の実装証跡、およびL07/L08のscheduler integration testが必要。これらの証跡が揃うまで定期評価・実配信を開始しない。
