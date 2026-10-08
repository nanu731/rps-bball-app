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

## Context documents

- PRD.md: confirmed product requirements, proposed criteria, and unresolved TODOs.
- WORKFLOW.md: coordination rules, execution preferences, and handoff format.
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
with online submission. Source sheets are expected from the owner before forms
are finalized.
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

1. Review supplied box-score/possession sheets; settle field definitions, data
   export details, pilot scope, and pending-edit behavior.
2. Inspect the existing Xcode project and verify a baseline iPhone/iPad build.
3. Build manual entry and local record viewing against the agreed fields.
4. Add Supabase signup/login, data storage, owner grants, and backend access rules.
5. Connect stats submissions, owner review, authorized publication, corrections,
   and agreed calculations. Verify the manual workflow with multiple accounts.
6. Add automatic export from Supabase to Google Sheets; its placement before/after
   the pilot remains to be agreed. Do not import spreadsheet edits into the app.
7. Run the manual-stats pilot on iPhone/iPad and address observed issues.
8. Add photo autofill through the existing forms and review flow.
9. Add dynamic play authoring/viewing and linked practice videos with owner-managed
   permissions. Relative order of these later features remains open.
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
