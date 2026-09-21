# ADR-013: P1レポート、分母、判定責任

## Status

Accepted（2026-09-22。SQLと実データ証跡はrelease gate）

## Context

D13は、ADR-001の固定語彙を使ってP1 Exit Artifactを再現可能にする契約である。分母を後から除外して見かけの成功率を上げず、成熟待ち・未完了・失敗を同じレポートで扱う必要がある。

## Decision

### 分母と集計

- Activationの分母は、`eligible_at` で固定した全 `eligible_open_loop` とする。Receipt未表示、未ACK、処理失敗、離脱を除外しない。
- Activationの分子は、`eligible_at` から7日以内に成立した、current basis revisionの有効な `OFFLOAD_RECEIPT_ACKED` とする。
- Matured successは、`activated_at` から7日後に、current valid factがvalid SOCまたはlegitimate Retireであり、material correctionとcritical trust incidentがない場合だけ成立する。
- AI推論、Push開封、時間経過、Raw削除、同意撤回はSOCまたはRetireに数えない。
- Ownershipは `OWNED` / `PARALLEL` / `UNKNOWN` の3状態とし、未回答を `OWNED` に補正しない。

### 初期チェックポイントと判定

- データ準備チェックポイントは、genuine eligible Open Loop 10件以上、参加者5名以上、matured context 5件以上とする。
- `PROCEED P2` は、Activation 60%以上、valid SOCを持つ参加者3名以上、2名以上にまたがる `OWNED` のmatured context 3件以上、false ACK・stale delivery・AI-only completion・cross-user violation・critical trust incidentが各0件の場合に限る。
- `ITERATE P1` は、Activation 35–59%、利用者がOBOの所有範囲を理解できない、またはparallel trackingが優勢な場合とする。主ボトルネックを1つだけ修正して再測定する。
- 2回のfocused iteration後もActivationが35%未満、またはparallel trackingが継続する場合は `RECONSIDER WEDGE` とする。
- 初期チェックポイントのmatured context 5件はデータ準備条件であり、`PROCEED P2` の最低判定値3件とは別の用途である。

### レポート凍結と責任

- 全 eligible loopのActivation 7日窓と、全 activated contextのmaturity 7日窓が完了するまで最終レポートを凍結しない。
- Measurement LeadがSQLとevidence bundleを作成し、Privacy/Security Ownerがデータ境界とincident状態を検証する。Product Ownerが最終判定を行う。
- Privacy/Security Ownerはcritical trust incidentが1件でもあれば `HOLD` / `STOP` を強制できる。

## Verification

- 合成fixtureで、未ACK・処理失敗・7日未満の成熟・current revision不一致が分母または成功値を誤って改善しないことを確認する。
- SQL snapshot、判定時点、ownership根拠、incident 0件の証跡をevidence bundleに含める。
- 実参加者データを使う前に、D07/D11/D12/D14のrelease gateと、必要な実装fixtureを通過させる。

## Implementation gate

D13の意思決定契約は確定した。集計SQL、evidence bundle、実データの7日窓完了、D10を含む各ADRの証跡は実装・リリース時のgateとして残す。
