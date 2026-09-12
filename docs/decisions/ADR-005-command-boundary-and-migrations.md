# ADR-005: P1のコマンド境界とmigration所属を固定する

## Status

Accepted

## Date

2026-09-12

## Context

P1はRaw、AI、Activation、SOC、Ownership、Deliveryをクライアントの直接書込みから隔離する必要がある。Lean Data ContractはEdge FunctionまたはPostgreSQL functionを許容していたため、実行主体とLM migrationの境界を固定する。

## Decision

- モバイルからの状態変更は、JWT検証を有効にした単一の`command` Edge Functionだけを入口にする。Supabaseの`auth: 'user'`でユーザーJWTを検証し、コマンド名はallowlistで受け付ける。
- `command`は入力スキーマ、active consent、account ownership、current state、idempotency keyを検証し、成功した業務結果と`audit_events`/`loop_events`を同じ処理で記録する。
- `command`内の通常のユーザー参照はJWTに紐づくRLS clientを使う。Raw読取と、RLSでは直接許可しない業務結果のサーバー書込みだけを、Function内でsecret keyを使うserver clientに限定する。secret keyを端末、ログ、リポジトリへ出さない。
- `processor`と`scheduler`はユーザーから呼べない内部Functionとし、`auth: 'secret'`、`apikey` secret、`verify_jwt = false`の組み合わせでサービス間認証する。公開Functionで`verify_jwt=false`を使わない。
- 公開schemaの全テーブルはRLSを有効化し、`anon`/`authenticated`のgrantを最小化する。`private.capture_raws`は通常クライアントにgrantしない。直接のActivation/SOC/Ownership/Delivery作成は拒否する。
- migration所属は次の通り固定する。
  - `LM00_FOUNDATION`: `accounts`、`consents`、`audit_events`とRLS helper
  - `LM10_CORE`: `captures`、`capture_raws`、`open_loops`、`loop_events`
  - `LM20_ATTENTION`: `deliveries`、`device_installations`、`product_events`、Cron function
  - `LM30_F1_MEASUREMENT`: `experiment.test_units`のみ。正式F-1開始前には作成しない
- P1参加者の事前登録は、追加の公開product tableを作らず、管理者専用のSupabase Auth user provisioningで行う。未知メールによる自動作成拒否はD03の契約を維持する。

## Alternatives Considered

### クライアントからPostgreSQL RPCを直接呼ぶ

却下。認可済み関数にはできるが、Function単位の入口、監査、Raw/外部AI境界を一箇所で検証しにくい。

### 全書込みをクライアントRLSに任せる

却下。クライアントがActivation、SOC、Ownership、Deliveryの業務結果を直接作れてしまう。

### すべての処理を常時service roleで行う

却下。secret keyの権限が不要な読取りまで広がり、漏えい時の影響範囲が大きくなる。

## Consequences

- L01以降の全コマンドは`command`の契約とサーバー監査を通る。
- L02のDBテストはown-row allow、cross-account deny、Raw client deny、直接業務結果denyを必須にする。
- D08/D09のScheduler・冪等性は`processor`/`scheduler`の内部境界に従う。

## Sources

- Supabase RLS grants and policies: https://supabase.com/docs/guides/database/postgres/row-level-security
- Supabase secured Edge Functions: https://supabase.com/docs/guides/functions/auth
- Supabase authorization headers and `verify_jwt`: https://supabase.com/docs/guides/functions/auth-headers
- OBO Lean MVP Minimal Data Contract: `docs/20260912/OBO_Lean_MVP_Implementation_Pack_v1.0_20260912/OBO_Lean_MVP_Minimal_Data_Contract_v1.0_20260912.md`

## Verification

- Mobile publishable keyからの直接insert/updateで業務結果が作れない。
- JWTなしの`command`、secretなしの内部Function、他account対象のコマンドが拒否される。
- Rawは通常クライアントからselectできず、Function内の必要な処理だけが読める。
- LM00/LM10/LM20のmigrationを個別にreset・検証できる。
