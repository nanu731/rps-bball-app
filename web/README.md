# TeamStats web pilot

Responsive React/TypeScript workspace using the existing maroon sports-ledger
visual direction. The native project remains preserved legacy work.

Court locations automatically select two or three points using the displayed arc
and straight corner lines; on-line selections count as two. The value remains
manually adjustable, and only Make/Miss records an attempt. Keyboard location
controls use the same rule. Existing recorded values are not recalculated.
This follow-up passed 15 unit checks, the build and all seven browser-local pilot
journeys, including automatic selection at phone/tablet widths and manual override.

## Run locally

Node 22.12 or later. Exact dependencies are pinned in the lockfile.

```sh
npm ci --prefix web --ignore-scripts
npm --prefix web run dev
npm --prefix web test
npm --prefix web run build
npm --prefix web run test:browser
```

Browser tests use an already installed Chrome through Playwright. No provider,
Google, SMS, schedule or production deployment is enabled by these commands.
Public Supabase URL/publishable-key configuration can be supplied through the
connection screen or `.env.local`; privileged keys are rejected. Never commit
private configuration or real records.

## Boundaries and current evidence

- **Browser-local**: practice plans and print/PDF, configurable nine shooting
  spots, FT conditioning, versioned collection templates, player/team court
  capture, corrections/Undo, running reference clock, and independent manual
  box scores, paired possessions and player paint touches. Local and explicitly
  labeled synthetic-demo ledgers are separate. Neither uploads automatically.
- **Existing shared contracts**: verified Auth, active membership and current
  server authority, protected owner administration, manual dataset draft/save,
  independent completion, submission, review, accepted viewing and correction.
- **Prepared new shared contract**: migration `202611110001_web_sessions.sql`
  and ADR0009 define practice/capture snapshots, explicit recorder/clock authority,
  immutable publication history and duplicate-safe operation receipts. The web
  bridge fails closed if unavailable. This migration is **not activated hosted**.
- **Executed checkpoint evidence**: 14 domain/server checks and focused Chrome
  journeys exercise local/demo durability, actual signed isolated Auth/PostgREST
  practice/capture review, the four independent manual datasets, accepted viewing,
  denied visibility, correction lineage, clock assignment, interrupted replies and
  remount recovery. A fresh isolated PostgreSQL cluster replayed all 21 source
  migrations and passed 64 SQL checks using Auth platform stand-ins. Signed-user
  browser evidence is separate. No hosted or real-device acceptance is inferred.

Blank counts remain missing; explicit zero stays zero. Scoring contradictions are
calm, nonblocking draft guidance. Recorded shots do not establish complete game
coverage or replace manually entered statistics. New collection definitions require
coach input; placeholders are not approved basketball rules.

Local browser saves require Web Locks and revision checks. Browser storage can be
lost; explicit recovery download/import is not a hosted backup or full offline
synchronization. Shared uncertain writes retain their original operation for
receipt lookup/reconciliation, rather than silently resubmitting a new mutation.

`shared-local.spec.ts` skips without an ignored private synthetic loopback fixture.
It must never be pointed at real student records or a hosted project. Physical
hardware, actual screen-reader interaction, other browsers, coaching protocol,
real roster/brand assets, hosted migration compatibility/activation and release
acceptance remain distinct gates.

## Activation remains separate

Do not apply the prepared migration automatically. Recheck the intended hosted
baseline, exposure/RLS, current permissions, native-client handling of new capability
names and migration dependencies before any authorized activation. Local replay of
21 source migrations does not prove a hosted upgrade from its older baseline.

No email/SMS sender, Google/media service, recurring task or deployment is activated.
Coach rules, real roster/branding, pilot participants/roles, browser/device rehearsal,
backup/access/retention/recovery and privacy/deletion policy remain owner decisions.
Actual mobile software keyboards, screen readers and Safari require separate
acceptance; a reduced Chrome viewport and accessibility tree are useful proxies.

## Acceptance checkpoint — 2026-11-11

Application source: `beb7a12`. Built artifact tested with installed Chrome at the
local preview, including 390px phone, 1024px tablet, desktop, light/dark, reduced
motion and enlarged root text. A shortened viewport tests occlusion/reachability;
it does not reproduce a mobile software keyboard.

| Evidence | Actual result |
|---|---|
| TypeScript / Vite build | Passed; bundle-size advisory remains (about 566 KB JS, 159 KB gzip). |
| Domain / server unit checks | 14 passed. |
| Compiled-browser acceptance | 22 passed, zero failures/skips/flaky cases in the final batch. |
| SDK account switch / sign-out | Separate actual signed local development-driver check passed; not counted among the 22 compiled checks. |
| Fresh database replay | 21 source migrations and 64 web SQL checks passed in a new isolated cluster with Auth platform stand-ins. |
| Signed service journeys | Actual isolated GoTrue, PostgREST and PostgreSQL; six synthetic identities, existing test grants and clearly labeled fixtures. |
| Independent visual review | 94 / 97 / 95, average 95.33, within the recorded compiled Chrome/synthetic scope. |
| Existing no-deploy CI | [Backend/recovery run passed](https://github.com/nanu731/rps-bball-app/actions/runs/43114298056) on `feeee32`; subsequent app changes leave backend/workflow files unchanged. Web browser evidence above ran locally. |

The signed journeys cover practice plan/save/reopen, shooting/FT and all four
template kinds, recorder/clock separation, capture/Undo, submission, independent
review, accepted viewing and correction lineage. Manual box scores, both independent
possessions and player paint touches complete/review separately. Tests also cover
missing/zero values, calm draft scoring checks, denied working snapshots, account
concealment, interrupted command receipts, stale-tab rejection, uncertain owner
commands, remount recovery and keeping unsaved input when recovery storage fails.
Correction comparison shows previous/proposed saved values without zero conversion.

Earlier failures remain in private evidence: a fractional-clock UI mapping, a false
Save warning and an obstructing shared Save bar were repaired and checked. One
concurrency test read storage before Save settled; it now awaits the real rejected
stale write before inspecting the durable winner. The final 22-case run passed.
An existing export test moved its clock backward to a fixed DST date; a locally
reproduced test-only monotonic future-DST fix made the unchanged CI pass.

This accepts the synthetic Chrome scope, not deployment or release. Remaining gates:

- Coach-defined spot labels/layout, drill and event rules, clock rules, actual roster
  and identity assets, pilot participants/roles and target-device rehearsal.
- Hosted upgrade/dependency review, native-client compatibility with added capability
  names, fresh hosted permissions/Auth configuration and authorized activation.
- Actual Safari/mobile keyboards, screen-reader interaction, physical devices and
  real-roster revision/label acceptance; accessibility-tree evidence is separate.
- Owner-selected backup destination/access holder/retention/recovery objectives and
  privacy/deletion/reporting policy; no hosted disaster-recovery process is verified.

No native container was read or written during this web pass. All three protected
Xcode files' working bytes and staged entries matched the retained start baseline.
Original native record counts were not independently re-audited; no automatic
import, upload or temporary-identity conversion was performed.

## Plain-language follow-up — 2026-11-11

The follow-up to `3bad286` replaces technical screen copy with basketball tasks:
My drafts, Team, after-game stats, stat-tracking templates and contextual recovery
steps. Browser-only backups are explicitly separate from team entries. Owner
connection settings and member account codes remain available through disclosures.
Save confirmations distinguish browser-only work, saved team drafts, waiting for
review and publication. Correction approval identifies the requester as the editor;
rejected results are not described as unreviewed. Existing permissions, protocol
values, records, validation and review/history behavior remain unchanged.

The final compiled build (`index-DKkdM8S9.js`) passed 25 installed-Chrome checks,
including actual signed isolated Auth/PostgREST journeys. The build and 16 unit
checks passed. Phone, tablet, desktop, light/dark, enlarged text and recovery
screenshots were inspected privately. A separate development-driver check covers
SDK account switching/sign-out; it is not part of the compiled-browser count.
The independent bounded source review closed its six wording findings. Intermediate
old-label/ambiguous-locator test failures are retained privately, not presented as
product defects or final passes. No hosted/provider activation occurred.

Applied design guidance was limited to task copy, consistency, progressive
help and rendered critique. Taste 2.5.1's marketing heroes, photography/effects,
full-screen sections and marketing finish gate do not apply to these entry screens.
The approved maroon layout, touch targets, court selection and clock dropdown stay.

| Actual change | Relevant UX principle |
|---|---|
| Owner connection/member-code setup is disclosed only when needed. | [Hick’s Law](https://lawsofux.com/hicks-law/): fewer routine choices. |
| Short task labels replace repeated architecture explanations. | [Cognitive load](https://lawsofux.com/cognitive-load/): less irrelevant interpretation. |
| Recovery names the next safe action while retaining uncertain-write checks. | [Tesler’s Law](https://lawsofux.com/teslers-law/): simplify guidance without hiding necessary complexity. |
| My drafts, Settings, Save and review states use familiar controls and language. | [Jakob’s Law](https://lawsofux.com/jakobs-law/): preserve familiar expectations. |
| Shorter actions retain existing touch sizes; enlarged-text Save/column traversal is checked. | [Fitts’s Law](https://lawsofux.com/fittss-law/): preserve reachable targets rather than shrink controls to fit copy. |

These are scoped browser and synthetic-service results. Hosted upgrade/delivery,
Safari, real mobile keyboards, actual screen-reader interaction, physical devices,
coach definitions and real-team pilot acceptance remain separate gates. The existing
bundle-size advisory remains; no performance or release-readiness claim is added.
