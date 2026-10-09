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
  missing values. Blank-as-zero at completion is not yet confirmed.
- Apply the owner-linked apple-design skill to the possession UI using native
  SwiftUI, respecting explicit visual exclusions. Next task is this bounded fix.
