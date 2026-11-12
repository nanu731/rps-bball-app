# TeamStats — current direction and working agreement

Updated: 2026-11-11. Status: primary platform and pilot scope confirmed; detailed capture rules pending.

## Authority and reading order

This is the entry point for the new practice-and-game web direction. Read this
file, AGENTS.md and PRODUCT.md before planning or implementation. For UI tasks,
read DESIGN_SYSTEM.md and the applicable portions of DESIGN.md.

Current owner answers override this file. Confirmed requirements and proposed
technical choices are distinguished below. PRD.md, PROJECT_CONTEXT.md, WORKFLOW.md
and READINESS.md retain the previous native product's requirements/evidence;
they are historical reference, not a queue to finish before web work. Existing
code, backend contracts and tests describe actual implementation, not proof that
a proposed web feature already works. Adopted ADRs still explain the existing
system; identify conflicts before changing its contracts.

## Purpose and audience

Help one high-school basketball team plan practices, record useful practice/game
observations, review results and use them in coaching decisions. Approximately
25 regular users were previously anticipated, including about 10 players and
15 staff; simultaneous recorders and pilot participants remain unconfirmed.
The operating budget remains strictly $0.

## Confirmed new direction

- Develop the blueprint for a web app with Add Practice beside Add Game.
- Practices need plans available as PDFs before practice and manager collection
  during practice. Twelve-minute shooting needs individual results at nine
  coach-defined spots; free-throw conditioning needs makes and attempts.
- Coaches change collection priorities through the season. Deflections, charges,
  missed box outs and event times are examples from the coach's notes.
- Preserve coach-supplied names such as Blackjack, Drag deep, one-man-down,
  solo/tandem, three-against-four and four-against-five. Do not invent their
  instructions, scoring rules or conclusions about their effectiveness.
- Court entry should offer a player header, a location tap, then Make/Miss.
  Other managers can collect other game observations. Recording workload is a
  test criterion, not grounds to reject this interface.
- Preserve the approved ESPN-inspired sports ledger and Rutgers Prep maroon
  direction, calm scoring guidance and horizontally swipeable statistics with
  hidden horizontal indicators. Preserve accessible alternatives to gestures.
- Use Impeccable, apple-design and UI/UX Pro Max as described below.

## Owner-confirmed decisions — 2026-11-11

| ID | Decision |
|---|---|
| Q1 | Responsive React/TypeScript web app for phone, iPad and desktop, using the existing Supabase backend. Preserve the Swift app as legacy work, not a parallel active product. |
| Q2 | First web pilot includes practice plans/PDFs, nine-spot player shooting, free-throw conditioning, game shot recording and selected game events, PLUS manual box scores, possessions and player paint touches. |
| Q3 | Our-team game shots require player selection; opponent shots are team-only. Include a running game clock in the app. Practice shooting remains player-attributed. |
| Q4 | Support simple reusable coach-selected templates using counts, makes/attempts, timed events and notes. Preserve the definition used for earlier sessions. |

Playbook, practice-video delivery, scouting, Sheets delivery, OCR and voice are
not prerequisites for this first web pilot. Their prior requirements/history are
retained for later scope review; they are not silently deleted or claimed ported.

Before detailed capture implementation obtain:

- TODO_NINE_SPOT_LAYOUT: coach's locations and labels, court dimensions/rules.
- TODO_DRILL_PROTOCOL: whether each attempt or station totals are entered; sets,
  rotations, simultaneous baskets, collector responsibility and counting rules.
- TODO_GAME_CLOCK_RULES: period lengths/overtime, who starts/stops/corrects the
  clock, and how other managers share it. The running clock is confirmed; exact
  operation is not. It is a manager-maintained reference, not verified official
  scoreboard synchronization. Drill countdown, video offset and device time
  remain separate; do not infer one from another.
- TODO_EVENT_DEFINITIONS: e.g. when a missed box out or successful stunt counts,
  whether attribution is player/team and whether opportunities are observed.
- TODO_PILOT_DEVICES_AND_CRITERIA: actual browsers/devices, manager rehearsal and
  acceptable entry effort/error rates; do not invent numerical success thresholds.

## Proposed product flow

Create practice/game → choose plan and collection focus → assign recorder(s) →
record → inspect missing values and corrections → explicit submission/review →
team results. Existing server authorization must be checked for compatibility.

Practice: ordered drill plan → printable page/PDF → player/spot makes and
attempts → corrected, reviewed session results. Use the same session identity
between plan and results. Nine-spot geometry is coach-provided.

Game: choose tracking modules → selected player/team → provisional court marker
→ geometry-selected 2/3-point value (manually adjustable) and Make/Miss → recorded
event with Undo. New location selections use the drawn arc and corner lines;
on-line taps select two points. Existing recorded values are not recalculated. Keep free
throws off the court as per-attempt or agreed makes/attempts entry. A location
tap alone must not persist an attempt. Retain a visible selection and recent
records so a wrong player, value or location can be corrected.

Our-team game shots are player-attributed; opponent shots are team-only. Practice
player results are required. Preserve historical player attribution. Manual box
scores, possessions and player paint touches are explicitly included in the web
pilot, retaining their after-game entry and independent reconciliation. Court
shots do not replace or reconstruct those datasets; never sum sources twice.

The running game clock accompanies capture. Store the period and displayed clock
reading associated with an event separately from device timestamps. Define how
recorders share clock authority and handle pauses, corrections or disconnection
before dependent implementation; do not silently rewrite older event times.
Period selection uses a dropdown: Quarter 1–4 and Overtime. New games start at
Quarter 1; older saved labels remain intact until the user explicitly sets a period.

## Data and analysis rules to retain

- Store makes and attempts, derive percentages; zero attempts is unavailable.
  Team percentage uses total makes / total attempts, not average percentages.
- Preserve missing/untracked versus observed zero; no universal blank-to-zero
  conversion. Existing possession completion rules are dataset-specific.
- Distinguish recorded shots from complete coverage. Matching score alone does
  not establish attempt coverage. Prior manager-confirmation plus authorized
  review is the existing contract; validate its fit for the new product.
- Keep practice and game results distinguishable. Version collection definitions
  so later changes do not reinterpret earlier observations.
- Store stable identities and source/proposal provenance. Corrections and review
  must preserve accepted history and enforce current server authority.
- Spot shooting alone cannot establish which plays should run through which
  players. Such analysis needs coach-defined play opportunities, roles, outcomes
  and context; descriptive comparisons are not causal recommendations.

## Confirmed platform and proposed implementation details

React + TypeScript and existing Supabase are confirmed. Vite is the proposed
build tool; use a responsive touch-friendly browser UI and a small PWA shell
if installability is needed; existing Supabase Auth/Postgres/RPC/RLS contracts
where compatible; SVG court; browser print-to-PDF; CSV export initially.
Cloudflare Pages Free is a frontend-host candidate, not proof all services are free.

Offline capture needs an explicit bounded design: local journal, clear pending /
server-confirmed states, duplicate prevention, connection recovery and authority
checks at submission. Browser storage is not an independent backup. Do not add
full offline synchronization or promise uninterrupted background clock operation.
Clock recovery after backgrounding, refresh and connection loss needs explicit
verification; the confirmed running-clock feature must not be dropped as a shortcut.

OCR and voice are optional proposal generators, not dependencies for manual entry.
Photo → template/cell recognition → field mapping → validation → human review →
draft → authorized publication. An LLM is optional; never invent missing values.
Google Drive is optional intake, not the authoritative database. Tesseract.js must
not be presented as a proven handwritten-form solution. Apple Vision is native,
not a browser API. Cloud OCR/audio require an authorized privacy and verified $0
route; free allowances do not prove a hard spending cap. Local models require
actual target-device capability/accuracy evidence.

## UI/UX agreement

Impeccable: task flow, hierarchy, copy, loading/empty/error/recovery states and
bounded audit/polish. apple-design: predictable touch feedback and purposeful,
reduced-motion-aware interaction. UI/UX Pro Max: responsive web layout,
accessible controls, forms and chart guidance. These are complementary references,
not competing design systems or mandates to install dependencies.

Existing DESIGN_SYSTEM.md owns the provisional palette; DESIGN.md records the
approved native visual evidence. Translate the visual direction to semantic HTML,
keyboard/screen-reader access, zoom/reflow and touch input. SwiftUI-specific
modifiers and platform controls are examples, not web implementation requirements.
Use one shared token/component system. Do not regenerate the brand or add a second
palette, generic dashboard template, decorative gradient/glass, or invented assets.
Official hex/logo and real roster remain owner-provided.

Immediate press feedback must not execute consequential writes on pointer-down.
Calm informational scoring notices remain nonblocking; invalid values, failed
saves and denied access need clear, actionable treatment. Verify actual light/dark,
small/large layouts, contrast, court touch targets, keyboard Save, scrolling,
reduced motion and screen-reader paths. Prototype/native passes do not accept web UI.

## Working sequence and chat roles

1. Q1–Q4 are resolved above. Define remaining clock, drill and collector rules;
   retain explicit TODOs for coach facts that are still unknown.
2. Define one real practice protocol and its desired results. Prototype the
   approved court/player flow without manufacturing coach facts.
3. Plan the smallest approved web slice end-to-end: create session, record,
   correct/Undo, save/reopen, review and results. Define its checkable acceptance.
4. Implement/test that slice on actual target browsers, including authorization,
   interrupted connection, duplicate handling, touch speed and accessibility.
5. Deliver the rest of the approved pilot: running-clock shot capture, selected
   game events, reusable templates and after-game box scores, possessions and
   player paint touches. Smaller delivery slices do not remove pilot features.
   Then evaluate OCR/voice separately against manual effort. Expand analysis only
   with evidence.
6. Re-scope release dates after platform/pilot decisions; the previous November 17
   target is not a verified delivery estimate for this new direction.

Planning chat: requirements, decisions and prompts. Implementation chat: one
integrator owns code, tools, browser operation, tests and commits. Use relevant
Matt Pocock skills for research/diagnosis/TDD/review; ECC for a finite queue and
compact checkpoints; LLM Council for consequential unresolved tradeoffs, not every
routine choice. Temporary read-only reviews are sufficient; avoid permanent
competing orchestrators.

Routine planning: GPT-6.1 Sol Medium. Implementation: Codex GPT-6.1 Sol High,
Fast mode as selected by owner. Every generated prompt states app/model/effort.
Continue authorized independent tasks around blockers; never report simulated,
build-only or source-only evidence as deployed/real-device acceptance.

## Preservation and service boundaries

Preserve native source, tests, original local records, temporary identities and
all pre-existing personal/project working bytes AND staged entries. Do not
reorganize or delete legacy work as part of documentation cleanup. Never auto-upload
local data or silently convert temporary players to real roster identities.
Do not repeat bootstrap, apply pending migrations, activate providers/schedules,
spend money or release merely because this direction document exists.
Never commit privileged credentials, student records or private internal tickets.
Security/recovery requirements remain applicable; existing native verification
is reusable evidence only for unchanged contracts and its recorded environment.

## Web implementation evidence — 2026-11-11

The implementation branch now contains the responsive pilot in web/. Browser-local
and explicit synthetic-demo ledgers stay separate from shared records. Actual signed
isolated Auth/PostgREST journeys exercise practice/capture and the existing manual
statistics lifecycle; prepared new contracts are not activated hosted. See
web/README.md and ADR0009 for guarantees and activation boundaries. A fresh isolated
cluster replayed the current 21 migrations with 64 web SQL checks; those tests use
Auth platform stand-ins and are distinct from signed browser evidence.

Compiled Chrome/synthetic acceptance is recorded in web/README.md: source beb7a12,
14 unit checks, 22 compiled-browser checks, separate signed local account-switch
proof and three independent visual scores averaging 95.33. This accepts only the
recorded local/isolated scope. It does not resolve coach facts or owner decisions,
establish Safari/mobile-keyboard/physical-device/screen-reader acceptance, or
authorize hosted activation, native data upload, provider spending or release.

A later plain-language follow-up to `3bad286` keeps the same web pilot behavior and
approved visual direction, with task labels and distinct browser/team/review states.
Its final build, 16 unit checks and 25 compiled Chrome/signed-isolated checks passed;
see web/README.md for the scoped evidence and design-principle mapping. This does not
activate hosted contracts or resolve the outstanding coach/device/policy gates.

## Authorized nonproduction pilot follow-up

The owner confirmed a web-only pilot: preserve native source/local records, but do
not maintain old native online-client compatibility as an additional active product.
Login-first team access and a minimal selective hosted practice/game/clock upgrade
are authorized for the intended Free nonproduction project after fresh review and
synthetic rehearsal. This does not authorize bootstrap reruns, blanket migrations
14–20, real-student uploads, paid providers, SMS, production or release. Provider
configuration, actual delivery and hosted cross-user acceptance remain separate
from source/local checks. Both email and Google may be offered only when their
actual configuration and strict $0 operation are verified.

The reviewed selective upgrade is now activated on the intended nonproduction
project: verified baseline 13 plus migration21, with 14–20 skipped. Actual history,
source-body, RLS/RPC permissions, owner binding and private-schema exclusion checks
passed. A compiled Chrome journey using existing signed synthetic accounts passed
the independent manual-statistics save/completion/review/publication lifecycle;
authenticated readback confirmed saved identities, missing values and accepted
pointers. Actual hosted synthetic practice/game/clock, correction lineage and
post-revocation denial checks subsequently passed with original active test grants
restored. The explicitly approved nonproduction Pages update now supports Google
sign-in in the owner-only Testing audience. Actual public-browser sign-in, exact
callback binding, current server owner access and original owner UUID preservation
passed. Email remains hidden pending its private SMTP setup and delivery check.
See web/README.md for scope. Provider delivery and real-team/device acceptance
remain separate gates; activation alone does not establish a functional teammate
pilot. Google remains in Testing with only the approved owner account, an exact
callback and no linked Cloud billing. Owner-saved SMTP is now enabled, with its
Gmail host/port verified without reading the password. The email-enabled frontend
update awaits specific deployment approval; actual email delivery/sign-in remain
unverified, and the authorized single owner email test has not been requested.
