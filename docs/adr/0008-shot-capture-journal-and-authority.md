# Shot journal, recorder authority and independent comparison

Date:2026-10-17. Adopted implementation defaults for PRD/ADR0007; source and actual
acceptance are recorded separately in TESTING.md. Coverage signoff remains an
owner decision, not resolved by this ADR.

## Local observations

Use a versioned account/team/game/session-scoped Codable journal. Stable session,
event and change identities distinguish retransmission from separately recorded
attempts. Store pending field goals and sparse indexed free-throw answers; omitted
answers are pending, never misses. Freeze team/player/basket attribution when an
entry begins; later selection changes cannot change it. Technical byte/history/
integer bounds protect storage and rendering, not expected basketball frequency.

Each correction retains before/after provenance. Undo appends a reversal of the
last eligible local change rather than erasing history. Validate references,
sequence, identity and the complete projected document. Atomically persist before
showing a saved receipt. A failed write preserves prior durable bytes and visible
pending input; explicit Retry uses the same change identity. No original store is
rewritten or automatically uploaded. Shared captures are concealed across account
changes and confirmed denial; device storage never creates server authority.

## Schematic court

Store full-court normalized coordinates and each field goal's attacking basket
end. Display flips are reversible and do not rewrite historical origins. Explicit
2/3 value controls scoring; no geometry inference. Free throws have no location.
Initial chart regions are clearly labeled equal-width left/center/right bands,
basket-relative, with observed sample counts. They are not regulation paint/arc,
measured distance, defender context or shot quality. Actual rotation acceptance
is separate from coordinate-transform tests.

## Shared capture

Keep recording, review, publication bypass and bounded grant administration distinct.
The server owns one designated recorder assignment/revision per game. Handoff is
explicit and fences new writes from the former assignment without deleting local
work. Register shared session identity/provenance while authorized; no general
shared-data offline synchronization is introduced.

Submit a frozen whole-session revision with stable batch identity, payload digest,
assignment and expected server revision. Atomically record its receipt with data.
Current authority is required for submission and receipt recovery. An identical
retry retrieves its original receipt; a reused ID with changed content conflicts.
A late receipt acknowledges only its frozen local revision, never subsequent edits.
No event merging or duplicate-attempt inference. Retain accepted revisions.

Old-recorder capture needs explicit, currently authorized recovery/adoption; stale
assignment is not an upload exception. Preserve original author/session/assignment
and flag overlap. The current recorder/reviewer must authorize recovery under the
current assignment; it grants no recording capability or access to another account's
local bytes. Exact recovery commands are verified with the shared implementation.

## Review and comparison

Incomplete drafts can be saved/submitted as incomplete. Proposed default: reviewers
can inspect pending answers but cannot publish them until resolved or explicitly
withdrawn with retained provenance. Unknown results may remain drafts; never force
invented Make/Miss. Resolved partial capture can be published with partial/unknown
coverage labels. This is not full-game completion or final owner coverage signoff.

Compare each team and available player against independently identified official
sources/revisions. Missing values are unavailable; known points with pending answers
are a subtotal/lower bound. Percentages use resolved attempts and state pending
counts. Matching points never proves missed attempts or locations were captured.
Keep manager-declared full-game recording separate; authoritative “Coverage complete”
remains unavailable while TODO_SHOT_COVERAGE_SIGNOFF is unresolved. Recompute after
source revisions change without altering either source.

Five independent perspectives and five peer reviews informed these defaults;
three advisers were reused, so the process was not strictly anonymous. No provider,
existing migration, scheduler or delivery activation is authorized by this ADR.

## Prepared offline continuation

Five additional current-model perspectives and five peer reviews converged on a narrow prepared-capture permit, not general shared offline synchronization. The current viewer is separate from the immutable capture creator. An environment/account/team-scoped protected permit permits only continuation of a previously registered device journal; unknown remote revocation cannot be learned while disconnected. Missing, corrupt, known-denied or expired preparation conceals content without removing bytes. Generic login never clears a shot-specific denial.

Before explicit online checks or commands, persist and verify a locked permit with a unique operation token. Only the matching current-account response can restore eligibility; stale completions cannot undo a later denial. Interrupted checks remain locked until online recovery. Offline continuation itself sends no request. This deliberately trades availability after an interrupted authorization check for durable denial concealment. Server submission always rechecks current designation, assignment revision and capabilities. Prior Auth binding establishes device identity only, never upload authority.

Implementation conservatively invalidates offline eligibility for other preparations
when checking a team; only the freshly verified game is re-enabled. Entries and
journals are retained. A SQL-confirmed rejection or denied receipt can be explicitly
archived with its frozen bytes before a newly authorized recovery proposal. This
is not proof of non-commit and never triggers automatic resubmission. Recording
deadlines do not block a fresh server-authorized published/reviewer view.
