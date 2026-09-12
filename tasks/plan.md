# OBO Lean MVP P0-P1 実装計画

## 概要

対象は `OBO_Lean_MVP_Implementation_Pack_v1.0_20260912` が有効化する P0-P1 Core Promise Proof のみです。P2 以降、Shared Open Loop、Email、LINE、Calendar、Group、商用化は前提 Gate を通過するまで実装しません。

実装を始める前に、パックだけでは確定しない製品意味・技術選定・数値定義を決定記録として閉じます。推測で補完しません。

## タスク台帳

実行状態、依存関係、受入条件は Beads を唯一の台帳とします。親Epicは `obo-main-gil` です。この文書は根拠・依存構造・未決事項の計画書であり、Markdown上でタスク状態は管理しません。

## 根拠と権限

- 製品意味・信頼・F-1測定は、パック外の `OBO Source of Truth v0.9.4` が最上位権限です。
- P0-P1 の物理実装順は `OBO Lean MVP / Core Proof - Phased Implementation Master v1.1`、スキーマ/コマンドは Lean Data Contract、既存作業単位は Ticket Map に従います。
- この計画は Ticket Map の L00-L12 を細分化せず順序・検証を保持し、その前に未決事項を解消するタスクを置きます。

## 依存関係

```text
D01--D04 ─┐
D05--D10 ─┼─> L00 -> L01 -> L02 -> L03 -> L04 -> L05 -> L06
D11--D14 ─┘                                      -> L07 -> L08 -> L09 -> L10 -> L11 -> L12 -> MVP-01
```

- D01 はメトリクス/成熟/SOC の親契約確認であり、L12 を必ずブロックします。
- D02-D05 は L00-L02、D06-D10 はそれぞれ L03/L05/L06/L07/L08 をブロックします。
- D11-D13 は削除・監査・P1運用の境界を決め、L11-L12 をブロックします。

## 実装フェーズ

### Phase D: 未決事項の決定

- `obo-main-gil.1` D01: 親SoT参照とP1測定語彙を確定
- `obo-main-gil.2` D02: 実行対象OS・配布/検証環境を確定
- `obo-main-gil.3` D03: 認証・成人確認・同意/撤回の契約を確定
- `obo-main-gil.4` D04: L00依存バージョンとCIコマンドを確定
- `obo-main-gil.5` D05: コマンド実行境界とRLS/サービス権限を確定
- `obo-main-gil.6` D06: 感度分類・拒否UX・AI送信可否規則を確定
- `obo-main-gil.7` D07: AIプロバイダと最小保持/コスト記録契約を確定
- `obo-main-gil.8` D08: Offload Receipt revision と配信冪等性キーを確定
- `obo-main-gil.9` D09: 評価/ACT・SILENCE・DEFER/再試行の規則を確定
- `obo-main-gil.10` D10: Pushの有効化条件・資格情報・失敗時UXを確定
- `obo-main-gil.11` D11: 削除/保持/匿名化とログ・クラッシュ報告の運用を確定
- `obo-main-gil.12` D12: P1参加者募集・同意文言・インシデント判定を確定
- `obo-main-gil.13` D13: P1レポートの分母・集計SQL・意思決定責任者を確定
- `obo-main-gil.28` D14: 外部P1参加者向けtransactional email/SMTP事業者と保持条件を確定

### Checkpoint D

D01-D13の回答を決定記録にし、P0-P1外を有効化せず、L00の依存をすべて解消する。

### Phase P0-P1: Ticket Map 実装

- `obo-main-gil.14` L00: Repository and implementation binding
- `obo-main-gil.15` L01: Auth and consent
- `obo-main-gil.16` L02: Minimal schema and RLS
- `obo-main-gil.17` L03: Minimum sensitivity preflight
- `obo-main-gil.18` L04: Durable Text Capture
- `obo-main-gil.19` L05: Interpret and confirm
- `obo-main-gil.20` L06: Open Loop and Offload Receipt
- `obo-main-gil.21` L07: Future evaluation and decision
- `obo-main-gil.22` L08: In-app / Push delivery
- `obo-main-gil.23` L09: Completion / end / reopen
- `obo-main-gil.24` L10: Ownership and semantic product metrics
- `obo-main-gil.25` L11: Privacy, deletion and mobile boundary
- `obo-main-gil.26` L12: Core Proof harness / P1 checkpoint

### Checkpoints

- A（L03後）: 認証、他者アクセス拒否、非対応センシティブ入力の安全停止を証明。
- B（L06後）: Text Capture から Offload Receipt 確認済み Activation までを証明。
- C（L09後）: 評価・配信・完了が stale send なく通ることを証明。
- D（L12後）: 実参加者で P1 Checkpoint を実行可能。

### MVP Exit

- `obo-main-gil.27` MVP-01: P1 Core Promiseを実施し、Exit Artifactと `PROCEED P2` / `ITERATE P1` / `RECONSIDER WEDGE` を根拠付きで確定する。

MVPの完成はP1の実施とExit Artifactの確定までとする。`PROCEED P2` であってもP2以降は別フェーズであり、本MVPの実装範囲には含めない。

## 明示的な矛盾・不足

| ID | 状態 | 根拠 | 影響 | 解消方針 |
|---|---|---|---|---|
| U01 | 解決済み | P1 固有の成熟期限・eligible predicate・Activation分母・legitimate Retire証跡を ADR-001 で固定 | P1 の成熟、valid SOC/Retire、分母を一意に集計できる | `docs/decisions/ADR-001-p1-measurement-contract.md` |
| U02 | 解決済み | Email OTP、成人自己申告、同意撤回、破壊的操作のrecent-authをADR-003で固定 | L01 の安全性とUX | `docs/decisions/ADR-003-p1-auth-consent.md` |
| U03 | 部分解決 | P1のiPhone/TestFlight/実機検証は ADR-002 で固定。依存version setとCI実行環境は未定 | L00、L08、L11 | D02は `docs/decisions/ADR-002-p1-ios-distribution.md`、D04は継続 |
| U04 | 未記載 | AIは「一つの承認済みプロバイダ」だが、プロバイダ、モデル、リージョン、利用目的、送信保持条件が未定 | L03/L05 のデータ境界 | D06/D07 |
| U05 | 解決済み | ADR-006で4つのP1 scope、SECRET/SENSITIVE/UNCLASSIFIEDの決定的preflight、2,000文字上限、FAILED_SAFE/hold UXを固定 | L03 の allow/deny テスト | `docs/decisions/ADR-006-p1-sensitivity-preflight.md` |
| U06 | 解決済み | ADR-005でJWT必須の単一command Function、secret専用processor/scheduler、service keyの閉域利用を固定 | L02-L05 のRLS回避権限 | `docs/decisions/ADR-005-command-boundary-and-migrations.md` |
| U07 | 契約不足 | `deliveries` は loop revision + reason + scheduled evaluation の一意性を要求するが、その3値/semantic key の列が定義されていない | L07-L08 の重複/ stale配信防止をDBで証明できない | D08 で列と一意制約を契約へ追加/確定 |
| U08 | 未記載 | current receipt basis/revision の保存形式、ACK の再送・訂正後の無効化規則が未定 | L06 Activation の正しさ | D08 |
| U09 | 未記載 | bounded batch、Cron頻度、ロック方式、失敗/再試行、ACT/SILENCE/DEFER判定規則が未定 | L07 の通知品質/負荷 | D09 |
| U10 | 未記載 | Expo Push は初期利用とあるが、資格情報、Push有効化時期、通知許可拒否時のin-app代替、controlled-proof tolerance が未定 | L08 | D10 |
| U11 | 未記載 | Account削除の「release privacy policy」、保持期間、匿名化対象、ログ/クラッシュ報告ベンダーが未定 | L11 | D11 |
| U12 | 未記載 | P1は5参加者/10 loop等を規定するが、募集/同意文言、インシデントのcritical判定、レポート責任者が未定 | L12 とPASS判定 | D12/D13 |
| U13 | 解決済み | ADR-005でLM00/LM10/LM20/LM30の正確なテーブル割当とL02/L08の追加境界を固定 | L02/L08の移行境界 | `docs/decisions/ADR-005-command-boundary-and-migrations.md` |
| U14 | 未記載 | Supabase既定メール送信は外部P1参加者へのOTP送信に使えず、custom SMTPの事業者、処理地域、保持・削除条件が未定 | L01 と外部P1ログイン | D14 |

## Gate-locked backlog（作成・実装しない）

- P2 / N20 Screenshot・Photo: P1 PASS 後。
- P3 / N30 OS Share: P2 PASS 後。
- Formal F-1 / N40: P3 PASS 後かつ正式コホート前。
- Social/Viral、WTP、Personal Compounding、Hardened Pilot、外部連携、商用化、Group/Vertical、Passport: 各先行 Gate 後。

## リスクと抑制

| リスク | 影響 | 抑制 |
|---|---|---|
| 親SoTなしで測定を実装 | 高 | U01を未解消のままL12へ進めない |
| AI/RLS実行境界の曖昧さ | 高 | D05-D07をL02-L05の必須ブロッカーにする |
| 冪等性キーの物理欠落 | 高 | D08でスキーマ制約まで決めてからL07-L08を実装 |
| P2以降の先走り | 中 | Gate-locked backlogを実装キューに入れない |
