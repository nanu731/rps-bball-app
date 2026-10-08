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
the custom Real Possessions formula. The dynamic playbook and approved practice
videos are required; their placement in the implementation sequence is unresolved.
Clarify definitions before finalizing forms, schema, or advanced-stat formulas;
shot outcomes are confirmed, but do not invent attempt order, player attribution,
additional collection fields, play contents, or video approval roles.

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
