# ADR-011: P1 Privacy、保持、削除、ログ境界

## Status

Proposed（D11。バックアップ／キャッシュの事業者保持条件が未決のため未承認）

## Context

P1は記名された成人参加者を扱うが、外部AI、Push、ログ、クラッシュ報告へRawや直接識別子を出してはならない。削除要求は新規処理を止め、物理削除の完了を監査可能にする必要がある。一方、Supabase等の事業者バックアップ保持期間は実装パックに記載がなく、推測で決めると削除契約と矛盾する。

## Decision

### 確定済みのサブ決定（Beads D11 notes）

- `DELETE_RAW_CAPTURE` は直ちに `DELETION_PENDING` へ遷移し、後続処理と外部AI送信を止める。`private.capture_raws` の物理削除成功時だけ `DELETED` とし、失敗時はpendingのまま非Rawの最小監査情報だけを残す。
- Rawは `OFFLOAD_RECEIPT_ACKED` 後に直ちに物理削除し、未確認・失敗・保留でも作成から最大7日で削除する。7日はP1のプロダクト上限であり、法定保持期間ではない。ユーザー削除を優先する。
- `DELETE_ACCOUNT` はアクセスを失効し、将来の評価・配信を取消した後、Raw、device token、アカウントに紐づくsemantic/audit/telemetryを削除する。再識別不能な集計値のみ保持可とし、D13はその集計値だけを読む。
- 外部クラッシュ報告、session replay、product analytics SDKは使わない。Supabase内のsanitized telemetry/deletion auditは匿名化済みerror code、時刻、app version、OS versionだけを保持し、Raw、token、PII、breadcrumb、prompt/response、exception bodyを含めない。

### P1バックアップ／キャッシュ境界（作業提案・未承認）

- アプリはRaw、device token、prompt/responseのバックアップまたはエクスポートを作らない。
- Rawは端末ディスクへキャッシュせず、Capture中のメモリ上だけで扱い、送信完了・明示的破棄・logout時に破棄する。
- P1では非Rawを含む永続表示キャッシュも作らない。必要になった場合は、保持・削除・復元を別ADRで決める。
- Supabaseその他事業者の管理バックアップはアプリの削除経路ではない。保持期間、削除反映、復元時の扱いは、事業者の公式条件とDPAを確認するまで未決とする。
- 事業者バックアップ条件の確認と受入記録が完了するまで、実参加者データではなくsynthetic/de-identified fixtureだけを使う。

## Verification

- D11実装時に、Rawのディスクキャッシュ0件、削除失敗時のpending維持、アカウント削除後のアカウント関連データ0件（許可された集計を除く）、ログ／telemetryの禁止フィールド0件をfixtureで確認する。
- 事業者ごとのバックアップ保持・削除反映・復元手順を公式文書とDPAで記録し、P1参加者データ開始前に人間が承認する。

## Implementation gate

D11は本ADRの確定済みサブ決定を実装境界として利用できるが、バックアップ／キャッシュの事業者条件が承認されるまで外部P1データを有効化しない。
