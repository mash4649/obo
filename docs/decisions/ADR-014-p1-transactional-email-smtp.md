# ADR-014: P1 transactional email／SMTP

## Status

Accepted（2026-09-21。実メール送信・DPA evidenceはrelease gate）

## Context

Supabase Authの既定SMTPは外部アドレスへの本番OTP送信に使えない。P1では記名成人のEmail OTPだけを送信し、メールアドレス・OTP・送信本文をログや分析へ流さない必要がある。

## Decision

- custom SMTPは **Amazon SES**、リージョンは **ap-northeast-1（東京）**、Supabase設定はTLS付きSMTP port 587を使う。認証用の送信ドメイン／From addressはマーケティング用途と分離する。
- AWS SESのDPA、リージョン、送信元ドメイン検証、DKIM/SPF/DMARC設定を参加者送信前のrelease gateとする。Supabase Authのcustom SMTP設定が完了するまで外部参加者へ送らない。
- Email addressはSupabase Authのactive accountに必要な期間だけ保持し、`DELETE_ACCOUNT`／撤回処理でアプリ側の関連データを削除する。アプリ独自のメールアドレス複製を作らない。
- OTP値、OTP本文、メール本文は保存・ログ・telemetryへ出さない。送信ログは匿名化した結果コード、時刻、app versionだけを30日保持し、その後削除する。SESのイベント発行・本文収集は有効化しない。
- OTP再送は1アカウントあたり3回／15分まで。SMTP送信が3回連続失敗、または直近10分の5件以上で失敗率20%以上になった場合、外部OTP送信を停止する。再開は原因確認後、事前登録テストアドレスへの3回連続成功と手動承認を条件とする。
- テストは事前登録済み外部テストアドレスだけで行い、ログにメールアドレス・OTP・SMTP資格情報が出ないことを確認する。

## Verification

- Supabase custom SMTP設定、SES東京エンドポイント、TLS接続、送信元ドメイン認証を確認する。
- 成功、期限切れ、再送上限、SMTP失敗、停止・再開のfixtureを検証する。
- SES DPAとデータ処理条件を記録し、D14のAcceptance evidenceとして保管する。

## Implementation gate

実参加者へのOTP送信は、SESアカウントの本番送信解除、ドメイン認証、DPA確認、外部テスト送受信、秘密情報非記録の証跡が揃うまで無効とする。
