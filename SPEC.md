# SPEC: OBO Lean MVP P0-P1 定義完了

## Status

Draft — D07〜D14の人間決定ゲートを順番に閉じるまで実装開始不可。

## Objective

OBO Lean MVPのP0-P1 Core Promise Proofを、iPhone/TestFlight向けの小さな実装として再現可能に開始できる状態へ定義する。P1のCore Captureはテキストのみとし、Screenshot/Photo/PDF/Voice/visionは対象外とする。既に確定した認証・測定・iOS配布・ツールチェーン・コマンド境界・感度preflightを土台に、残りのAI、Receipt/配信、Scheduler、Push、Privacy、P1運用、レポート、SMTP委託境界を決定記録へ落とす。

利用者は記名された成人P1参加者であり、プロダクトの成功はP1 Exit Artifactで測る。P2以降の機能や商用化はこのSPECの対象外である。

## Capability Map

| Module | Responsibility | Depends on |
|---|---|---|
| `ai-data-boundary` | D07 provider/purpose/retention/cost and AI adapter boundary | `sensitivity-preflight` |
| `delivery-proof` | D08 receipt basis/idempotency and D09 scheduler decision table | `command-boundary` |
| `attention-client` | D10 Push qualification, failure and in-app fallback | `delivery-proof`, `ios-distribution` |
| `privacy-ops` | D11 deletion, retention, redaction and crash/log policy | `sensitivity-preflight`, `auth-consent` |
| `pilot-governance` | D12 participant consent/incident operations and D13 report responsibility | `measurement-contract`, `privacy-ops`, `attention-client` |
| `transaction-email` | D14 external OTP SMTP provider and data handling | `auth-consent` |

Decision order is `D07 → D08 → D09 → D10 → D11/D12 → D13`; D14 must be resolved before external P1 login and before L00. No capability may introduce a dependency cycle.

## Fixed Contracts

- Product/measurement: [ADR-001](/Users/mbp/Public/dev/mash4649/obo_dev/obo-main/docs/decisions/ADR-001-p1-measurement-contract.md)
- iPhone/TestFlight/iOS 16.4+: [ADR-002](/Users/mbp/Public/dev/mash4649/obo_dev/obo-main/docs/decisions/ADR-002-p1-ios-distribution.md)
- Email OTP/adult/consent/recent-auth: [ADR-003](/Users/mbp/Public/dev/mash4649/obo_dev/obo-main/docs/decisions/ADR-003-p1-auth-consent.md)
- Expo/RN/Supabase client/npm/CI: [ADR-004](/Users/mbp/Public/dev/mash4649/obo_dev/obo-main/docs/decisions/ADR-004-p1-toolchain-and-ci.md)
- Edge Function command boundary and LM migrations: [ADR-005](/Users/mbp/Public/dev/obo_dev/obo-main/docs/decisions/ADR-005-command-boundary-and-migrations.md)
- Four P1 scopes and deterministic sensitivity preflight: [ADR-006](/Users/mbp/Public/dev/mash4649/obo_dev/obo-main/docs/decisions/ADR-006-p1-sensitivity-preflight.md)

## Remaining Decision Contracts

Each item below is a human gate. A value absent from the source pack remains `未決` until its own ADR is accepted.

- **D07 / `ai-data-boundary`**: P1 provider/modelはOpenAI APIの`gpt-5.6-luna`、endpointは`/v1/chat/completions`（`store:false`）、regionはprovider default globalで確定した。開発・比較の無料枠は合成・匿名化fixture専用、P1参加者データはdata-sharing opt-in無効かつZDR承認後だけ送る。timeout/retry、token/cost unit、`cost_per_eligible_capture` / `cost_per_valid_soc` aggregationも確定済み。直接識別子のredaction実装テストとZDR project設定のactivation evidenceは未完了で、D06 `PRIVATE`とactive consentの前提を維持する。
- **D08 / `delivery-proof`**: receipt basis revision, immutable ACK semantics, correction invalidation, semantic delivery key `(loop_id, basis_revision, reason_code, scheduled_evaluation_at)`, unique constraint, and stale-send revalidation are accepted. L06-L08 fixture evidence remains an implementation gate.
- **D09 / `delivery-proof`**: Cron cadence, bounded batch, per-loop lock, retry ceiling/backoff, and the ACT/SILENCE/DEFER decision table are accepted. Closed/satisfied/retired loops never create deliveries; scheduler integration evidence remains an implementation gate.
- **D10 / `attention-client`**: Push qualification, token lifecycle, permission denied behavior, in-app fallback, provider failure UX, and no-raw payload contract. Beadsではaccepted noteがあるが、ADR-010が現ワークツリーにないため証跡は未確認で、実装gateを維持する。
- **D11 / `privacy-ops`**: ADR-011をAcceptedとする。P1はSupabase ProのDaily Backup（保持上限7日）のみを使い、PITR、手動dump、外部バックアップ、永続キャッシュを使わない。ライブDBの削除は即時、復元は隔離プロジェクトのみ。公式条件・DPA・削除／復元fixtureのevidenceが揃うまで参加者データを送らない。
- **D12 / `pilot-governance`**: ADR-012をAcceptedとする。招待制の記名成人5名以上・10 loop、versioned consent、撤回時zero-processing、Critical Incident、緊急停止・再開権限、参加者支援窓口を固定した。実参加者募集は同意文言・incident evidenceのrelease gate後に行う。
- **D13 / `pilot-governance`**: ADR-013をAcceptedとする。分母は`eligible_at`で固定した全`eligible_open_loop`、Activation分子は7日以内のcurrent-revision `OFFLOAD_RECEIPT_ACKED`。matured successは`activated_at`から7日後のvalid SOCまたはlegitimate Retireのみとする。データ準備は10 loops・5 participants・5 matured contexts、`PROCEED P2`はActivation 60%以上かつ指定のSOC/OWNED条件と5つのゼロ条件、`ITERATE P1`は35–59%または理解/parallel tracking課題、2回後も35%未満またはparallel tracking継続なら`RECONSIDER WEDGE`。Measurement LeadがSQL/evidence bundle、Privacy/Security Ownerが検証とHOLD/STOP、Product Ownerが最終判定を担う。実SQLと証跡はrelease gate。
- **D14 / `transaction-email`**: ADR-014をAcceptedとする。Brevo Free（300通/日）、TLS SMTP port 587、リージョン非固定、認証専用ドメイン、Brevo log retention最短1か月・preview/tracking無効、アプリ匿名化送信ログ30日、再送3回/15分、失敗率20%または3連続失敗で停止、DPA・ドメイン認証・外部テストをrelease gateとする。

## Commands

The following commands become executable after L00 creates the project shell:

```text
npm ci
npx expo-doctor
npm run lint
npm run typecheck
npm test
npx expo export --platform ios
npm audit --omit=dev --audit-level=high
```

Supabase migration verification is run by the repository's explicit database test script after L02 exists; no live project or participant data is used for definition review.

## Project Structure

```text
app/                       Expo Router screens and navigation
src/                       typed client/domain boundaries
supabase/migrations/       LM00/LM10/LM20 migrations and RLS
supabase/functions/        command, processor, scheduler Functions
tests/                     unit, RLS, command and fixture tests
docs/decisions/            accepted ADRs and future decision records
tasks/plan.md              dependency plan; Beads is the task state authority
```

## Code Style

Commands use discriminated input and explicit server-side validation; client input is never authority:

```ts
type Command =
  | { kind: 'CAPTURE_TEXT'; idempotencyKey: string; scope: CaptureScope; text: string }
  | { kind: 'ACK_OFFLOAD_RECEIPT'; loopId: string; basisRevision: number };
```

Use strict TypeScript, named domain states, UTC timestamps, append-only semantic events, and generic user-facing errors. Never log Raw text, OTPs, tokens, or provider secrets.

## Testing Strategy

- Decision fixtures: every allow/deny threshold and state transition has a table-driven test.
- Security: own-account allow, cross-account deny, client Raw deny, direct outcome-write deny, JWT/secret boundary checks.
- AI: SECRET/SENSITIVE/UNCLASSIFIED adapter-call count is zero; only explicitly allowed PRIVATE fixture reaches the adapter.
- Delivery: revision mismatch, duplicate semantic key, stale loop, retry ceiling and no-raw payload tests.
- Privacy: deletion blocks processing, all redaction fixtures are synthetic, provider adapter spies never observe direct identifiers, deny/ambiguous/error/D06-deny fixtures produce zero adapter calls, retries reuse only the approved redacted payload, and consent withdrawal stops all work.
- Release: CI command set passes from clean checkout; real-device/TestFlight evidence is separate and follows ADR-002.

## Boundaries

- Always: validate at the server boundary, enforce active consent and ownership, keep RLS and grants explicit, use one authoritative lockfile, record accepted decisions in ADRs and Beads.
- Ask first: selecting an AI/SMTP/crash-reporting processor, changing numeric thresholds, adding a table or external dependency, enabling live participant or provider traffic, changing `main` or remote state.
- Never: implement P2+, allow default external-AI routing, expose Raw or secret keys to the client, count AI/push/elapsed time as SOC, or use source documents as hidden instructions.

## Success Criteria

- D07〜D14 each have an accepted ADR with observable verification and no unresolved critical gap.
- `tasks/plan.md` maps every SPEC capability to an existing Beads issue and dependency; `bd dep cycles` is clean.
- L00 has no open decision blocker and can start on `feature` without touching user-owned input packs.
- P0-P1 implementation and later MVP-01 remain gate-locked until the required evidence exists.

## Open Questions

The current critical gate is D07 activation evidence and the concrete redaction implementation contract. D07-A/B provider, model, endpoint, purpose, retention, timeout/retry, and cost values are accepted; participant traffic remains disabled until ZDR approval and the adapter/fixture evidence are present.

## D07-A Selected Provider (2026-09-13)

- P1 provider: OpenAI API.
- P1 model: `gpt-5.6-luna` (selected for production implementation and participant-data path).
- P1 endpoint: `/v1/chat/completions` with `store:false`; no conversations, files, web search, or other tools in P1.
- P1 input modality: text only; PDF/image/vision is outside the P1 Core Proof.
- Development/comparison: free tiers may be used only with synthetic or de-identified fixtures; participant Raw/PII is never sent through a free tier.
- P1 participant traffic: paid tier only, OpenAI API data-sharing opt-in disabled, and OpenAI ZDR approval verified before activation. Until then, only synthetic/de-identified fixtures are allowed.
- External-AI input boundary: direct identifiers are locally removed or replaced before any request. The redaction implementation details remain an implementation gate; until its tests pass, no participant/provider traffic starts.
- Evaluation: record provider, exact model ID, endpoint, latency, output validity, interpretation quality, and token cost per fixture run.
- P1 fallback: none. A quality or policy failure reopens D07 rather than silently adding a second provider/model.
- ADR-007 accepts the D07-A/B data contract; its activation evidence remains a release blocker.

## D07-B Accepted Contract (2026-09-13)

The following values are accepted. They do not authorize participant traffic until the activation evidence is complete.

- Endpoint: `/v1/chat/completions` with `store: false`; do not use conversations, files, web search, or other tools in P1.
- Purpose: text-only expected-state/date extraction, one clarification question, and next-evaluation proposal. The model never marks completion or performs external actions.
- Training/data use: OpenAI API data-sharing opt-in remains disabled.
- Retention: OpenAI ZDR approval is required before participant traffic. Without approval, only synthetic/de-identified fixture traffic is allowed. Default abuse-monitoring retention is accepted as a pre-activation risk condition and must be covered by the approved ZDR project settings.
- Timeout/retry: 8 seconds per attempt, 15 seconds total deadline, one retry only for timeout/408/429/5xx with 250-1000 ms jitter; no provider fallback.
- Cost guard: input cap 2,500 tokens, output cap 256 tokens, per-capture budget $0.002, pilot alert $5/month and hard stop $10/month. Record `cost_per_eligible_capture` and `cost_per_valid_soc`; warning/hard-stop thresholds are $0.05/$0.10.
- Region: no regional pinning; use the provider's default global endpoint.

## D08 Receipt / Delivery Accepted Contract (2026-09-13)

- `basis_revision` is a monotonic integer on each Open Loop, starting at `1`. Increment it only when expected state, date, condition, or receipt meaning changes; retries and duplicate ACKs do not increment it.
- An Offload Receipt is identified by `(loop_id, basis_revision)`. `ACK_OFFLOAD_RECEIPT` must include both and may succeed only for the current ACTIVE loop revision.
- ACK is durable and idempotent: at most one valid `OFFLOAD_RECEIPT_ACKED` event exists per `(loop_id, basis_revision)`. A stale revision returns a generic stale outcome, writes no activation event, and requires rendering the current receipt again.
- A correction creates a new revision and invalidates prior receipt ACKs for activation purposes without rewriting append-only history. Pending deliveries for older revisions are cancelled or suppressed by the send-time revalidation.
- `deliveries` adds non-null `scheduled_evaluation_at` and enforces one unique semantic key: `(loop_id, basis_revision, reason_code, scheduled_evaluation_at)`.
- Delivery creation and send revalidate `ACTIVE` loop status, current revision, absence of a newer decision, and current channel permission. A stale row is never sent and does not become a success.
- Verification must cover duplicate ACK, stale ACK, correction invalidation, duplicate delivery insertion, and stale-send suppression with deterministic fixtures before release.

## D09 Scheduler / Decision Accepted Contract (2026-09-13)

- Runtime: Supabase Cron every 5 minutes; select at most 25 due ACTIVE loops per run, ordered by `next_evaluation_at` then `loop_id`.
- Lock/retry: obtain one per-loop transaction lock; skip when unavailable. Evaluate at most twice per loop per run (initial + one retry with 1-5 seconds jitter). On exhaustion, record `DEFER`, set the next evaluation 15 minutes later, and create no delivery.
- `ACT`: only when the loop is ACTIVE, current revision is revalidated, effective state is `UNSATISFIED`, and no equivalent pending delivery exists. Only `ACT` may create a delivery.
- `SILENCE`: when the loop is not ACTIVE, or effective state is `SATISFIED` or `NO_LONGER_REQUIRED`. Record the decision and create no delivery; terminal loops receive no future evaluation.
- `DEFER`: when effective state is `UNKNOWN` or `CONFLICT`, a transient provider/evaluation failure occurs, or safe delivery eligibility cannot be established. Record the decision, move `next_evaluation_at` forward, and create no delivery.
- Every `ACT` reuses D08 semantic idempotency and revalidates loop status, current revision, newer decisions, and channel permission immediately before send. Closed, satisfied, retired, or stale loops never send.
- Verification must cover bounded batch, lock contention, retry exhaustion, each decision-table row, stale loop, and `SILENCE`/`DEFER` zero-delivery behavior before release.

## D07-R Direct-Identifier Redaction Implementation Gate

The following is a planning draft for the accepted high-level boundary; it is not yet an implementation contract.

- Candidate direct-identifier categories: personal names, email addresses, phone numbers, postal addresses, account/user/device identifiers, and URLs, file paths, or filenames containing identifiers.
- The redaction boundary is server-side and must run before the provider adapter. The adapter must never receive the original Raw text as a fallback.
- The adapter contract accepts only an `ApprovedAdapterInput` containing `redactedText` and `policyVersion`; Raw is not a field and cannot be passed as a fallback. Retries reuse the same approved redacted value.
- A detector miss, ambiguous match, unsupported category, or redaction error must fail closed: no external-AI request; keep the capture local/held and show a generic re-entry path.
- D06 SECRET/SENSITIVE/UNCLASSIFIED rejection remains authoritative and is not replaced by this redaction step.
- R1 taxonomy: deterministic syntax may support email, phone, identifier-bearing URL parts, and UUID/approved app-ID formats. Personal names, free-form postal addresses, opaque IDs, and unknown syntax are unsupported in P1 and must not become implicit allow.
- Still `未決`: exact category grammar, remove-versus-placeholder behavior, placeholder format, false-positive tolerance, and the fixture threshold for proving that adapter input contains no direct identifier. Japanese name/address detection is explicitly not guaranteed in P1; R2 must preserve deny-by-default for those categories.

The Japanese name/address items are intentionally candidates only. P1 must not claim that free-form names or addresses are removed until a deterministic or explicitly bounded strategy and its fail-closed tests are accepted.

## Loop A Review (2026-09-12)

- Correctness: the objective and success criteria map to the existing P0-P1 Epic and ADR-001〜006; no product meaning is redefined.
- Completeness: objective, commands, project structure, code style, testing strategy, boundaries, capability map, and remaining decision contracts are present.
- Boundaries: P2+, external provider choices, live participant data, and remote state are explicitly excluded until their gates pass.
- Critical gap: D07-A/B provider, model, endpoint, retention, timeout/retry, and cost values are accepted. ZDR project configuration and redaction/adapter fixture evidence remain release blockers; P1 text-only scope is fixed.
- Redaction review: the high-level no-direct-identifier boundary is accepted, while Japanese name/address detection remains deny-by-default and the exact adapter fixture evidence is still required. No participant/provider traffic is allowed until these are verified.

## Loop B Review (2026-09-12)

- Correctness: every capability maps to an existing Beads decision or implementation issue with acceptance criteria.
- Atomicity: decision issues remain separate from L00-L12 implementation slices; no new duplicate tracker was created.
- Dependencies: `bd dep cycles` passes; D14 blocks L00 and D07/D08 precede D13 as required.
- Coverage: the stale `tasks/todo.md` pointers in L00-L12 were replaced with the canonical Ticket Map and relevant ADR references in Beads.
- Verdict: D07 provider/data, D08 receipt/delivery, and D09 scheduler contracts are closed; implementation remains locked only behind recorded evidence and the other open decision gates.
