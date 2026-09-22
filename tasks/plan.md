# OBO Lean MVP P0-P1 実装計画

## 概要

対象は `OBO_Lean_MVP_Implementation_Pack_v1.0_20260912` が有効化する P0-P1 Core Promise Proof のみです。P2 以降、Shared Open Loop、Email、LINE、Calendar、Group、商用化は前提 Gate を通過するまで実装しません。

実装を始める前に、パックだけでは確定しない製品意味・技術選定・数値定義を決定記録として閉じます。推測で補完しません。

## タスク台帳

実行状態、依存関係、受入条件は Beads を唯一の台帳とします。親Epicは `obo-main-gil` です。この文書は根拠・依存構造・未決事項の計画書であり、Markdown上でタスク状態は管理しません。

## 根拠と権限

- 定義ループの仕様は `SPEC.md`。このファイルは依存構造とBeads IDの索引であり、状態の正はBeadsに置く。

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

### Definition loop review

- Loop A（spec）: `SPEC.md` に固定済みADR、残りD07-D14の能力境界、コマンド、構造、テスト、禁止境界を記録する。
- Loop A review: provider/保持/数値/運用責任を推測で埋めず、D07を次の人間ゲートにする。
- D07-A/B（2026-09-13確定）: P1 provider/modelはOpenAI APIの`gpt-5.6-luna`、endpointは`/v1/chat/completions`（`store:false`）、regionはprovider default global。P1 text-only scope、P1 fallbackなし、D07-Bのtimeout/retry/cost値を確定した。Rawからローカルで直接識別子を除去・置換したテキストだけを送る方針とR1-R3契約は維持し、ZDR project設定とredaction/adapter fixture evidenceが閉じるまで参加者通信は開始しない。
- D07-B（2026-09-13確定）: `/v1/chat/completions` + `store:false`、text-only purpose、API data-sharing opt-inなし、ZDR承認前はsynthetic/de-identified fixtureのみ、8s/attempt・15s総期限・retry 1回（timeout/408/429/5xxのみ）、input 2,500 tokens・output 256 tokens、per-capture $0.002、月額alert $5・hard stop $10、`cost_per_eligible_capture`/`cost_per_valid_soc` warning/hard-stop $0.05/$0.10、regionはprovider default global。参加者通信はZDR project設定とredaction/adapter fixture evidence完了まで停止する。
- D08（2026-09-13確定）: `basis_revision`はLoopごとの単調増加整数（初期1）。Receipt/ACKは`(loop_id,basis_revision)`でcurrent ACTIVE revisionだけを受理し、同一revisionのACKは冪等に1件へ収束、古いrevisionはgeneric stale outcomeで無変更とする。訂正は新revisionを作り旧ACKをActivation上無効化する。`deliveries`にはUTCの`scheduled_evaluation_at`を持たせ、`(loop_id,basis_revision,reason_code,scheduled_evaluation_at)`の一意制約を置く。作成・送信直前にACTIVE/current revision/newer decision/channel permissionを再検証し、stale行は送信しない。duplicate ACK、stale ACK、訂正、duplicate delivery、stale sendのfixtureを実装時に検証する。
- D09（2026-09-13確定）: Supabase Cronを5分間隔、1回最大25件、`next_evaluation_at`→`loop_id`順で処理する。Loop単位transaction lockを取得できない行はskipし、1回+retry 1回（1-5秒jitter）まで。`ACT`はACTIVE/current revision/`UNSATISFIED`/同等pendingなしだけでdelivery作成可。`SILENCE`は非ACTIVEまたは`SATISFIED`/`NO_LONGER_REQUIRED`でdelivery 0件。`DEFER`は`UNKNOWN`/`CONFLICT`/一時障害/安全な送信条件不成立で、15分後へ再評価を進めdelivery 0件。D08再検証を送信直前に行い、bounded batch・lock競合・retry exhaustion・decision table・stale・SILENCE/DEFER zero-deliveryを実装時にfixture検証する。
- D11（2026-09-21確定）: Raw削除、作成から最大7日、Account削除、再識別不能な集計値のみ保持、Supabase sanitized telemetry、外部crash/session replay/analytics SDKなしをADR-011で確定した。P1はSupabase ProのDaily Backup（保持上限7日）のみ、PITR・手動dump・外部backup・永続cacheなし。復元は隔離プロジェクトのみで、公式条件・DPA・削除／復元fixture evidenceがrelease gate。
- D12（2026-09-21確定）: 招待制の記名成人5名以上・10 loop、versioned consent、撤回時zero-processing、Critical Incident、誰でも緊急停止可能・Product OwnerとPrivacy/Security Ownerが共同再開、専用運用窓口をADR-012で確定した。実参加者募集は同意・incident evidence後。
- D13（2026-09-22確定）: ADR-001の全eligible分母と7日窓を採用し、10 loops・5 participants・5 matured contextsをデータ準備、Activation 60%以上等の`PROCEED P2`、35–59%等の`ITERATE P1`、2回後も35%未満等の`RECONSIDER WEDGE`を固定した。Measurement Lead、Privacy/Security Owner、Product Ownerの責任分界とHOLD/STOP権限もADR-013で確定した。SQL/evidence bundleはrelease gate。
- D10（2026-09-14確定）: ADR-010でIn-appを全ACTの正規かつ必須確認経路、Pushを補助チャネルとして固定した。明示的Push opt-in、iOS authorized permission、active consent、ACTIVE token、送信直前再検証を資格条件とし、provisional/ephemeralは除外。submission retryなし、15分後ticket単回reconcile、missing/errorは`RECEIPT_ERROR`、`DeviceNotRegistered`はinstallation無効化、permission/provider障害時はIn-appを維持する。opt-in撤回・logout・同意撤回・Account削除・token更新後は旧installationを使わず、payloadはRaw/PIIなし・推測不能なopaque参照に限定する。L08 fixtureと実機証跡はrelease gate。
- D14（2026-09-22 provider amendment）: Brevo Free（300通/日）のcustom SMTP、リージョン非固定、認証専用ドメイン、OTP値・本文非記録、Brevo log retention最短1か月・preview/tracking無効、アプリ匿名化送信ログ30日、再送3回/15分、3連続失敗または直近10分5件以上で失敗率20%以上なら停止、テスト送受信・DPA・ドメイン認証をADR-014で確定した。
- D07-R（redaction sub-gate, draft）: 直接識別子候補を列挙し、server-side adapter前の処理境界、fail-closed、fixture検証を定義する。日本語人名・住所の検出戦略、削除/placeholder、誤検知許容、証明閾値は人間ゲートまで未決。対象が確定するまで参加者/provider通信は開始しない。
- Loop B（plan）: 既存Beads `obo-main-gil.7-.13` と `.28` を依存順に使い、重複タスクを作らない。
- Loop B review: `bd dep cycles`、各BeadのAcceptance/Verification、D14→L00のブロッカーを確認する。

### D07-R plan（起票済み）

1. **`obo-main-gil.7.1` 直接識別子taxonomy**
   - Acceptance: 対象候補（個人名・メール・電話・住所・アカウント/端末識別子・識別子を含むURL/パス/ファイル名）ごとに、P1で検出可能か、未対応ならどう拒否するかがD07/ADR-007に記録される。
   - Verify: 仕様レビューで未対応カテゴリが暗黙のallowになっていないことを確認する。
   - Dependencies: なし。Files: `SPEC.md`, `docs/decisions/ADR-007-p1-ai-input-redaction.md`。
2. **`obo-main-gil.7.2` redaction adapter boundary**
   - Acceptance: server-sideのprovider adapter直前に一度だけredactionを適用し、`ApprovedAdapterInput`以外をadapterへ渡さない。Raw fallbackを持たず、未対応・曖昧・失敗は外部AIリクエスト0回になる。retryは同じredacted valueを再利用する。
   - Verify: adapter spyで、許可fixtureはredacted textだけを受け、拒否fixtureは到達回数0であることを確認する。
   - Dependencies: 1。Files: L03/L05のAI adapter境界とその単体テスト。
3. **`obo-main-gil.7.3` fixture/verification contract**
   - Acceptance: 日本語を含むallow/deny/ambiguous/error fixtureがあり、adapter受信値に直接識別子がなく、失敗時のgeneric re-entry経路が確認できる。
   - Verify: `npm test`のredaction/adapter fixture suiteと`bd lint`、`bd dep cycles`が成功する。
   - Dependencies: 2。Files: redaction fixture/test files、ADR-007の検証節。

依存順は `taxonomy → adapter boundary → fixture/verification`。provider/model benchmarkは3を通過したde-identified fixtureだけで行う。

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
| U04 | 未記載 | AIは「一つの承認済みプロバイダ」だが、プロバイダ、モデル、リージョン、利用目的、送信保持条件が未定 | L03/L05 のデータ境界 | D07 |
| U05 | 解決済み | ADR-006で4つのP1 scope、SECRET/SENSITIVE/UNCLASSIFIEDの決定的preflight、2,000文字上限、FAILED_SAFE/hold UXを固定 | L03 の allow/deny テスト | `docs/decisions/ADR-006-p1-sensitivity-preflight.md` |
| U06 | 解決済み | ADR-005でJWT必須の単一command Function、secret専用processor/scheduler、service keyの閉域利用を固定 | L02-L05 のRLS回避権限 | `docs/decisions/ADR-005-command-boundary-and-migrations.md` |
| U07 | 解決済み | `deliveries` にUTC `scheduled_evaluation_at`を持たせ、`(loop_id, basis_revision, reason_code, scheduled_evaluation_at)`を一意制約にする | L07-L08 の重複/stale配信防止をDBで証明 | D08 / ADR-008 |
| U08 | 解決済み | `basis_revision`、current revision ACK、訂正による旧ACK無効化、stale ACK戻り値を契約 | L06 Activation の正しさ | D08 / ADR-008 |
| U09 | 解決済み | bounded batch、Cron頻度、ロック方式、失敗/再試行、ACT/SILENCE/DEFER判定規則をADR-009で固定 | L07 の通知品質/負荷 | D09 / ADR-009 |
| U10 | 解決済み | ADR-010でExpo Push Service、明示的Push opt-in、iOS authorized permission、ACTIVE token、In-app必須経路、失敗時の`RECEIPT_ERROR`/installation無効化/単回reconcileを固定。実Pushはcredential・device・fixture・実機証跡後に有効化 | L08 | ADR-010 |
| U11 | 解決済み | Raw削除、7日上限、Account削除、集計値のみの保持、Supabase sanitized telemetry、外部報告SDKなし、Pro Daily Backupのみ・PITR/手動dump/外部backupなし、隔離復元をADR-011で固定。公式条件・DPA・fixture evidenceはrelease gate | L11 | ADR-011 |
| U12 | 解決済み | 招待制・記名成人5名以上・10 loop、versioned consent、撤回、Critical Incident、停止／再開権限、支援窓口をADR-012で固定。レポート責任者と判定閾値はADR-013で固定 | L12 とPASS判定 | ADR-012 / ADR-013 |
| U13 | 解決済み | ADR-005でLM00/LM10/LM20/LM30の正確なテーブル割当とL02/L08の追加境界を固定 | L02/L08の移行境界 | `docs/decisions/ADR-005-command-boundary-and-migrations.md` |
| U14 | 解決済み | Brevo Free、300通/日、リージョン非固定、custom SMTP、OTP／本文非記録、Brevo retention最短1か月・preview/tracking無効、匿名化ログ30日、再送・停止基準、DPA・ドメイン認証・テスト送受信をADR-014で固定 | L01 と外部P1ログイン | ADR-014 |

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
| 冪等性キーの物理欠落 | 中 | D08/ADR-008の一意制約をL07-L08のmigration/testで証明 |
| P2以降の先走り | 中 | Gate-locked backlogを実装キューに入れない |
