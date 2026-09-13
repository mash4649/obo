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

- **D07 / `ai-data-boundary`**: D07-Aのprovider/model選定を再オープンし、Mistral / Gemini / OpenAI / Groqを候補とする。開発・比較の無料枠は合成・匿名化fixture専用、P1参加者データは有料プランとtraining opt-out、ZDRまたは同等の保持制御を確認した候補だけに送る。外部AIへは、Rawからローカルで直接識別子を置換・除去したテキストだけを送信することを確定する。対象項目、置換方式、誤検知時の扱いは未決とし、D07-Bの purpose, no-training/no-human-review terms, timeout/retry, token/cost unit, and `cost_per_eligible_capture` / `cost_per_valid_soc` aggregationと一緒に詰める。D06 `PRIVATE`とactive consentの前提は維持する。
- **D08 / `delivery-proof`**: receipt basis revision, immutable ACK semantics, correction invalidation, semantic delivery key `(loop_id, basis_revision, reason_code, scheduled_evaluation_at)`, unique constraint, and stale-send revalidation.
- **D09 / `delivery-proof`**: Cron cadence, bounded batch, per-loop lock, retry ceiling/backoff, and a decision table for ACT/SILENCE/DEFER. Closed/satisfied/retired loops never create deliveries.
- **D10 / `attention-client`**: Push qualification, token lifecycle, permission denied behavior, in-app fallback, provider failure UX, and no-raw payload contract.
- **D11 / `privacy-ops`**: Raw/account/audit/telemetry retention, deletion timing, anonymization, backup/cache scope, crash/log redaction, and external reporting vendor. No Raw/token/PII in telemetry or crash breadcrumbs.
- **D12 / `pilot-governance`**: recruitment and consent wording, five-person cohort handling, withdrawal/incident runbook, critical incident definition, pause/stop authority, and participant support channel.
- **D13 / `pilot-governance`**: report SQL, denominator from ADR-001, evidence bundle, owner, review date, and one of `PROCEED P2` / `ITERATE P1` / `RECONSIDER WEDGE`.
- **D14 / `transaction-email`**: custom SMTP provider, processing region, email/OTP log retention and deletion, DPA/processor approval, outage stop rule, and test delivery evidence.

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
- Privacy: deletion blocks processing, redaction fixtures contain no Raw/token/PII, provider adapter spies never observe direct identifiers, deny/error fixtures produce zero adapter calls, and consent withdrawal stops all work.
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

The current critical gate is D07-A provider/model selection plus the concrete redaction contract. The previous Mistral/Global choice is provisional and reopened for comparison with Gemini, OpenAI, and Groq. Do not infer provider, model, retention, human-review terms, timeout/retry, cost ceiling, identifier categories, replacement format, or redaction-failure behavior before the benchmark and next human decision.

## D07-A Working Shortlist (reopened 2026-09-13)

- P1 provider candidates: Mistral AI API, Gemini API, OpenAI API, and Groq API.
- P1 model and endpoint: `未決`; the earlier Mistral `mistral-small-2603` / Global proposal is a benchmark candidate, not an accepted contract.
- P1 input modality: text only; PDF/image/vision is outside the P1 Core Proof.
- Development/comparison: free tiers may be used only with synthetic or de-identified fixtures; participant Raw/PII is never sent through a free tier.
- P1 participant traffic: paid tier only, with provider-specific training opt-out and ZDR/equivalent retention control verified before activation.
- External-AI input boundary: direct identifiers are locally removed or replaced before any request. The identifier list, replacement format, and fail-closed behavior remain `未決`; until those are accepted, no participant/provider traffic starts.
- Evaluation: record provider, exact model ID, endpoint, latency, output validity, interpretation quality, and token cost per fixture run.
- P1 fallback: none. A quality or policy failure reopens D07 rather than silently adding a second provider/model.
- ADR-007 remains unaccepted until the candidate benchmark and D07-B data contract are closed.

## D07-R Direct-Identifier Redaction Draft (not accepted)

The following is a planning draft for the accepted high-level boundary; it is not yet an implementation contract.

- Candidate direct-identifier categories: personal names, email addresses, phone numbers, postal addresses, account/user/device identifiers, and URLs, file paths, or filenames containing identifiers.
- The redaction boundary is server-side and must run before the provider adapter. The adapter must never receive the original Raw text as a fallback.
- A detector miss, ambiguous match, unsupported category, or redaction error must fail closed: no external-AI request; keep the capture local/held and show a generic re-entry path.
- D06 SECRET/SENSITIVE/UNCLASSIFIED rejection remains authoritative and is not replaced by this redaction step.
- R1 taxonomy: deterministic syntax may support email, phone, identifier-bearing URL parts, and UUID/approved app-ID formats. Personal names, free-form postal addresses, opaque IDs, and unknown syntax are unsupported in P1 and must not become implicit allow.
- Still `未決`: exact category grammar, remove-versus-placeholder behavior, placeholder format, false-positive tolerance, and the fixture threshold for proving that adapter input contains no direct identifier. Japanese name/address detection is explicitly not guaranteed in P1; R2 must preserve deny-by-default for those categories.

The Japanese name/address items are intentionally candidates only. P1 must not claim that free-form names or addresses are removed until a deterministic or explicitly bounded strategy and its fail-closed tests are accepted.

## Loop A Review (2026-09-12)

- Correctness: the objective and success criteria map to the existing P0-P1 Epic and ADR-001〜006; no product meaning is redefined.
- Completeness: objective, commands, project structure, code style, testing strategy, boundaries, capability map, and remaining decision contracts are present.
- Boundaries: P2+, external provider choices, live participant data, and remote state are explicitly excluded until their gates pass.
- Critical gap: D07-A provider/model/endpoint and D07-B retention/human-review/timeout-retry/cost values remain intentionally unresolved and require the next human gate. P1 text-only scope is fixed; ADR-007 remains unaccepted.
- Redaction review: the high-level no-direct-identifier boundary is accepted, but Japanese name/address detection and the exact fail-closed contract remain critical D07 blockers. No participant/provider traffic is allowed until these are accepted.

## Loop B Review (2026-09-12)

- Correctness: every capability maps to an existing Beads decision or implementation issue with acceptance criteria.
- Atomicity: decision issues remain separate from L00-L12 implementation slices; no new duplicate tracker was created.
- Dependencies: `bd dep cycles` passes; D14 blocks L00 and D07 precedes D13 as required.
- Coverage: the stale `tasks/todo.md` pointers in L00-L12 were replaced with the canonical Ticket Map and relevant ADR references in Beads.
- Verdict: plan is ready for the reopened human D07-A provider comparison; implementation remains locked.
