# TeamStats agent instructions

Before implementation read PRD.md, PROJECT_CONTEXT.md, WORKFLOW.md and README.md.
Preserve existing local records and temporary identities; never auto-upload them.
Preserve both personal Xcode files' working bytes and staged entries. Use explicit-path commits.
Ask before adding dependencies, reorganizing files/directories, or deleting work.
Never put privileged credentials or real student records in source, logs or handoffs.
New owner end-to-end authorization overrides older bounded-step stopping instructions.

## Agent skills

### Issue tracker
Private local Markdown tickets under `.scratch/`; see docs/agents/issue-tracker.md.
Do not publish internal tickets/specs in the public repository.

### Triage labels
Use canonical default labels; see docs/agents/triage-labels.md.

### Domain docs
Single context. Before relevant exploration read GLOSSARY.md and applicable docs/adr entries;
see docs/agents/domain.md. Create decision records only for material tradeoffs.

### Implementation and tests
Read `.scratch/teamstats-completion/spec.md` and the claimed ticket before work.
Independent implementation agents use isolated worktrees based on the integration tip.
Only the integrator edits the Xcode project. Advisors/reviewers are read-only.
Test public seams specified in the spec: storage/validation/metric results, authenticated
server commands and denied access, session state, and user-observable navigation/saving.
Keep simulated successes separate from actual provider integration evidence.
