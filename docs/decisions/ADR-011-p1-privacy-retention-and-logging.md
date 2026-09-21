# ADR-011: P1 Privacy、保持、削除、ログ境界

## Status

Accepted（2026-09-21。Supabaseバックアップ境界を確定。実装・DPA evidenceはrelease gate）

## Context

P1は記名された成人参加者を扱うが、外部AI、Push、ログ、クラッシュ報告へRawや直接識別子を出してはならない。削除要求は新規処理を止め、物理削除の完了を監査可能にする必要がある。一方、Supabase等の事業者バックアップ保持期間は実装パックに記載がなく、推測で決めると削除契約と矛盾する。

## Decision

### 確定済みのサブ決定（Beads D11 notes）

- `DELETE_RAW_CAPTURE` は直ちに `DELETION_PENDING` へ遷移し、後続処理と外部AI送信を止める。`private.capture_raws` の物理削除成功時だけ `DELETED` とし、失敗時はpendingのまま非Rawの最小監査情報だけを残す。
- Rawは `OFFLOAD_RECEIPT_ACKED` 後に直ちに物理削除し、未確認・失敗・保留でも作成から最大7日で削除する。7日はP1のプロダクト上限であり、法定保持期間ではない。ユーザー削除を優先する。
- `DELETE_ACCOUNT` はアクセスを失効し、将来の評価・配信を取消した後、Raw、device token、アカウントに紐づくsemantic/audit/telemetryを削除する。再識別不能な集計値のみ保持可とし、D13はその集計値だけを読む。
- 外部クラッシュ報告、session replay、product analytics SDKは使わない。Supabase内のsanitized telemetry/deletion auditは匿名化済みerror code、時刻、app version、OS versionだけを保持し、Raw、token、PII、breadcrumb、prompt/response、exception bodyを含めない。

### P1バックアップ／キャッシュ境界

- アプリはRaw、device token、prompt/responseのバックアップまたはエクスポートを作らない。
- Rawは端末ディスクへキャッシュせず、Capture中のメモリ上だけで扱い、送信完了・明示的破棄・logout時に破棄する。
- P1では非Rawを含む永続表示キャッシュも作らない。必要になった場合は、保持・削除・復元を別ADRで決める。
- SupabaseはProプランのDaily Backupのみを使い、PITRはP1では有効化しない。Daily Backupの保持は公式仕様の直近7日を上限とする。
- 管理バックアップはアプリの削除経路ではない。ライブDB上の削除は即時に実行し、バックアップ上の残存は最長7日以内に自動失効する前提をプライバシー説明とDPA確認へ反映する。
- 復元は本番DBへ直接戻さず、隔離した新規プロジェクトへ行う。削除済みRaw／Accountを再送信・再配信しないことを確認するまで参加者通信を再開しない。
- P1では手動dump、外部バックアップ、Rawを含むエクスポートを作らない。

## Verification

- D11実装時に、Rawのディスクキャッシュ0件、削除失敗時のpending維持、アカウント削除後のアカウント関連データ0件（許可された集計を除く）、ログ／telemetryの禁止フィールド0件をfixtureで確認する。
- Supabase公式の保持期間・復元手順とDPAの削除条件を記録し、P1参加者データ開始前に人間が承認する。

## Implementation gate

D11の契約は確定した。Raw削除、DPA evidence、隔離復元、禁止フィールドのfixtureが揃うまで外部P1データは有効化しない。
