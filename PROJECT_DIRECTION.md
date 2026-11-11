# TeamStats — current direction and working agreement

Updated: 2026-11-11. Status: planning; owner clarification pending.

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

## Choices awaiting owner answers

These are not approved implementation defaults. Resolve them before dependent work.

| ID | Question | Proposed answer / marker |
|---|---|---|
| Q1 | Primary platform, stack and native maintenance? | Responsive React/TypeScript web app with existing Supabase; preserve native source. TODO_PLATFORM_STACK_CONFIRMATION |
| Q2 | First web pilot scope? | Practice plans, nine-spot shooting, FT, game shot capture and selected game events; legacy manual datasets/media/plays/Sheets need explicit placement. TODO_WEB_PILOT_SCOPE |
| Q3 | Game attribution and time? | Our-team player selection, opponent team-only; manual period/game-clock reading initially. Team-only mode and running clock remain choices. TODO_GAME_CAPTURE_MODE |
| Q4 | Changing collection definitions? | Simple reusable templates with count, makes/attempts, timed event and notes; fixed screens are an alternative. TODO_TEMPLATE_SCOPE |

Before detailed capture implementation obtain:

- TODO_NINE_SPOT_LAYOUT: coach's locations and labels, court dimensions/rules.
- TODO_DRILL_PROTOCOL: whether each attempt or station totals are entered; sets,
  rotations, simultaneous baskets, collector responsibility and counting rules.
- TODO_TIME_MEANING: game clock, drill countdown, video offset and device time
  are different facts. Do not infer one from another.
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
→ explicit 2/3-point value and Make/Miss → recorded event with Undo. Keep free
throws off the court as per-attempt or agreed makes/attempts entry. A location
tap alone must not persist an attempt. Retain a visible selection and recent
records so a wrong player, value or location can be corrected.

A team-level game mode must not erase historical player attribution. Practice
player results are needed for the coach's requested individual percentages.
Court shots cannot reconstruct possession logs, paint touches or other
uncollected events. Decide legacy modules' new scope explicitly.

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

## Proposed technical baseline, subject to Q1

React + TypeScript + Vite; responsive touch-friendly browser UI; a small PWA shell
if installability is needed; existing Supabase Auth/Postgres/RPC/RLS contracts
where compatible; SVG court; browser print-to-PDF; CSV export initially.
Cloudflare Pages Free is a frontend-host candidate, not proof all services are free.

Offline capture needs an explicit bounded design: local journal, clear pending /
server-confirmed states, duplicate prevention, connection recovery and authority
checks at submission. Browser storage is not an independent backup. Do not add
full offline synchronization or a background-running clock by assumption.

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

1. Resolve Q1–Q4 and record owner answers here; replace only resolved TODOs.
2. Define one real practice protocol and its desired results. Prototype the
   approved court/player flow without manufacturing coach facts.
3. Plan the smallest approved web slice end-to-end: create session, record,
   correct/Undo, save/reopen, review and results. Define its checkable acceptance.
4. Implement/test that slice on actual target browsers, including authorization,
   interrupted connection, duplicate handling, touch speed and accessibility.
5. Add approved game modules, then evaluate OCR/voice on representative forms
   and rehearsal data against manual effort. Expand analysis only with evidence.
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
