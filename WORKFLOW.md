# TeamStats — Planning and Implementation Workflow

Last updated: 2026-10-08.

## Chat responsibilities

The planning chat owns brainstorming, requirement clarification, PRD decisions,
and implementation prompt generation. The owner wants context documents settled
before prompts are generated. Do not generate an implementation prompt or begin
app implementation until the owner explicitly says to proceed.

The separate implementation Codex chat executes bounded tasks from prompts the
owner pastes there. The owner pastes its short handoff back into the planning
chat. The planning chat reviews the handoff and supplies the next prompt when
appropriate. Do not create or message other chats automatically.

Implementation prompts must work in a fresh chat without prior conversation:
include the workspace/project paths, document-reading order, current bounded
task, constraints, checks, GitHub destination, and handoff format. Start the
implementation chat locally in the same checkout; chat history and attachments
are not assumed to transfer.

After each implementation prompt, recommend a model and reasoning effort based
on that task. Favor token efficiency and increase effort only for meaningful
complexity. The owner's chosen planning-chat setting is GPT-6.1 Sol, medium.
Recommendations do not themselves change the selected model/settings.

## Context documents

- PRD.md: confirmed product requirements, proposed criteria, and unresolved TODOs.
- WORKFLOW.md: coordination rules, execution preferences, and handoff format.
- PROJECT_CONTEXT.md: concise project entry point, verified paths, milestone
  sequence, and remaining inputs. Reference it in implementation prompts.
- Read applicable AGENTS.md instructions before repository work.
- Record decisions in their relevant document rather than repeating full context
  in every prompt. Keep both documents aligned with owner-approved changes.

Confirmed sequence: after-game manual entry first, photo autofill afterward.
Live tracking is excluded entirely. PRD.md records the owner-supplied player
box-score totals, individual paint-touch totals, home/away possession data, and
the custom Real Possessions formula for each team. Possession shots are made/missed
tallies by type, without attempt order. The dynamic playbook and practice videos
are required; their placement in the implementation sequence is unresolved.
The owner grants upload permission to selected accounts; those users need no
case-by-case upload approval. Other users upload pending videos that only the
owner may approve for team viewing. Signup supports both email and phone number.
Both iPhone and iPad are supported; spreadsheet integration uses Google Sheets.
Supabase holds official stats; Google Sheets receives automatic one-way exports.
Any app user can contribute stats subject to owner approval; selected accounts
can receive permission to publish without case-by-case review. Owner-managed
authorization applies to plays and videos too; permission granularity is open.
The initial pilot focuses on manual stats. Offline sync is low priority; begin
with online submission. The supplied blank box-score and advanced PDFs have been
reviewed; PRD.md preserves layout findings and explicit excluded fields. Printed
names and jersey numbers are placeholders, not the team roster. The owner now
authorizes labeled temporary roster names/numbers until the fixed roster is
provided after tryouts; no roster-management screen is requested. Do not extend
scope from source legends or add excluded fields to manual entry/photo extraction.
Collect offensive and defensive rebounds separately and derive total rebounds.
The owner will revise the advanced sheet to use `FTmade/attempted`; derive missed
free throws as attempted minus made. Do not infer misses from the old FT notation.
Clarify definitions before finalizing forms, schema, or advanced-stat formulas;
do not invent attempt order, player attribution, additional collection fields,
or play contents. Do not add per-video owner approval for authorized uploaders
or expose pending videos to ordinary team viewers before owner approval.

## Iteration sequence — once authorized

1. Clarify the requirements needed for the next step; resolve dependent TODOs.
2. Generate one bounded prompt referencing these documents, with an objective,
   permitted scope, acceptance criteria, relevant decisions, and handoff request.
3. Implementation chat inspects existing code/Git state and completes the task.
4. Run checks appropriate to the change; report failures and unverified behavior.
5. Commit the completed step with a clear message; include only relevant changes.
6. Return the compact handoff; the owner pastes it into the planning chat.
7. Planning chat assesses completion, updates requirements when authorized, and
   selects the next step. Resolve failed requirements before extending scope.

## Proposed project milestones

This is a planning sequence, not authorization to start implementation.

1. Inspect the existing Xcode project and verify a baseline iPhone/iPad build;
   establish a minimal app foundation using empty states. Resolve the GitHub
   destination before publication; do not guess the owner's repository.
2. Use the reviewed sheet layouts and confirmed rebound/FT definitions; review
   the revised advanced PDF when supplied. Resolve box-score shot shorthand,
   possession/page mapping, and remaining definitions. Obtain the owner's actual
   roster; settle export details, pilot scope, and pending-edit behavior.
3. Build manual entry and local record viewing against the agreed fields.
4. Add Supabase signup/login, data storage, owner grants, and backend access rules.
5. Connect stats submissions, owner review, authorized publication, corrections,
   and agreed calculations. Verify the manual workflow with multiple accounts.
6. Add automatic export from Supabase to Google Sheets; its placement before/after
   the pilot remains to be agreed. Do not import spreadsheet edits into the app.
7. Run the manual-stats pilot on iPhone/iPad and address observed issues.
8. Add photo autofill through the existing forms and review flow.
9. Add dynamic play authoring/viewing and linked practice videos with owner-managed
   permissions, plus Game Film uploads/playback linked to games. Relative order
   of these later features remains open; use separate bounded prompts.
10. Verify the completed app and proceed to the agreed wider distribution.

Only one chat should edit app code at a time. Proposed coordination rule:
the planning chat normally edits these context files; the implementation chat
edits app code. Commit and disclose any app changes made by the planning chat
before issuing the next implementation prompt.

Do not treat a proposed next step as authorization to start it. If human input
or approval is necessary, identify the exact decision and stop dependent work.

## Execution preferences

- Execute authorized shell, Git, and build commands; do not hand the owner commands.
- Start with the simplest solution. Add complexity only after identifying why
  the simpler approach fails; explain non-obvious choices briefly.
- Ask before moving, renaming, or reorganizing files/directories, adding a
  dependency, or deleting work.
- Preserve pre-existing changes and staged files. Do not commit unrelated work.
- Never invent owner-supplied content or data; use obvious TODO markers.
  Exception: the owner explicitly permits labeled temporary player names/numbers.
- Do not expose secrets in prompts, logs, commits, or handoffs.
- No empty commits for read-only inspection steps.

## Compact handoff

Target 150–250 words; maximum 300 unless essential failure details require more.
Use relative paths in the handoff and include exact commit identifiers. Do not
repeat the PRD, paste large logs, or claim checks passed when they were not run.

```text
STEP: objective; COMPLETE / PARTIAL / BLOCKED
RESULT: completed behavior or findings; key files
CHECKS: commands/checks and outcomes; unverified items
GIT: repository root; branch; commit(s); clean/dirty state;
     distinguish remaining task changes from pre-existing changes
DECISIONS: material choices, assumptions, and any PRD changes
BLOCKERS / HUMAN INPUT: exact decision or action needed, or none
NEXT: recommended next bounded step; do not begin it
```

## Planning review of each handoff

Compare results against the assigned acceptance criteria. Check verification
evidence, outstanding changes, assumptions, blockers, and the Git state.
Ask for missing evidence before treating uncertain behavior as complete.
Update context with confirmed decisions; do not silently convert proposals into
requirements. Keep subsequent prompts focused on the smallest useful next step.

## Progress — Step 1 complete (2026-10-08)

Game Film scope was added while Step 2 was in progress. Do not interrupt or expand
the assigned game/temporary-roster task. After its handoff, carry this requirement
into the relevant later media prompt, preserving the manual-stats pilot priority.

- Implementation handoff: Games/Players navigation and truthful empty states.
- Commit `9bd184e` preserves remote initial history; `3404839` adds the foundation.
- Implementation reports baseline/final simulator builds and iPhone 17/iPad A16
  screen/tab checks passing; physical devices, landscape, and accessibility
  variations remain unverified. Planning review did not repeat those checks.
- Planning review confirmed source, commits, iPhone/iPad target families, and
  two remaining pre-existing personal Xcode files staged/dirty. Do not absorb them.
- GitHub push was verified by implementation; planning review has not repeated
  the remote verification.
- App minimum is currently 26.4; owner has selected 26.0 onward for the next task.
- Confirmed game fields: date, opponent, our team's home/away status, and regular
  season/playoff. No scrimmages. A fixed real roster comes after tryouts; temporary
  arbitrary names/numbers are permitted now, clearly labeled as development data.
- Next bounded task: local game creation/viewing, temporary roster display, and
  minimum OS adjustment. Full stat entry follows in a separate prompt.

## Progress — Step 2 complete (2026-10-08)

- Commit `5b74f2f`: game creation/details, stable UUIDs, atomic local JSON storage,
  visible save/load errors, temporary five-player roster, deployment target 26.0.
- Planning review confirmed source/commit and two personal Xcode files remaining
  staged/dirty; no app source changes were made by the planning chat.
- Implementation reports final build passing on a 26.4 runtime, iPhone creation,
  validation, details and relaunch persistence, plus iPad layout/load-error/Retry
  checks. iPad Save interaction, physical devices, save-failure injection, and
  actual 26.0-runtime execution remain unverified. Do not claim they passed.
- Implementation reports successful push and remote HEAD verification; planning
  review did not repeat network verification.
- Next task: local player box-score entry with both individual and roster-table
  modes sharing records. Blanks remain missing and zero is explicit. Entered
  points are checked against shot makes, with disagreements flagged. Matching
  game totals must later reconcile with advanced-sheet points once possession
  data is available/complete. Do not claim cross-sheet checks pass yet.
  Possession entry and connected approval/publishing remain separate tasks.
- Before stats are persisted, give temporary players stable identities independent
  of jersey numbers; do not silently map them onto the eventual actual roster.
- Game Film is still a later feature. Hudl is the likely recording source; confirm
  exported video files versus links before selecting an integration.

## Progress — Step 3 implementation complete, verification partial (2026-10-08)

- Commit `1c3c314`: shared individual/table box-score entry, requested fields,
  derived rebounds, missing-versus-zero handling, numeric validation, points
  checks, incomplete draft persistence, and stable temporary-player IDs.
- Planning review inspected the source and local Git state; it did not run the
  app or repeat the implementation chat's reported checks.
- Implementation reports a passing simulator build and model checks for invalid
  input, discrepancies, overflow, persistence, unique updates, and storage errors.
  iPad interactions verified both modes sharing edits, validation, draft saves,
  editing without duplicates, and relaunch persistence. Step 2 files stayed intact.
- UI automation then failed. iPhone interaction/layout and iPad new-game Save
  remain unverified. Actual 26.0 runtime and physical devices remain untested.
- Human action: unlock the Mac and reopen Simulator before resuming UI checks.
- Next bounded task: finish these checks and fix only issues they reveal. Do not
  start possession entry, connected services, or media features. Advanced-sheet
  reconciliation remains unavailable, and draft saving is not publishing.
- Implementation reports remote HEAD matching local HEAD. The two pre-existing
  personal Xcode files remain staged/dirty and must stay outside task commits.

## Step 3 verification follow-up (2026-10-08) — partial

- No app source changes or new build: earlier build/model checks remain valid.
- Earlier iPhone checks passed game Save/details, both entry modes, shared
  unsaved edits, blank versus explicit zero, and negative-input save blocking.
- Resumed iPhone checks used `TEST ONLY Step 3 iPhone verification` on iPhone 17,
  Simulator 26.4. Saving an incomplete draft with the number keyboard visible
  succeeded. Tapping keyboard 7 entered the value and Save remained reachable.
- Accessibility output reported total rebounds 2 from offensive 0 + defensive 2,
  disagreement for entered points 10 versus shot-implied 7 (twos made 2, threes
  made 1, free throws made 0), then a match after editing points to 7.
- JSON inspection after saves found five distinct game/player records, the updated
  player values, and empty dictionaries for untouched players. Relaunching the
  app and reopening the table restored those values, stable IDs, and match check.
- Field focus automatically moved horizontally to shooting columns. Manual
  scroll/swipe attempts produced no visible movement; manual table scrolling
  remains unverified rather than treated as a demonstrated app defect.
- iPad window switching and opening New game succeeded. Filling Opponent then
  returned stale-element error `-10005`. UI retries stopped at the owner's request;
  iPad new-game Save/details remain unverified. The form may still be open.
- Existing Step 2 games and iPad draft records are preserved. Both personal Xcode
  files, including their staged entries, remain outside task commits.
- Actual iOS/iPadOS 26.0 and physical devices remain untested. Advanced-sheet
  reconciliation remains unavailable. No connected services or further entry
  features were started.

### Remaining manual checklist

1. On iPhone 17, open Games → `TEST ONLY Step 3 iPhone verification` → Whole-roster
   table entry. Swipe horizontally left across the table to reach Total rebounds
   and Points check, then right to return to Points. Expected: all columns remain
   reachable, total rebounds is 2, and points match made shots (7). Tap a field
   to show the keyboard and swipe vertically to reach Temporary Player 5;
   expected: all five rows remain reachable and Save draft stays above the keyboard.
   Leave values unchanged. Report whether these gestures work or which part fails.
2. Dismiss any Simulator menu and bring iPad A16 forward. In Games, open Add game
   (or use the already-open New game form). Set Opponent to
   `TEST ONLY Step 3 iPad Save verification`, date October 8, 2026, Our team Home,
   Game type Regular season. Tap Save. Expected: sheet closes and the labeled game
   appears in Games. Open it; expected details show those four values. Report the
   Save result and displayed details; retain the test game and existing records.

Next bounded task: complete these two manual checks and record the evidence,
fixing only any demonstrated defect. Do not begin the next implementation step.

## Step 3 closed — owner manual verification (2026-10-08)

- Owner reported “iphone passed; ipad passed” for the two remaining manual
  checklist items above. iPhone table columns/rows and keyboard-visible Save
  are reachable; iPad new-game Save and saved details passed.
- Step 3 is complete. No source fix or rebuild was required. Earlier partial
  verification entries are historical and superseded by this confirmation.
- Actual 26.0-runtime execution and physical-device testing remain unverified.
  Advanced-sheet reconciliation still awaits possession entry.
- Next: resolve possession entry conventions, then authorize a bounded local
  entry task. Supabase, publishing, and media remain later milestones.

## Possession and visual decisions (2026-10-08)

- Owner confirmed independent team numbering paired left to right, our team then
  opponent; reversible sheet-completion controls and incomplete game labels;
  legal-possession grouping including free throws/OREB; holding until period
  end excluded. PRD.md records remaining completion/period-ending edge cases.
- Owner supplied explicit visual exclusions. Future prompts must honor PRD.md's
  native, restrained visual direction without expanding into a separate redesign.
- Next prompt waits for these narrow edge-case clarifications. No source changes
  were made by the planning chat.

## Step 4 authorized scope — local possession drafts (2026-10-08)

- Owner confirmed period-ending possessions with actions count; no-action holds
  until the buzzer do not. Completed datasets require edit requests approved by
  the owner or an authorized dataset-editing reviewer; revisions need completion
  again. Preserve accepted data while requests are pending.
- Next bounded prompt implements paired local possession drafts only. Completion
  and edit-request enforcement follow accounts/backend permissions, not simulated
  local approval. Paint-touch player totals, reconciliations, and derived metrics
  are separate bounded tasks. No new dependency or restructuring is authorized.


## Progress — Step 4 local possession drafts implemented, verification partial (2026-10-08)

- Added `Possession.swift` with paired entry from game details, independent team
  numbering, stable record/game UUIDs, eight requested count fields, and optional
  turnover answers. Only Add next creates records; an empty opposite-side cell
  stays a placeholder. Draft-record counts are explicitly incomplete, not metrics.
- Reused the existing whole-number validator. Missing counts remain absent keys;
  zero and No are explicit. Atomic `possessions.json` storage validates IDs,
  team/number uniqueness and nonnegative values, preserves other records, and
  reports load/save failures. No fixed possession limit, deletion, completion,
  approvals, reconciliation, individual paint-touch totals, or connected services.
- Generic simulator build passed with minimum target 26.0. Runtime inspections
  used iPhone 17 and iPad A16 on 26.4, not actual 26.0 or physical devices.
- Foundation checks passed missing/zero, invalid/overflow inputs, nil/Yes/No,
  independent teams, stable IDs, unique updates, persistence, more than 40 records,
  corrupt-load rejection, and failed-write propagation.
- iPhone UI saved our possession 1 with no opponent record, then independently
  added opponent 1 and our 2. Editing paint touches to explicit 0 and turnover
  to No kept three unique IDs; other counts/answers stayed missing. Relaunch
  restored records, counts 2/1, the zero, No, and the empty opponent-2 placeholder.
  Number-keyboard entry and keyboard-visible Save passed. Final focus positioning
  puts the active field above the keyboard; Hide keyboard does not dirty unchanged
  input. Turnover menu offers Unanswered, Yes, No and shows the selected answer.
- iPad paired layout, our-only addition, opposite placeholder/count 0, invalid
  negative-count Save blocking, and incomplete draft Save passed. A native
  setValue action returned `AXError.cannotComplete` after applying the negative
  value; repeated text-entry attempts stopped. Button interactions remained usable.
- UI inspections revealed and fixed clipped iPhone guidance, a keyboard-toolbar
  overlap with Save, hidden focused fields under the keyboard, and unchanged
  input becoming dirty on focus changes. Each behavioral fix was rebuilt.
- Original games and box-score files on both simulators remain byte-for-byte
  unchanged. Both personal Xcode files retain their staged entries and working
  bytes and remain outside task commits. Planning commits are included in the push.

### Remaining Step 4 manual checks

On each simulator, use the existing labeled Step 3 verification game and open
Possession draft entry. Swipe horizontally to the opponent side and back, then
vertically through every field and additional paired rows. Expected: labels,
Unanswered/Yes/No controls, and both Add next buttons remain reachable; guidance
is readable at the initial position. On iPad, enter 0 in our possession 1 Paint
touches, choose Yes for Turnover, then Save with the software keyboard visible.
Expected: active field and Save remain visible with no overlap. Hide keyboard;
expected: Done remains enabled. Relaunch and reopen; expected: 0 and Yes persist
in the same record, with opponent still at zero records. Report any failed step.
Do not delete the test records. These manual gesture/iPad keyboard/relaunch
checks are outstanding, not presumed passing. Larger-text and landscape layouts
also remain untested. Finish verification before the next implementation task.
# Step 4 owner feedback — fix before closing

- Owner confirmed vertical scrolling on both devices and iPad keyboard-visible
  saving/relaunch persistence. Horizontal swipes do not move paired columns on
  either device. Diagnose overflow and gesture behavior rather than assuming
  every device needs scrolling when both columns fit.
- Updated requirements: numeric blanks remain allowed; new turnover defaults No;
  each count gets +1/-1 controls alongside direct typing. Preserve historical
  missing values. Subsequent confirmation below settles blank-as-zero at completion.
- Apply the owner-linked apple-design skill to the possession UI using native
  SwiftUI, respecting explicit visual exclusions. Next task is this bounded fix.

## Possession completion confirmation decision (2026-10-08)

- Owner confirmed blank numeric fields mean no events at completion. Show a popup
  warning of conversion to explicit zeros, with Confirm/Go back and per-user
  “Don't show this again.” Draft blanks remain missing until completion.
- Suppressing the popup skips only that warning on future explicit completion;
  it never bypasses validation, approval, or editing permissions. Only existing
  possession records are converted; empty paired placeholders are not records.
- Record for the later authenticated completion task. The current Step 4
  usability-fix prompt remains unchanged; do not add completion scope to it.


## Step 4 usability fix — implementation complete, verification partial (2026-10-08)

- Read the owner-linked [apple-design skill](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md).
  Applied immediate value feedback, familiar native buttons, minimum 44-point
  touch targets, explicit accessibility labels/values, system type and Dynamic
  Type scaling. No custom gesture physics, web libraries, glass cards, or animations.
- Diagnosed lazy-stack sizing: fixed-width paired children overflowed visually
  without an explicit paired content width. The stack now declares the full
  measured width (two scaled columns, spacing, padding), retaining native two-axis
  scrolling. Default 264-point columns fit the inspected normal iPad sheet; where
  both columns fit, horizontal movement is unnecessary. Larger text expands them.
- Each numeric field retains direct entry beside +1/-1. Blank + becomes 1;
  minus is disabled for blank/0, 1 minus becomes explicit 0, and clearing restores
  missing. Invalid typed text disables counter arithmetic without correcting it;
  Int overflow is checked, with no basketball-frequency cap. Draft saving never
  converts missing counts to zeros. Only new possessions default turnover to No;
  loading passes saved optional answers through without migration.
- Final generic simulator build passed at target 26.0. Foundation checks passed
  counter boundaries, whitespace blanks, invalid input/overflow, clearing, stable
  unique updates and preserved historical nil/Yes/No turnover values.
- iPhone 17 on 26.4: blank→1→0 counter feedback and disabled decrement passed;
  number-keyboard typing, clearing, keyboard-visible Save, save/edit, and relaunch
  passed. A new labeled test-game possession (our #3) saved blank counts and No.
  Every original possession record stayed identical, including historical answers;
  no duplicate IDs. Relaunch restored counts 3/1 and cleared input as Unentered.
- Layout checks: normal iPad A16 sheet displays both columns/counters fully. Focus
  scrolling brings opponent fields fully into view on iPhone and at larger iPad
  text (accessibility-extra-large). iPhone maximum text size was inspected and
  Save activated successfully. Original text-size settings were restored.
- Automated iPhone horizontal drag produced no movement. Gesture retries stopped;
  programmatic horizontal access passed, but real swipe behavior and exhaustive
  every-field reachability are not claimed verified. Owner's prior vertical and
  iPad keyboard-visible Save/relaunch results remain recorded; final counter layout
  still needs the short manual check below. Actual 26.0 and physical devices remain
  untested. No new metrics, completion, approvals, reconciliation or services.
- Games and box-score files stayed byte-identical on both simulators. All original
  possession records stayed unchanged (iPad possession file also byte-identical).
  Both personal Xcode files remain excluded. The original UI-state staged blob
  is unchanged; its working bytes changed during the run without an agent edit.
  Leave that current personal state untouched rather than overwrite it.

### Remaining usability-fix manual checklist

1. iPhone labeled test game → Possession draft entry: swipe horizontally across
   a field label/gap to opponent, then back. Expected: both complete columns and
   their +1/-1, input, Add next and turnover controls become reachable. Swipe
   vertically to the last paired row and check all eight numeric fields plus
   turnover. At normal iPad text both columns should already fit; no horizontal
   movement is required there. With larger text, verify the same horizontal access.
2. Repeat at a larger text size on both devices, including software keyboard shown.
   Expected: text remains readable, active input and Save are reachable without
   overlap, and both counter buttons can be tapped. On a labeled test record use
   a blank count: + gives 1, minus gives 0 and disables, clearing restores blank.
   Save/reopen should retain blank and should not rewrite historical turnover.
   Restore the preferred text size afterward. Report the device, text size and
   exact unreachable control if any check fails; do not delete existing records.

Finish this verification before authorizing the next implementation step.

## Step 4 closed — manual usability passed (2026-10-09)

- Owner reported “both passed” for the remaining usability-fix checklist above.
  Horizontal access where overflowing, vertical reachability, larger-text controls,
  keyboard and Save access are verified by the owner on both devices.
- Step 4 is complete at implementation commit `6f96cd4`. No further source fix
  or rebuild is required by this confirmation. Historical partial entries remain
  for evidence; actual 26.0-runtime and physical-device testing remain unverified.
- Next bounded task: individual-player game-total paint-touch drafts, using the
  existing temporary roster and stable game/player identities. No attribution
  of possession touches to players or new counting conventions is implied.

## Step 5 — player game-total paint-touch drafts (2026-10-09)

- Added `PlayerPaintTouches.swift` and a game-details entry button. Native roster
  form shows names/numbers, temporary-roster and incomplete/unreviewed labels,
  the confirmed two-feet-with-ball definition and independently collected totals.
  Direct typing and accessible +1/-1 reuse existing validation/counter semantics.
  Missing totals stay missing; zero is explicit. No completion, metrics,
  possession attribution, counting convention, or connected service was added.
- Separate Codable JSON storage writes atomically, validates nonnegative totals
  and unique game/player keys, updates existing records and shows load/save errors.
  Saving untouched players retains optional missing totals, consistent with the
  existing box-score draft approach. Temporary roster IDs remain unchanged.
- Simulator build passed. Focused Foundation checks passed for blank/zero,
  counters, invalid/overflow inputs, atomic save/reload, stable keys, edits without
  duplicates, unrelated-record preservation, corrupt-record rejection and write
  failure propagation. Model checks do not substitute for UI interaction.
- iPhone 17 / iOS 26.4: blank + becomes 1, decrement becomes explicit 0 with
  minus disabled; typed -1 blocks Save/counters with a visible error; entering 7
  and clearing it passed. Save worked with the software keyboard visible; editing
  and saving retained exactly five unique records (first player 0; others missing).
  Those records remained in storage after terminate/relaunch; UI reopening is
  still unverified. Existing games, box scores and possessions stayed byte-identical
  on iPhone and iPad. No existing records were deleted or rewritten.
- UI automation reported -10005 `noWindowsAvailable` while clearing (the clear
  actually applied), then again on scrolling at larger iPhone text. Failing
  actions were not repeated. Larger-text layout/scrolling and iPad form interaction
  remain unverified. Original simulator text settings were restored. Actual iOS
  26.0 and physical devices remain untested. Step 5 verification is PARTIAL.
- Both personal Xcode files and their staged entries are excluded from this step.
  UI-state working bytes changed during the run without an agent source edit;
  the pre-task bytes were restored, with both versions retained temporarily.

### Remaining Step 5 manual checklist

1. iPhone: reopen `TEST ONLY Step 3 iPhone verification` → Player paint-touch
   drafts after relaunch. Expected: Player 1 is explicit 0; Players 2–5 are blank.
   Scroll to Player 5; enter 2, Save, reopen, change to 3, Save and relaunch.
   Expected: Player 5 retains 3, earlier values remain, one total per player.
2. iPad: open `TEST ONLY Step 3 iPad Save verification` → Player paint-touch
   drafts. On a blank total tap + (1), minus (0, then disabled), type 2 then clear
   (blank). Paste -1, 1.5, and an overflowing integer: error shown and Save disabled.
   Enter 3, show the software keyboard and Save. Reopen/edit to 4, Save/relaunch;
   expected 4 retained, other totals remain blank, existing data unchanged.
3. Both devices: repeat reachability at a larger accessibility text size. Scroll
   through all five players; every label, field and counter must be readable and
   reachable. With keyboard visible, active input, Hide keyboard and Save must
   remain reachable without overlap. Restore preferred text size afterward.

Finish these bounded checks before beginning another implementation step.

## Step 5 closed — manual verification passed (2026-10-09)

- Owner reported “both passed” for the remaining Step 5 manual checklist.
  UI reopening, iPad entry/save/relaunch, and larger-text/keyboard reachability
  passed. Step 5 is complete at `ab1047e`; no further fix or rebuild is required.
- Actual 26.0-runtime and physical-device checks remain outstanding for pilot
  validation. All stored stats remain local drafts, not reviewed/published data.
- Next bounded task: read-only local game summary using existing stores, with
  explicit missing values and draft subtotals. No completion, approval controls,
  official metrics, cross-sheet reconciliation, or connected services in this task.

## Step 6 — read-only local game summary (2026-10-09)

- Added `GameSummary.swift` and a game-details summary button. Native lists show
  metadata and “Local draft — incomplete and unreviewed”, temporary-player
  detail links with all saved box-score fields, derived rebounds, shot/points
  checks and independently stored paint-touch totals. Separate team sections
  show counts explicitly as records entered, not final game possessions, and
  links to each saved possession's counts/turnover answer. No statistical aggregate
  or new metric was added; no reconciliation/completion/publication is claimed.
- Missing values display “Not entered”, zero remains 0, rebounds require both
  component inputs, and shared arithmetic detects overflow. Historical unanswered
  turnovers remain missing. No writes/migration/edit controls exist in the summary.
- Each store loads independently; failures clear that store's displayed snapshot,
  show the actual error and Retry, while other data stays inspectable. Empty
  successful loads get explicit empty messages. Opening the summary reloads all
  three stores; player/possession detail pages show that saved snapshot.
- Simulator build passed. Focused checks using isolated `/tmp` fixtures passed:
  missing versus zero; rebounds missing/complete/overflow; shot match/disagreement/
  incomplete/overflow; game filtering; read preservation; fresh reload after an
  edit; historical unanswered turnovers; empty versus corrupt loads for all stores.
- iPhone 17 / 26.4: metadata/status and saved Player 1 points 7, offensive rebounds
  0, defensive rebounds 2, and missing fields were accurately exposed/displayed.
  iPad A16 / 26.4: entered our-team count 8 matched saved records; possession 1
  paint touches 1, missing counts and turnover Yes were accurately exposed.
  An existing second game displayed the empty player-paint-touch message.
  Visible accessibility-extra-large layouts wrapped readably on both devices;
  original text sizes restored. Actual 26.0 and physical-device checks not performed.
- Automated iPhone list scroll and native swipe produced no movement. Gesture
  retries stopped. Full lower-content access, both-team counts/all records at
  larger text, UI refresh after edits and error/Retry UI remain unverified. These
  limits do not establish a source defect; no speculative gesture fix was added.
  Step 6 implementation is complete; verification remains PARTIAL.
- All existing games, box-score, possession and player-paint-touch JSON remained
  byte-identical on both simulators. Personal Xcode files and staged entries were
  preserved and excluded; pre-task UI working bytes were restored if they changed
  during the run, with the intervening version retained temporarily.

### Remaining Step 6 verification

1. On each device, open a labeled test game's Local game summary. Scroll through
   both teams' Records entered sections and open each possession, including the
   last one. Expected: counts match saved entries (independent numbering), every
   field is reachable, blanks read Not entered, explicit zeros read 0, and saved
   Yes/No/unanswered turnover answers remain unchanged.
2. Open each player; scroll to total rebounds, shot check and game-total paint
   touches. Expected: rebounds only when both inputs exist; shots show incomplete,
   match or disagreement as appropriate; paint touches match the independent
   player entry screen. Repeat scrolling at larger accessibility text on both
   devices, then restore preferred text size. Back/Done must remain reachable.
3. Close the summary, change a clearly labeled test draft in an existing entry
   screen and Save, then reopen the summary. Expected: new saved value appears;
   other records remain unchanged. No edit controls should exist in the summary.
4. Error/Retry UI needs an isolated test-data environment: a broken store must
   show an error, not an empty count/missing values; unaffected stores stay visible.
   Restoring valid data then Retry must recover. Do not corrupt the owner's saved
   stores to perform this check. Model error handling already passed.

Finish only these verification gaps before authorizing another implementation step.

## Step 6 closed — remaining verification passed (2026-10-09)

- Owner confirmed both devices passed the remaining manual reachability and
  refresh-after-edit checks, including larger-text navigation/content access.
  This closes checklist items 1–3 above; earlier partial entries remain as history.
- Error/Retry UI passed on iPad A16 / iOS 26.4 using the existing `dfadedb` build
  copied to `/tmp` and installed under a separate test-only bundle identifier,
  `com.narayanlekhi.TeamStats.RetryVerification` (display name TeamStats TEST ONLY).
  Only the copied bundle metadata/signature changed; app source/binary behavior
  was unchanged. The isolated game is labeled TEST ONLY isolated error Retry.
  Test data used its separate container, never the owner's saved stores.
- Malformed box-score JSON displayed the actual load error and Retry rather than
  an empty-data message. Player paint touches 7 remained inspectable and the
  entered possession count 1 remained available. After restoring valid fixture
  JSON, clicking Retry removed the error and player points 0 were displayed.
- Malformed player-total JSON likewise showed its own error/Retry; player points
  0 remained inspectable and possession count 1 remained available. Restoring
  valid data and clicking Retry cleared that error. A separate possession failure
  then displayed its own error instead of empty team counts while player detail
  navigation remained usable. Restoring its fixture and clicking Retry restored
  count 1 and record inspection: paint touches 0, missing counts, turnover No.
- No source defect was demonstrated; no source change or redundant rebuild was
  made. Both original simulator containers' JSON stayed byte-identical. Personal
  Xcode working bytes/staged entries were preserved. The isolated app was stopped,
  the original app brought back, and test artifacts retained without deletion.
- Step 6 is COMPLETE at implementation `dfadedb` plus this documentation update.
  Error/Retry UI was tested on iPad; it was not separately repeated on iPhone.
  Actual 26.0-runtime and physical-device pilot testing remain unverified.
- Next bounded task: planning review and definition of the next authorized step.
  No subsequent implementation, services, metrics, completion or approvals started.

## Individual shot/points validation fix (2026-10-09)

- Diagnosed `boxScoreShotCheck`: it exited as incomplete before any made-shot
  calculation unless points and every made-shot category were present. The notice
  also sat below all individual fields or at the table's far-right end. Thus the
  reported partial case could not produce a discrepancy warning.
- Shared logic now computes checked contributions only from valid entered makes.
  A partial scoring lower bound greater than points warns with “at least”; other
  partial cases stay Check incomplete. Exact comparison requires points and all
  three made-shot categories. Invalid inputs and arithmetic overflow report Check
  unavailable; missing points report incomplete. Misses do not participate.
- `ShotCheckNotice` uses bold system text plus a warning symbol, rather than color
  alone. Individual warnings sit directly after affected scoring fields; table
  warnings sit beneath their scoring inputs in wider Dynamic Type columns. Summary
  places the same notice before saved fields, close to Points. No popup, correction,
  blank-to-zero conversion, completion, service or reconciliation behavior added.
- Simulator build passed. Focused checks passed: reported 4 points / 7 threes /
  other makes blank => lower bound 21; other partial contradictions; incomplete
  noncontradictory/equal-lower-bound cases; missing points; full exact match/mismatch;
  explicit zeros; invalid/overflow input; multiplication/sum overflow; ignored
  misses; blank-preserving persistence. Existing Step 6 error checks not repeated.
- Used isolated test apps (`com.narayanlekhi.TeamStats.ShotVerification`) on iPhone
  17 and iPad A16 / 26.4, with a labeled TEST ONLY shot discrepancy game. Normal
  individual/table/summary warnings were inspected on both devices. On iPad,
  typing points 3 updated the warning immediately; Save succeeded with the
  disagreement and retained missing twos/free throws in five unique draft records.
  Accessibility-medium summary warnings wrapped fully/readably on both devices.
- An automated iPad native scroll produced no movement; retries stopped. Larger
  text entry-mode scrolling, later made-shot-field warnings and horizontal table
  access still need the check below. Verification is PARTIAL; implementation/model
  checks passed. Actual 26.0 and physical devices remain untested.
- All original JSON on both simulators stayed byte-identical. Original text sizes
  and apps were restored; isolated fixtures retained without deletion. Both personal
  Xcode files' working bytes and staged entries were preserved and excluded.
  Original simulator apps were updated from the passing build without clearing
  data so the remaining manual check uses this fix.

### Remaining warning-layout manual check

On each device use a clearly labeled test game/player: points 4, threes made 7,
twos/free-throw makes blank. At a larger accessibility text size, inspect individual
and table entry. Expected: the complete bold warning with symbol is readable beside
Points and each made-shot input; scroll vertically/horizontally as needed. Clear
threes: Check incomplete, no match. Re-enter 7: immediate at-least-21 warning.
Enter twos 0/free throws 0: exact mismatch. Change points to 21: exact match.
Save/reopen summary: same saved result, blanks preserved when left blank, and no
automatic correction. Check keyboard-visible reachability of warning and Save.
Restore preferred text size. Report any exact field/message that cannot be reached.

Finish only this validation-fix verification before another implementation step.

## Scoring-warning presentation refinement (2026-10-09)

- Owner confirmed larger-text field reachability and keyboard-visible Save passed
  on both devices for `56d0777`. That closes the prior fix's remaining layout
  checks; the new presentation below has separate verification limits.
- Box-score entry now uses one red warning above the entry-mode controls with
  the exact heading “Points don’t align with made baskets.” A warning symbol and
  accessible player-name/detail text distinguish exact mismatches from partial
  lower bounds. Individual mode lists only the selected player's discrepancy;
  table mode lists every affected player. The list derives from current draft
  values and disappears when no proven discrepancies remain.
- Removed redundant entry-field/far-right discrepancy messages. Useful match,
  incomplete/unavailable checks and invalid-number validation remain. The header
  scrolls, using its measured natural height capped at 45% of available content
  height so larger text/multiple players/keyboard leave room for entry. This is
  native scrolling, not custom gesture behavior or a fixed-height warning card.
- Validation function and GameSummary source remain unchanged. Blanks stay
  missing, invalid/overflow input is honest, and discrepancies remain saveable.
  No dependencies, migration, completion controls or unrelated features added.
- Final sequential simulator build passed. An overlapping build attempt initially
  hit a build-database lock; the active build was allowed to finish before the
  successful final check. Focused model/source-expression checks passed for
  exact/partial detail labels, no warnings for incomplete/matching/invalid/overflow
  data, selected/all-player scope, multiple affected players, and removal after
  value changes. These checks do not substitute for actual UI interaction.
- Prepared labeled isolated banner fixtures on both 26.4 simulators (separate
  `com.narayanlekhi.TeamStats.BannerVerification` app). UI control failed with
  -10005 stale-element error while switching the Simulator Window menu; failing
  actions were not repeated. Actual appearance/removal, live mode switching and
  new larger-text layout/keyboard reachability remain UNVERIFIED. Status PARTIAL.
  Actual 26.0-runtime and physical-device testing also remain unverified.
- Original records and personal Xcode working/staged entries were preserved;
  fixtures retained without deletion. Original simulator apps were updated from
  the passing build for the manual checks below, without clearing saved data.

### Remaining banner presentation manual checklist

1. If Simulator's Window menu is stuck, close it manually. Use a clearly labeled
   test game. Player 1: points 4, threes made 7, other makes blank. Expected: one
   red heading/icon above mode controls, Player 1 listed with Partial lower bound
   and at least 21. Change points to 21: banner hides, Check incomplete remains.
   Change back to 4: banner appears immediately.
2. Player 2: points 2, twos/threes made 0, free throws made 3. Expected: Exact
   mismatch detail. Table mode lists both affected players once; individual mode
   lists only the selected affected player. Select an unaffected player: no banner.
   Change both players to noncontradictory/matching inputs: banner hides.
3. On iPhone and iPad at larger accessibility text, scroll the warning header to
   read every name/detail and reach mode controls. Scroll entry fields/table and
   show keyboard. Expected: readable text without truncation, fields and Save
   reachable, no repeated per-field warnings. Save/reopen preserves blanks and
   discrepancies; read-only summary retains its prior presentation. Restore text
   size afterward. Report the exact unreachable field/control if any check fails.

Finish only this presentation verification before another feature.
