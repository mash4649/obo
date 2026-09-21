# ADR-012: P1募集、同意、Critical Incident

## Status

Accepted（2026-09-21。実参加者募集・同意画面・incident evidenceはrelease gate）

## Decision

### 募集

- P1は招待制で、事前登録した記名成人のみを対象にする。
- 初期対象は子育て世帯で、反復する未解決の生活上の用件を持つ参加者とする。
- 公開募集、未知メールアドレスの登録、匿名の永続追跡は行わない。最低5名を個別招待し、P1全体で最低10 loopを扱う。

### 同意・撤回

- version、同意文言、同意時刻、actorをappend-onlyで記録する。同意前はCapture、AI、評価、配信を開始しない。
- 同意画面には、収集データ、text-only AI処理、通知、保持・削除、外部サービス、撤回方法、問い合わせ先、P1の実験目的を明記する。
- 撤回は即時に新規Capture、AI、評価、配信を止め、全端末をlogoutし、D11の削除処理へ進める。撤回後に再開するには新しい同意を取得する。

### Critical Incident

次のいずれかは、疑いの段階でもCriticalとして扱う。

- Raw／PII／tokenが承認外のAI、SMTP、Push、ログ、第三者へ到達した。
- cross-user access、認証・同意状態の破綻、削除要求後の処理継続が発生した。
- stale delivery、誤配信、停止不能など、Core Promiseの信頼境界を破った。

### 対応・停止権限

- Critical検知時は、誰でも緊急停止を実行できる。AI、SMTP、Push、Schedulerの外部処理を停止し、参加者の新規処理をholdする。
- 30分以内にProduct OwnerとPrivacy/Security Ownerへ内部エスカレーションし、最小限の非Raw監査情報だけを残す。参加者への一次連絡は事実確認後24時間以内を目標とし、法令上の報告要否は別途判断する。
- 再開はProduct OwnerとPrivacy/Security Ownerの共同承認、原因修正、fixture再実行、影響範囲確認を条件とする。再開できない場合はP1をpauseまたはstopする。

### 参加者支援

- P1専用の運用メールボックスを問い合わせ窓口とし、緊急停止時の代替連絡先を同意文言に記載する。実アドレスは環境設定で管理し、ログへ出さない。

## Verification

- versioned consent、撤回直後のzero-processing、Critical fixture、緊急停止・再開承認、参加者連絡テンプレートを確認する。
- 5名以上・10 loopの招待記録と、同意・撤回・incident auditの再構成可能性を確認する。

## Implementation gate

同意文言、運用窓口、緊急停止手順、責任者、参加者連絡テンプレートが承認されるまで、実参加者を募集しない。
