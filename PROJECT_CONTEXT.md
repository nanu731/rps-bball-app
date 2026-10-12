# TeamStats — Project Context and Development Sequence

Owner added Lincoln Devine's polish guide as a UI acceptance reference; PRD.md's
Human-use polish section records the rubric and native/security adaptations.
Guide successfully read on 2026-10-11; token-bearing URL intentionally excluded.
Audit results are not assumed passes. Incorporate the rubric into remaining
UI/recovery/physical-device validation without changing the $0 or offline scope.

Latest owner steering (2026-10-11): current prompt authorizes end-to-end
completion with installed Matt Pocock skills and LLM Council resolving ambiguous
design/product choices. Add owner roster management and grant/revoke/delegate
capability administration; enforce bounded delegation server-side and preserve
historical data. This supersedes earlier statements excluding roster management
or requiring a fresh bounded prompt for each feature. External credentials,
paid-service budget, real branding/roster and release authorization remain human
inputs, not facts Council can invent. See PRD.md's latest owner-administration section.

Last updated: 2026-10-11.

## Current completion checkpoint

The older Step 1–6 notes below are historical. The end-to-end branch now includes
native Account, team/roster/capability administration, shared games/statistical
version workflows, accepted metrics/reconciliation, owner export status, reviewed
play animation, transient on-device photo review and private video-link metadata.
These are locally tested implementations, not a completed hosted release.

| Area | Evidence and remaining limit |
| --- | --- |
| Identity/access | 21 native Account fixtures; actual local email-link PKCE/restore and distinct-user Auth/RLS checks. Owner now reports Free nonproduction setup, successful app sign-in and matching app/Auth Users UUID. Trusted independent re-verification/bootstrap and hosted access checks await administrative access; real SMS stays disabled. |
| Shared statistics | SQL 136 baseline +37 approved-recovery checks and signed gateway 81 checks; actual local SDK workflow passed. Approved current-source corrections retain stale drafts read-only; explicit attachment preserves unsaved buffers. |
| Plays | 11 integrated geometry/play tests and 54 baseline +37 recovery SQL checks. Explicit Reload/Attach preserves buffers after uncertain recovery; device interactions unverified. |
| Photo | 14 native tests, including bounded file reads and actual synthetic Vision. Explicit mapping/confirmation only; no identity inference or persistent photo/text copy. Marked-form accuracy and picker interactions unverified. |
| Video links | 78 actual SQL and 14 native checks; actual local SDK practice/film lifecycle passed with target filtering. File uploads, private playback, quota/transfer enforcement and Hudl access remain incomplete. |
| Sheets | Private empty destination verified; worker source and outbox tests passed, Google delivery disabled. Trusted service identity/runtime and billing-disabled proof remain unavailable. |
| Device/release | Simulator inspection recovered, but input failed with `-10005: noWindowsAvailable`; attempts stopped. Updated private checklist covers polish/navigation, rotation, large text, VoiceOver and keyboard/recovery. Actual26.0/physical devices and signing/production/release approval remain unverified. |

The owner completed private Free setup and confirmed the app's verified Auth UUID
matches Authentication → Users. This is owner-confirmed evidence. The agent has
not independently verified that account or granted owner authority: CLI admin
authentication and an ignored hosted setup file are unavailable, and the connected
dashboard is awaiting sign-in. Nine unchanged tested migrations are pinned in a
private manifest; target/schema inspection must precede application. Private
activation gates require trusted account re-verification and audited bootstrap,
followed by hosted signed access checks. No local upload or production deployment.
Real identifiers stay out of public files/logs; $0 and SMS-disabled limits remain.

The f682cfe polish rubric was audited before changes. Demonstrated fixes protect
unsaved navigation in local/shared game creation, play/media/photo review and
roster editing; pending requests freeze affected fields and show native progress.
Administration destinations survive model reloads, and admission messages distinguish
pending, active and removed responses. Confirmed server denial conceals cached
statistics/play/media content, including entry headers and completion rosters;
transient failures preserve recoverable buffers. A failed Retry after denial cannot
restore protected content. Current-context owner export denial also conceals it;
ordinary export errors and obsolete responses remain independent.
Seventy affected native fixtures passed; after the statistics repairs, all23
statistics fixtures passed. Final iPad simulator build passed. Standards review
found0 breaches; Spec found2 presentation/locking gaps, repaired and re-reviewed
with0 remaining concrete findings. Court dragging during pending Save remains a
targeted UI check. No new persistent connected cache or termination-restoration
promise was added; full offline synchronization remains deferred. The strict$0
budget and server-confirmed permissions/approvals are unchanged.
Additional local Storage/Functions/Imgproxy test tooling is awaiting approval.
The integrated native suite passed111 tests, with two opt-in local-server tests
skipped in that run. Actual local-server workflows are verified separately.
Final iPad simulator build passed. The new recovery slice passed Standards0
documented breaches and Spec0 findings; device behavior remains pending.
An unsigned local device archive of c0504a6 passed; its manifest declares26.0 and
iPhone/iPad device families. It is not a signed installable release or actual
26.0-runtime verification. Real signing/distribution and release approval remain pending.
An eligible consumer Gmail SMTP sender is a documented no-cost candidate for
team email, requiring separately authorized private sender/account setup and
real inbox verification. It has not been configured; default organization-only
mail is not a team delivery solution.

Completion work is on `codex/teamstats-completion`. Private task graph/acceptance
and coverage live in ignored `.scratch/teamstats-completion/spec.md`; generic
engineering configuration is in docs/agents. Structure/default local labels and
the official Supabase Swift SDK are owner-approved. Actual service configuration,
signing and release approval remain human inputs. The owner set a strict $0 budget;
paid SMS/AI and possible overages are not authorized. Adopted Council defaults
are summarized in docs/adr/0001-reviewed-dataset-versions-and-bounded-grants.md;
five independent analyses, five anonymous fresh-agent reviews and chairman
synthesis were performed. Provider capabilities still require primary research.
Read WORKFLOW.md's Project readiness audit for the 20-item checklist and remaining
sequence. PRD.md now states value/pain/audience and lean brand/UI standards;
README.md describes actual setup/status. Native Auth now supports PKCE email links and email/phone OTP,
private Keychain configuration/session restore, Retry and sign-out; remote SMS is
disabled. Twenty-one isolated native account tests passed, including real simulator
Keychain operations in a signed test host. These SDK fixtures do not prove hosted
delivery or deployed authorization. Server membership/grant/delegation/roster
source passed81 actual Postgres17.11 pgTAP checks after local tooling approval.
Required administration revisions reject stale/NULL requests. Real Auth gateway checks passed40 checks, with26 additional owner/session checks.
An opt-in native test verified real local Auth, Keychain session restoration and
roster create/edit/archive/history through the SDK. Hosted integration remains blocked.
Actual default-email-link PKCE verification and restart/session handling passed
on the isolated local stack through the native Account model. New Free projects
cannot customize default email templates; use the verified email-link route
without upgrading or adding a paid sender. Hosted delivery remains unverified.
Hosted configuration and centralized monitoring remain unavailable. Continue
independent work while banner interaction checks remain open. Shared games and
statistical lifecycle screens are now wired from Account/team administration;
the integrated build and65 native fixture tests passed. The actual local signed
statistical gateway passed81 checks; native connected workflow integration passed on the local stack;
locked-Mac UI checks are still outstanding. Metrics use accepted pointers only.
The server retains immutable corrections and atomic export enqueue, while actual Sheets
delivery remains disabled and unverified.
Status: requirements draft; Steps 1–6 complete. Games, shared box scores, and paired possession drafts are
stored locally. Possessions have independent team numbering, stable UUIDs,
missing-versus-zero counts, and unanswered/Yes/No turnovers. All possession data
is incomplete and unreviewed; no completion or approval controls are implemented.
Step 4 usability changes add accessible +1/-1 controls beside typing, Dynamic Type
column sizing, explicit horizontal content bounds, and No only for new turnovers.
Existing unanswered/Yes/No values stay intact; draft blanks remain missing.
Build/model checks and iPhone counter/typing/clearing/save/relaunch checks passed.
Normal iPad columns fit; larger iPad text and iPhone overflow can be brought fully
into view by focus scrolling. Owner confirmed both devices passed the remaining
manual swipe, larger-text, field reachability, keyboard and Save checklist.
Owner previously confirmed vertical scrolling and iPad keyboard Save/relaunch.
Actual 26.0 and physical devices remain untested. Completion/edit requests follow
backend authorization; advanced metrics and cross-sheet comparison remain separate tasks.
Step 5 local player game-total paint-touch drafts are implemented and verified.
The separate atomic `player-paint-touches.json` store uses stable
game/player keys, retains missing versus zero, and never derives player totals
from possessions. Existing temporary identities are unchanged. Build and focused
model checks passed; iPhone counters, invalid-input blocking, direct entry/clearing,
keyboard-visible Save and repeated saves passed. Five unique saved records remained
after app relaunch; the owner confirmed UI reopening passed. Existing games,
box scores and possessions stayed byte-identical on both simulators.
Simulator UI scrolling failed with error -10005 (`noWindowsAvailable`); retries
stopped. Owner confirmed the remaining iPad interaction and both devices'
larger-text/reachability checks passed. No actual 26.0-runtime or physical-device
testing was performed. Next: read-only local game summary with honest draft and
missing-data labels; completion, official metrics and reconciliation follow later.
Step 6 read-only local game summary is implemented and verified.
It reads the three existing stores independently, displays metadata/draft status,
saved player fields and independent paint touches, safe rebound/shot checks,
entered possession-record counts and inspectable possession records. Missing
values stay “Not entered”; viewing never writes or converts values. Empty stores
and errors are distinct, with Retry; every reopening reloads saved data.
Build/model checks passed. iPhone saved player values and iPad possession values/
entered count were inspected; larger-text visible layouts wrap readably. Owner
confirmed remaining reachability and refresh-after-edit checks passed on both
devices. Actual error/Retry interaction passed on iPad 26.4 using the unchanged
build in a separately identified test app/container: each of the three stores
showed an error instead of empty data; unaffected sections remained usable; Retry
recovered after repairing each isolated fixture. Original simulator records stayed
byte-identical. No source fix/rebuild was needed. Actual 26.0 and physical-device
testing remain unverified. Next: planning review and a bounded next-step definition;
do not infer authorization for another feature.

Individual shot/points validation fix: the prior check returned incomplete before
calculating entered makes, so partial contradictions were missed; notices were
also below the form/at the table's far right. The shared check now detects entered
scoring lower bounds greater than points, compares exact equality only with all
made-shot categories, and reports other incomplete/invalid/overflow states honestly.
Owner confirmed larger-text field reachability and keyboard-visible Save passed
on both devices for `56d0777`, closing that fix's remaining layout checks.
Scoring-warning presentation now uses one overarching red text/icon banner above
entry-mode controls, scoped to the selected player or all roster discrepancies.
Exact mismatches and partial lower bounds are distinguished. The header scrolls
and adapts to available height; redundant entry warnings are removed while useful
incomplete/invalid checks remain. Validation/storage and read-only summary are
unchanged. See WORKFLOW.md for verification results and any remaining limitations.


## Workspace and source of truth

Workspace: `/Users/narayanlekhi/Documents/ChatGPT/Basketball stats input app`.
Existing Xcode project: `TeamStats/TeamStats.xcodeproj`.
App source: `TeamStats/TeamStats/`.
Owner-specified public GitHub repository: `https://github.com/nanu731/rps-bball-app`.
Use this existing project and repository. Do not create a replacement project,
nested Git repository, alternate app, or workspace outside this folder.

Read applicable AGENTS.md instructions, PRD.md, and WORKFLOW.md before work.
PRD.md is authoritative for detailed product requirements. WORKFLOW.md defines
coordination and handoffs. This file is the concise entry point and sequence.
Resolve contradictions using the owner's latest explicit decisions; report them
rather than quietly inventing requirements.

## Product context

- High school basketball app for approximately 100 users, including players,
  managers, and coaches. Native Swift/SwiftUI, supporting iPhone and iPad.
- Minimum iOS/iPadOS 26.0. Game fields: date, opponent, our team's home/away
  status, and regular season/playoff. No scrimmages.
- Supabase holds official stats. Google Sheets receives automatic one-way
  exports of published data and accepted corrections.
- All statistical entry is after games. Manual entry first, photo autofill later.
  Absolutely no live game tracking in any phase.
- Initial pilot focuses on manual stats. Online submission first; offline sync
  is low priority. Playbook, videos, and photo extraction follow the pilot.
- Signup supports both email and phone as options; do not require both from
  every user. Authentication details and account linking still need agreement.
- Any app user can submit stats and corrections for owner approval. Selected
  owner-authorized users may publish without case-by-case approval.
- Coaches draw/save plays, and viewers see animated movement. Practice videos
  link to plays. Authorized users upload without individual review; other users
  upload pending clips that only the owner may approve for team viewing.
- A Game Film menu lets coaches/managers upload recorded videos linked to games,
  with the same owner-authorized upload bypass and pending review for other
  eligible uploaders. It follows the manual-stats pilot; no livestreaming or
  automatic video-to-stat extraction is requested.
- Hudl is the likely game-film recording source. Exported-file upload versus Hudl
  links is unresolved; do not assume direct API access or build an integration yet.
- Owner-managed permissions apply to stats, plays, and videos. Separate versus
  shared permission grants remains unresolved.

## Data scope

Player game totals: points, offensive rebounds, defensive rebounds, assists,
turnovers, steals, blocks, fouls, charges drawn, and made/missed counts for twos,
threes, and free throws. Derive total rebounds from offensive + defensive.
Record each of our players' game-total paint touches separately.

Manual box scores support both individual-player and whole-roster table entry
against the same records. Blank means not entered, not zero. Check entered points
against shot makes; preserve discrepancies for correction rather than overwriting
them. Compare game-total box-score points with advanced-sheet possession scoring
when both matching datasets are complete; missing data is not a passed check.

For each team's possessions: paint-touch count, offensive-rebound count,
made/missed tallies by shot type, and turnover outcome. No shot sequence is
collected. Offensive rebounds continue the same possession.

Pair our team's nth possession on the left with the opponent's nth on the right;
each team has independent numbering. Provide reversible entry-complete checkboxes
for the team sheets; unchecked sheets leave the game labeled incomplete data.
Legal possession groups all actions until the opponent legally possesses the
ball, including free throws and offensive rebounds. Period-ending possessions
with actions count; no-action holds until the buzzer do not count.
Completed datasets require an edit request approved by the owner or an authorized
dataset-editing reviewer before changes; revised data needs completion again.
Build drafts first; enforce completion/edit requests later with authenticated
backend permissions. Reviewer scope and reopen details remain to be settled.

Visual direction: restrained native SwiftUI, system typography, clear forms and
tables, consistent spacing and readable contrast. Avoid the owner's listed
gradient/card/animation/font/copy tropes; see PRD.md for the explicit exclusions.
No separate redesign is authorized by these preferences alone.
Owner requests the apple-design skill linked in PRD.md; translate its principles
to native SwiftUI without web libraries or conflicting glass effects.
Latest possession-entry defaults: new turnover No; numeric blanks allowed and
still unentered. Add +1/-1 controls alongside direct entry. Preserve saved nil
turnovers. Owner found horizontal access failing on both devices; vertical scroll
and iPad keyboard-visible save/relaunch passed. Next is a bounded Step 4 fix,
not metrics or backend work.
At possession-sheet completion, blank numeric fields become saved zeros. Warn
with Confirm/Go back and a per-user “Don't show this again” option. Suppression
applies to this warning only; validation/permissions still apply. No conversion
during draft saving or for unadded paired placeholders; box-score semantics stay
unchanged. Implement this later with authenticated completion, not the Step 4 fix.

Paint touch means intentionally establishing two feet in the paint with the ball.
Real Possessions is calculated separately for each team:
`team possessions - team turnovers + team offensive rebounds`.
The revised source notation `FTmade/attempted` yields misses = attempted - made.
A revised PDF draft is available as `rpsadvstatsdraft-revised.pdf`, pending owner
confirmation; old makes-only FT notation cannot supply misses.

Exclude 50/50 balls, ATOs, transition flags, shot-style classifications, timeouts,
quarter-score checkpoints, and any other unrequested collection fields.
Printed PDF names/numbers are arbitrary. Temporary arbitrary roster names/numbers
are explicitly permitted until the owner supplies the fixed roster after tryouts.
Label that roster as temporary; do not invent actual school branding or game stats.
Use obvious TODO markers and truthful empty states for missing owner content.

## Security and review

Publishable Supabase key in the app; secret/privileged keys, spreadsheet
credentials, and AI secrets on trusted infrastructure only. Use Supabase Auth,
RLS, protected owner-managed grants, private media policies, HTTPS, secure
credential storage, and database/server validation. UI restrictions alone do
not establish permission enforcement.

Proposed correction behavior: retain published data while edits await review.
Only accepted changes affect stats and exports. Confirm this before implementing.
Do not add dependencies, restructure files, or delete work without owner approval.

## Remaining owner input by milestone

Foundation can proceed with empty states; it does not require a roster or secrets.

Before final entry/schema work: completed notation examples,
possession/page mapping, remaining paint-touch/possession boundary definitions,
player visibility, enrollment rules, and pending-edit/permission-granularity choices.

Before connected services: Supabase project details (public URL/key only in chat),
owner account identification, auth-provider setup, and Google Sheets destination.
Never ask the owner to paste privileged keys into a handoff.

For GitHub publication: use the owner-specified public repository above. No
remote was configured at the earlier planning inspection; inspect current state
and preserve any remote commits when connecting it.

Current PDF references in the workspace root: `rpsadvstatsdraft-revised.pdf` and
`boxscorestatsheet-revised.pdf`. Both include game type and home/away checkboxes.
`boxscorestatsheet.pdf` remains an unchanged copy of the original template.
A fresh local chat in this same checkout can read these files without inheriting
the planning chat's attachment history. Future supplied files must be saved in
the workspace if they are to be reliably shared across chats.

Before photo import: owner confirmation of the revised advanced PDF and marked
shot/tally examples. The actual roster will be supplied later; labeled temporary
names/numbers are authorized and must remain easy to replace.
Before playbook/video work: editor controls, review details, and media limits.
Before Game Film: eligible upload/view roles, large-file limits, storage budget,
and whether practice/game video grants are shared or separate.

## Development sequence

Each milestone may require several bounded prompts. Complete only the assigned
task, verify it, commit relevant changes, and return the short handoff.

1. Foundation: inspect the existing project/Git state, verify baseline builds,
   and establish simple iPhone/iPad navigation with truthful empty states.
   Connect/push GitHub only once the owner specifies the destination.
2. Resolve entry-specific open requirements; build local box-score, possession,
   and individual paint-touch entry against the agreed fields.
3. Implement local viewing and agreed calculations, including Real Possessions;
   validate against owner-approved examples without inventing sample game data.
4. Configure Supabase tables, Auth, membership, permission grants, and RLS.
   Confirm any dependency installation before adding the SDK.
5. Connect submissions, owner review, authorized publishing, corrections, and
   viewing. Verify with accounts having different permissions.
6. Implement one-way Google Sheets export with correction/duplicate handling.
   Confirm whether export must precede the pilot or immediately follow it.
7. Pilot manual stats on iPhone/iPad; resolve observed issues.
8. Add photo extraction into the existing entry/review workflow.
9. Add dynamic play authoring/viewing, linked practice videos, and Game Film
   uploads/playback linked to game IDs, with backend permission enforcement.
   Reuse common media behavior; split these into bounded prompts. Their relative
   order can be refined later.
10. Verify the complete app, finish distribution requirements, and release more widely.

## Coordination and handoff

Only one chat edits app code at a time. The planning chat owns decisions and
prompts; the implementation chat executes the current prompt. Context-file work
must also be coordinated to prevent overlapping edits.

Preserve existing work and staged changes. Commit only task-relevant files with
descriptive messages; never use a blanket commit to absorb unrelated work.
No force pushes, history rewrites, or deletion of existing work.

Step 1/2 handoffs and verification limitations are recorded in WORKFLOW.md.
Current minimum is 26.0. Build/simulator checks used 26.4; actual execution on
26.0 is unverified because that runtime is not installed.

Return 150–250 words, maximum 300, with:
`STEP`, `RESULT`, `CHECKS`, `GIT`, `DECISIONS`, `BLOCKERS / HUMAN INPUT`, `NEXT`.
Include branch/commit identifiers, dirty state, actual check results, and any
remaining human action. Do not repeat the whole PRD or include secrets.

Native integration review found and fixed transient-check navigation buffer loss
and cross-team completion validation. The affected35-test run passed; actual
interaction checks remain pending until the Mac is unlocked.

Real local native shared-statistics round trips now passed, including accepted
reopening/metrics/reconciliation and fresh verified signup without team authority.
Export worker/source passed54 local SQL and20 synthetic HTTP checks; malformed
Boolean activation is fixed. Google delivery stays disabled and unverified.

Owner export status now independently loads server queued/reserved/failed/delivered
receipts with Retry; errors do not hide the saved game snapshot. Sixteen connected
SDK fixture tests passed, and the actual local native workflow confirmed four
queued, undelivered jobs after four dataset publications. UI interaction and
actual Google delivery remain unverified. The owner has no hosted project yet;
a private Free-only setup guide is prepared, with no billing/SMS configuration.

Export-status navigation race fixed after review;17 affected tests passed.
Snapshot-scoped reads prevent stale results after switching/reopening games.

Playbook source is integrated from Account/team administration: stable generic
markers, authored movement steps, native drag/coordinate controls, playback and
reduced-motion positions; drafts, independent review, immutable publication and
successor revisions are server-enforced. Seven native play tests and54 actual
rollback SQL checks passed. The real local native SDK also saved/published/reopened
a play and retained its accepted drawing while creating a stable-marker successor.
Actual gesture/playback/VoiceOver/larger-text device interaction remains unverified.

Photo review is wired to selected existing player/possession draft targets in local
and shared entry. Native PhotosPicker/Vision keeps preview/text transient, validates
image/request bounds, proposes only standalone valid counts, and requires explicit
field mapping/value confirmation before changing unsaved buffers. Eight review
tests passed plus actual Vision on a corrected synthetic printed image. The first
image’s REBOUNDS0 was read as letterO; no substitution was added. Real marked-form
accuracy, picker interactions and both-device layout remain unverified.

Private video-link metadata/review is integrated from published plays and shared
game details. Ordinary active members submit practice links; protected film
eligibility remains separate from publication bypass. Only the owner approves
pending video resources; legacy review grants are inspection only. Nine native
fixtures and73 actual rollback SQL checks passed. Real local SDK practice/film
save/submit/owner-approve/reopen/successor checks passed without opening providers.
File upload, private playback, Hudl rights and hosted/media budget enforcement
remain unimplemented/unverified; saving a link does not establish them.

Play review: Standards0 breaches (optional action-enum suggestion); Spec1 stranded
stale-draft defect. Explicit retained-history recovery fixes it;37 additional
actual SQL checks and8 native play tests passed. Both play/media editors retain
unsaved buffers after intentional recovery; actual recovery navigation still
requires device inspection.

Photo import now reads bounded native provider files before allocating image Data;
all14 integrated photo tests passed. Possession review includes explicit
Unanswered/Yes/No turnover mapping, never inferred from text or numeric0.
Counts and optional Boolean answers enter only the existing unsaved record.
