# ADR-003: P1は事前登録者へのEmail OTP認証と明示同意を使う

## Status

Accepted

## Date

2026-09-12

## Context

P1は記名の少人数参加者だけを対象とし、認証、成人確認、同意、撤回、削除操作の本人確認を一貫したサーバー側の信頼境界で扱う必要がある。パックはpasswordless email modeを求めるが、方式、失効、撤回後の状態、破壊的操作の再認証を定めていない。

SupabaseのEmail OTPとMagic Linkは同じpasswordless認証経路を使う。メールスキャナやリンクの先読みでMagic Linkが消費されうるため、P1モバイルではOTPを採用する。外部P1参加者へ送信するには、Supabaseの既定メール送信ではなくcustom SMTPが必要である。SMTP事業者・リージョン・保持条件はD14で別途確定する。

## Decision

- 認証は6桁のEmail OTPとする。OTPは発行から10分、単回だけ有効とし、同一メールアドレスの再送は60秒後から許可する。
- P1参加者のメールアドレスは事前登録する。未知メールアドレスによる自動アカウント作成を拒否する。
- 初回OTP認証後、18歳以上の自己申告を必須にする。生年月日・年齢は保存しない。同意文書version、成人自己申告、時刻は追記専用で記録する。
- 同意撤回時は、新規Capture、AI処理、評価、配信を直ちに停止し、全端末をログアウトしてアカウントを`DELETION_PENDING`へ遷移させる。Raw/Accountの物理削除、保持、監査の詳細はD11で定める。同意撤回をSOCまたはRetireとして数えない。
- `WITHDRAW_CONSENT`と`DELETE_ACCOUNT`は操作直前の再認証を必須にする。再認証は、対象account・session・action kindに束縛した専用Email OTP challengeをアプリケーション側で発行・検証する。challengeは10分、単回有効とし、成功したrecent-auth証跡をサーバー側に記録してコマンド境界で検証する。
- `DELETE_RAW_CAPTURE`はログイン中の本人が対象を確認して実行できる。サーバーはaccount・captureの所有関係と有効なsessionを確認し、Rawだけを削除する。2026-09-25に、削除を妨げるメール再認証の負担をなくすため変更した。
- Supabaseの`reauthenticate()`はパスワード変更向けの機能であり、このpasswordless破壊的操作の要件充足には使わない。
- OTP本文、OTP値、メールアドレス、同意本文、recent-authの秘密情報をアプリ、関数、クラッシュ報告のログに出力しない。

## Alternatives Considered

### Magic Linkを使う

却下。メールセキュリティ製品やクライアントの先読みが確認URLを消費しうるため、P1モバイルの認証失敗要因を増やす。

### 未知メールから自動作成を許可する

却下。P1の記名コホート、成人確認、同意追跡の対象外アカウントを作れてしまう。

### 初回ログインOTPを破壊的操作の再認証として再利用する

却下。操作時点の本人確認、actionへの束縛、単回監査を証明できない。

### 撤回時はクライアントをログアウトするだけにする

却下。他端末・非同期処理・配信が継続しうる。

## Consequences

- L01は事前登録、OTPの失効・再送、同意追記、撤回状態、サーバー側recent-auth challengeを実装・検証する。
- L02/L05/L07/L08は`DELETION_PENDING`とactive consentをコマンドおよび非同期実行の前提条件として扱う。
- 外部P1参加者のOTP送信は、D14でcustom SMTP事業者とデータ取扱いを承認するまで開始しない。
- OTP試行回数上限・IP/メール単位のrate limit値は、実装基盤の標準保護設定をD04で確認し、標準で足りない場合だけ追加の数値決定を起票する。

## Sources

- Supabase passwordless email: https://supabase.com/docs/guides/auth/auth-email-passwordless
- Supabase email templates and link scanning note: https://supabase.com/docs/guides/auth/auth-email-templates
- Supabase `signInWithOtp`: https://supabase.com/docs/reference/javascript/auth-signinwithotp
- Supabase custom SMTP: https://supabase.com/docs/guides/auth/auth-smtp
- Supabase sessions: https://supabase.com/docs/guides/auth/sessions
- Supabase reauthentication scope: https://supabase.com/docs/guides/auth/password-security

## Verification

- Unknown email cannot create an account or receive a P1 login session.
- OTP is rejected after 10 minutes, after use, and before the 60-second resend window; values never appear in logs.
- An authenticated user cannot continue Capture, AI, evaluation, or delivery after consent withdrawal from any device.
- Consent withdrawal and account deletion reject a missing, expired, used, account-mismatched, session-mismatched, or action-mismatched recent-auth proof.
- Raw deletion rejects unauthenticated and cross-account requests, requires a confirmation in the app, and preserves linked tracking.
- Test evidence shows no birthdate or age value is persisted, while consent version, adult declaration, and timestamp are auditable.
