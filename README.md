# rps-bball-app

TeamStats is a native SwiftUI app for after-game high-school basketball statistics
on iPhone and iPad (minimum iOS/iPadOS 26.0). Managers enter box scores,
team possessions, and individual paint-touch totals; players view accepted shared
statistics. Device-local saved drafts are separate, incomplete and unreviewed.

Owner scope update2026-10-17: the first pilot may use shared manual statistics
while automatic Sheets/media delivery remains unfinished. An optional iPad-first
shot recorder for both teams, with per-player our-team shots and side-panel free
throws, now has implemented source and isolated local acceptance. Hosted, device
and release gates remain in READINESS.md. See
[shot requirements](PRD.md#in-game-shot-recorder-amendment--2026-10-17).
The completion target is2026-11-17, not a release-readiness claim.

### Manual-statistics pilot boundary

The owner permits shared manual statistics before automatic Sheets/media delivery.
This is scope approval, not deployment or release acceptance. The2026-11-17 target
is a planning target. Follow [READINESS.md](READINESS.md) for current gates.

Pilot acceptance uses a clearly labeled synthetic game and distinct admitted and
denied accounts: verify admission, real roster identity, shared draft save/reopen,
independent sheet completion, ordinary submission/review and authorized publication,
viewer access to accepted versions, correction recovery and revoked access. Keep
these server-confirmed states distinct. Existing synthetic checks are recorded in
TESTING.md; they do not authorize a new provider activation or real-record upload.
Actual hosted signup/access, distribution, privacy/retention, device/accessibility
and selected pilot participants remain required acceptance inputs.

The selected support/security/deletion contact is in READINESS.md and Using
TeamStats. It does not establish a response commitment or deletion executor.
The10GB owner allocation is for encrypted backup generations only, not app/media
hosting. Local JSON export is plaintext and user-directed; no automatic Google
backup, expiry, retention, deletion or real-data transfer is configured.

### Media scope

Owner decision (2026-10-12): approximately 25 regular users plus initial testers.
Full-game film stays on Hudl, with optional game-linked shortcuts in TeamStats.
Practice clips linked to plays are the in-app upload/playback target. These are
implemented source paths with actual isolated Auth/Storage/native playback checks;
hosted clip capacity under the strict $0 budget and real Hudl links remain unverified.

## Native appearance

Maroon is confirmed for this Rutgers Prep app. AccentColor and prominent controls
use provisional accessible light/dark variants from DESIGN_SYSTEM.md, not official
school hex. Logo, final icon and actual roster remain owner-provided TODOs. Rendered
appearance, accessibility and interaction checks remain separate from contrast math.

## Current implementation

Local game creation, temporary roster, manual stat drafts, and read-only game
summaries are implemented. Scoring checks flag exact mismatches and proven
partial-score contradictions. An actual isolated iPhone journey verified immediate
consolidated scoring feedback, multiple affected players, switching modes and saved/reopened
values. Maximum-text and remaining device checks have their own evidence limits.
The approved native game ledger adds saved box-score viewing, explicit player editing,
and one calm “Check scoring” notice above entry modes. Horizontal indicators are
hidden while native table scrolling remains available. See TESTING.md for current acceptance.
The local entry screens remain local and unreviewed; shared server workflows are separate.

“Using TeamStats” is revisitable from Local games and Account. It explains local
versus shared work, recovery, completion and optional retained clips. It offers an
explicit private JSON copy of saved local drafts; no in-app import/restore or upload
is provided. [Recovery preparation](RECOVERY.md) adds separately tested synthetic
offline restoration and a no-deploy CI boundary; hosted disaster recovery remains
unverified. Account now prepares request-only deletion intake with explicit confirmation and
server receipts; existing servers remain unavailable until separately reviewed
activation. Deletion execution and owner-selected privacy/reporting/retention
policies remain unfinished. New local saves request complete file protection;
physical protection behavior remains unverified.

The Account tab implements email-link and code verification, secure session
restore, retry and sign-out. Configure an authorized nonproduction server's URL
and publishable key privately on the device. Allow the exact email redirect
`com.narayanlekhi.teamstats://auth/callback` in Supabase Authentication's URL
Configuration. Request a sign-in email and open its link on the same device; PKCE
binds the exchange to that device's Keychain challenge. Typed email codes remain
supported when the configured sender supplies them. New Free projects using the
default sender cannot edit templates; do not upgrade for codes. Remote SMS stays
disabled under the $0 budget. Actual local Auth/gateway/native SDK tests passed;
limited owner hosted email sign-in and identity/session preflight are recorded.
The owner executed reviewed nonproduction activation; independent hosted SQL
readback passed. Signed synthetic nonproduction authorization acceptance passed; team-wide email
delivery remains pending. Shared entry/review and accepted summaries are accessible from Team → Shared games and statistics. These use real server commands;
local games are kept separate. Native fixtures and real local SDK workflows passed; hosted signed access passed, while remaining full device workflows are unverified. The owner can inspect per-game server export status with independent error/Retry. A trusted [export worker](supabase/exports.md) is implemented with Google disabled
by default; actual Sheets delivery, full-form photo accuracy and hosted media delivery remain
pending. Published plays offer private practice clips and earlier reviewed links;
shared games offer scouting PDFs and Hudl shortcuts. Actual isolated file transfer,
validation, owner review and retained-viewer navigation passed; video controls remain unverified and hosted delivery disabled. Provider
links require independent access, and saving them proves no rights or playback.
Playbook authoring/review/court-movement playback is available from Team → Playbook;
local database and native SDK verification passed, with iPhone published movement and hosted signed checks passed; authored editing
and full device acceptance remain pending.
Photo review is available inside local/shared player and possession drafts. Choose
a photo, review recognized text, map existing fields and confirm values; applying
changes only the unsaved buffer. Whole-form notation/player mapping is not inferred.
On-device recognition can misread zero as O; representative marked-form accuracy
and device interactions remain unverified. No app photo/text persistence or upload occurs; Photos may create temporary
provider files. Possession turnover answers require explicit Unanswered/Yes/No
review; they are never inferred from recognized text.
Box-score, possession and player paint-touch entry remain after-game. The implemented
shot recorder is the only authorized in-game exception; clocks, possession tracking,
substitutions, lineups and public live-score broadcasts remain outside scope.

### Where to find connected features

The Team tab now opens member activities directly: shared games/statistics,
playbook and team roster. It uses an adaptive sidebar/detail workspace on iPad
and native collapsed navigation on iPhone. Request admission there using a private
invitation code; Account remains for sign-in/session configuration. Authorized
management is a separate Team home → Manage team destination. Local drafts remain
in their separate tab and are never automatically uploaded.

Shared game → Game Film opens reviewed Hudl shortcuts. New film links require
safe HTTPS destinations on hudl.com/www.hudl.com; historical metadata stays intact.
Hudl independently controls access. Both simulator families passed synthetic Hudl/scouting navigation; real provider links and rights remain unverified.

| Feature | Path and current limit |
| --- | --- |
| Account | Account tab; private device configuration, email link/code verification, session Retry/sign-out. Hosted SQL readback passed; signed synthetic permission acceptance passed; real SMS disabled. |
| Owner administration | Team → Manage team; membership admission, roster add/edit/archive, separate grants and bounded delegation. Historical identities retained. |
| Shared statistics | Team → Shared games and statistics; games, individual/table box scores, independent paired possessions and player paint totals. No automatic upload of local records. |
| Completion and review | Shared game details; server-confirmed independent completion, approved edit requests, review/publication and accepted summaries. Possession zero conversion uses the confirmed warning flow. |
| Metrics | Accepted shared summaries; missing inputs stay unavailable. Only accepted versions affect agreed metrics and reconciliation. |
| Sheets status | Shared game details, owner only; server outbox status and Retry. Live Google delivery disabled and unverified. |
| Photo review | Existing local/shared drafts; map/confirm recognized values, apply to unsaved input, then explicitly Save. Real form accuracy unverified. |
| Plays and clips | Team → Playbook; authored movement and reviewed revisions. Published play → Practice clips, optional Keep on device; Saved clips tab opens retained copies. Hosted file delivery pending. |
| Scouting and Hudl | Shared game → Scouting reports or Game Film; separate current capabilities and owner review. Hudl controls film access. |

Saved play/media recovery preserves earlier proposals as read-only history.
After an uncertain response, explicitly Reload and confirm attachment to a
validated recovered draft; input buffers are retained and Save remains separate.
Media history is filtered by selected play/game before transfer.
Approved statistical corrections likewise retain stale unfinished drafts as
read-only history; an authorized reviewer must approve a current-version edit
request before its recovered working draft can receive retained entries.

### Release readiness

This branch is not release-ready. Signed nonproduction access/lifecycle checks passed;
team email delivery, trusted Google worker configuration and hosted media
capacity/delivery remain blocked. Actual isolated file validation/upload/review and
explicit retention passed. Full-app offline startup opens a previously retained
clip with an honest unknown-rights disclosure; native video play/pause/scrub remains
unverified. XCUITest recovered real input without resetting simulators, although
several bounded journeys remain blocked by native control exposure or focus.

Representative local light/dark, larger-text and rotation checks passed, and the
current device-specific evidence is recorded in TESTING.md. Full changed-screen
appearance, maximum text reachability, Reduce Motion, VoiceOver, shared recovery/
completion, photo interaction and hardware/actual26.0 acceptance remain open.
Physical testing is explicitly deferred. Real branding/roster, signing/distribution
and production approval remain outstanding. No paid service, public submission or
automatic original-record upload is enabled.

The owner-requested polish audit added unsaved-navigation confirmations, pending
field locks/progress, clearer admission next actions and protected-content hiding
after confirmed server denial. Recovery buffers remain private until an authorized
reload; only explicitly retained private clips have persistent connected caching; full
shared-data offline sync remains deferred. Native
regressions and simulator compilation passed, while slow-network, background/
termination, accessibility and physical-device acceptance remain separate checks.

A consumer Gmail sender with eligible app-password access is a documented no-cost
SMTP candidate for team email on Free; it is not configured or verified delivery.
Account/security prerequisites, private trusted sender configuration and real inbox
checks remain required. Do not invite players into provider administration to
work around default-email restrictions. See [Supabase SMTP](https://supabase.com/docs/guides/auth/auth-smtp)
and [Google app passwords](https://support.google.com/accounts/answer/185833).

## Project and planning

### Short app flows

Local and shared records are separate; signing in does not upload local games.
These are implemented navigation/state paths, not proof that hosted acceptance
or every current gesture has passed. See [TESTING.md](TESTING.md) for limitations.

| User task | Path and result |
|---|---|
| Local practice entry | Local drafts → Add game → Game → View box score → expand a player → Edit player stats. Individual/table entry shares one draft; a calm Check scoring notice explains proven discrepancies without blocking Save draft. Possession/player paint-touch drafts and the read-only summary remain available from Game. Saved only on this device; not official data. |
| Join the team | Account → private server configuration → email sign-in on the same device → Team tab. Request admission if needed; pending admission grants no active-member access. SMS remains disabled. |
| Enter shared statistics | Team → Shared games and statistics → game → editable dataset → Save → explicit completion → submit for review, or authorized publication. Server reply determines status. |
| View accepted statistics | Shared game → accepted summary. Accepted versions drive supported metrics/reconciliation; missing inputs remain unavailable. |
| Correct completed data | Request edit → authorized reopen approval → new draft → edit/save/complete → review/publication. Accepted history stays intact; retained stale buffers require explicit authorized attachment and Save. |
| Owner/delegate administration | Team → Manage team → roster/members/grants/delegation. Archive preserves history; capability use and permission to grant it are separate, server-enforced authorities. |
| Plays and practice film | Team → Playbook → author saved movement/review/publish → published play → Practice clips. Upload/validation/review precede playback; optional retained copies appear in Saved clips. |
| Game film and photo input | Shared game → Game Film Hudl shortcuts; eligible authors submit, owner reviews. Existing draft → photo review → map/confirm → Apply → explicit Save. Photo Apply does not complete/publish. |

Loading, empty, pending admission, failed requests and denied access must have
different messages and next actions. Unfinished provider/media work remains
identified above. Scouting reports for upcoming opponents follow ADR0003. The scouting picker, draft/review, private transfer and PDF viewer are implemented.
Actual isolated trusted validation/storage/retrieval passed; hosted and rendered UI
acceptance remain pending.

### Technical documentation

- [Architecture and source map](ARCHITECTURE.md): modules, storage and integration boundaries.
- [Security boundaries](SECURITY.md): authority, controls and verification gaps.
- [Testing and acceptance](TESTING.md): suites, safe prerequisites and remaining gates.
- [UI/UX skills and autonomous verification](docs/agents/ui-ux-workflow.md): selected native guidance, skill routing and the next automation diagnostic.
- [Glossary](GLOSSARY.md): local/shared data, completion, publication and recovery terminology.

Update this flow section when visible navigation or lifecycle changes; keep
technical contracts in their own documents rather than duplicating them here.

Open `TeamStats/TeamStats.xcodeproj` in Xcode. Select an iPhone/iPad simulator
to run; physical-device signing requires the developer's own Apple account.
Owner confirmed private hosted sign-in and matching app/Auth Users UUID. Trusted
SQL account verification and dashboard Free/phone-disabled checks now passed.
The owner reports successful reviewed activation. Later reviewed hosted follow-ups through migration13 and signed synthetic access
checks are recorded in TESTING.md; bootstrap is already verified and must not be rerun. Signed synthetic distinct-user checks later passed within TESTING.md’s recorded hosted scope; current Auth/provider gates remain separate.
Most simulator verification has used 26.4; actual 26.0 and physical devices remain
untested. The approved official Supabase Swift SDK is pinned to 2.55.3; connected
account source is implemented and tested with isolated SDK responses; trusted hosted
SQL activation readback passed; shared workflows have passed isolated local integration and the recorded signed synthetic hosted checks. Full hosted delivery/release acceptance remains pending.

- [PRD](PRD.md): product scope, data definitions, design direction, open decisions.
- [Project context](PROJECT_CONTEXT.md): current state and implementation sequence.
- [Workflow](WORKFLOW.md): bounded tasks, checks, handoffs, readiness checklist.

Printed PDF names and the development roster are placeholders. Actual roster and
branding will come from the owner. Do not commit real student records or secrets.

## Backend configuration policy

Supabase will be the official store; Google Sheets receives one-way exports.
Privileged backend, Google, and AI credentials must remain on trusted server
infrastructure. Putting a secret in an environment variable during an iOS build
does not make it safe to ship in the app. Client Supabase URL/publishable key are
configuration, protected by authentication and RLS rather than secrecy.

Separate development/staging and production configuration before shared pilot
data. No backend credentials or environment files are needed for local stat drafts.
The Account tab stores its private server configuration in device Keychain. `.gitignore` excludes local environment files and Xcode user state;
already staged personal files must still be excluded explicitly from commits.
The operating budget is strictly $0: paid delivery, AI calls and services with
possible overages remain disabled unless separately authorized. Private local
completion tickets/configuration are excluded from the public repository.

Network deadlines, session/refresh semantics, durable file-admission controls and
remaining hosted activation gates are documented in [NETWORK.md](NETWORK.md).
Synthetic/native CI does not certify hosted Auth, provider billing or release readiness.


### Optional shot capture: local and shared boundaries

Game details expose a separate shot recorder and recorded-shot charts. Our field
goals use the existing player identity; opponent observations are team-only. Each
field goal has a schematic location, explicit2/3 value and Make/Miss or pending
answer. FT series retain each answer separately and never acquire court dots.
Atomic local journals retain corrections/Undo and do not alter official stat stores.

Shared recording requires a server designation and distinct recording/review/
publication capabilities. Prepare an actual-roster capture online; its narrowly
scoped device journal can then continue through venue interruptions. Reconnect and
explicitly submit immutable batches; uncertain replies use receipt recovery.
Fresh authority is required. Competing branches require explicit reviewer adoption,
not automatic merging. Local temporary-roster captures are never auto-uploaded.

Charts show team/player observed counts, pending inputs, schematic basket-relative
bands and independent after-game comparisons. An authorized statistics reviewer
may separately confirm either team's final-score reference, leaving the other
unentered. Score agreement is not attempt coverage or completion. Coverage signoff
requires designated-manager confirmation followed by owner/current-statistics-reviewer
approval of the exact saved version. Later saved edits require renewed signoff;
original approvals remain attached to their versions. Migrations18–20 are tested in new synthetic databases
only; existing/hosted activation and acceptance are separate gates. See READINESS.md.
