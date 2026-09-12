# ADR-006: P1は決定的な最小感度preflightだけを実装する

## Status

Accepted

## Date

2026-09-12

## Context

P1はlow-risk everyday administrationだけを対象にし、Rawを外部AIへ送る前にSECRET/SENSITIVE/UNCLASSIFIEDを安全停止する必要がある。パックは広範な感度分類器やHuman Raw ProxyをP1に要求していない。

## Decision

- Capture時にユーザーが次のscopeを一つ選ぶ: `SCHEDULE`（予定）、`HOUSEHOLD`（家事）、`SHOPPING`（買い物）、`GENERAL_ADMIN`（一般的な用事）。scopeはサーバー側allowlistで検証し、`captures`に記録する。
- 入力はtrim後のUnicode code point数で2,000文字を上限とする。超過は`UNCLASSIFIED`として安全停止し、外部AIへ送らない。
- preflightはローカルで決定的に実行し、モデルや外部AIを分類器として使わない。
  - `SECRET`: password、OTP、recovery code、API key、authentication token等の明白な資格情報。通常処理を拒否する。
  - `SENSITIVE`: 医療詳細、公的ID、高リスク金融資格情報等の明白な高リスク情報。外部AIを拒否し、ローカルでholdする。
  - `UNCLASSIFIED`: scope不正、長さ超過、入力欠落、または安全に分類できないもの。外部AIを拒否する。
  - `PRIVATE`: scopeが許可され、上記の拒否シグナルがなく、サーバーpreflightが明示的に許可したものだけ。`external_ai_allowed`をサーバー側でtrueに遷移できる。
- `SECRET`/`SENSITIVE`/`UNCLASSIFIED`は`external_ai_allowed=false`を維持し、Capture状態を`FAILED_SAFE`にする。ユーザーには入力本文を再表示せず、削除または危険情報を除いて再入力する導線だけを示す。
- 判定理由はコードだけを監査し、Raw本文・一致した秘密値・分類器の詳細をログ、telemetry、AI promptへ出さない。P1では手動override、LLM分類、一般的な感度ルーターを追加しない。

## Alternatives Considered

### LLMに感度分類を任せる

却下。分類前のRawが外部へ出てしまい、AI出力も信頼境界にならない。

### 未検出ならPRIVATEにする

却下。UNCLASSIFIEDを暗黙に外部AI許可へ変換するdefault-allowになる。

### すべての入力をSECRET/SENSITIVEとして拒否する

却下。P1のlow-risk Core Promiseを検証できない。

## Consequences

- L03は拒否fixtureの外部AI adapter到達回数が0であることを検証する。
- scope enumと2,000文字上限はL04のCapture入力契約にも適用する。
- D07で承認するAI provider/purpose/retentionが確定するまで、`PRIVATE`でも実送信を開始しない。

## Sources

- OBO Lean MVP Core Proof Source of Truth: `docs/20260912/OBO_Lean_MVP_Implementation_Pack_v1.0_20260912/OBO_Lean_MVP_Core_Proof_Source_of_Truth_v1.0_20260912.md`
- OBO Lean MVP Minimal Data Contract: `docs/20260912/OBO_Lean_MVP_Implementation_Pack_v1.0_20260912/OBO_Lean_MVP_Minimal_Data_Contract_v1.0_20260912.md`
- Supabase API keys and server-only secret keys: https://supabase.com/docs/guides/getting-started/api-keys

## Verification

- SECRET、SENSITIVE、UNCLASSIFIED、scope不正、2,001文字入力のfixtureは外部AI adapterへ到達しない。
- 許可された4 scopeで、拒否シグナルのない2,000文字以内のfixtureだけがサーバーのPRIVATE遷移候補になる。
- AI送信前にscope、active consent、`external_ai_allowed`、D07のprovider approvalを再検証する。
