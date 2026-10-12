# rps-bball-app

TeamStats is a native SwiftUI app for after-game high-school basketball statistics
on iPhone and iPad (minimum iOS/iPadOS 26.0). Managers enter box scores,
team possessions, and individual paint-touch totals; players view accepted shared
statistics. Device-local saved drafts are separate, incomplete and unreviewed.

## Current implementation

Local game creation, temporary roster, manual stat drafts, and read-only game
summaries are implemented. Scoring checks flag exact mismatches and proven
partial-score contradictions. The latest consolidated warning presentation still
awaits owner manual verification. The local entry screens remain local and unreviewed; shared server workflows are separate.

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
readback passed. Team-wide email delivery and signed authorization acceptance
remain pending. Shared entry/review and accepted summaries are accessible from Account → Team
administration → Shared games and statistics. These use real server commands;
local games are kept separate. Native fixtures and real local SDK workflows passed; hosted setup
and two-device UI checks are still pending. The owner can inspect per-game server export status with independent error/Retry. A trusted [export worker](supabase/exports.md) is implemented with Google disabled
by default; actual Sheets delivery, full-form photo accuracy and videos remain
incomplete. Private reviewed practice/game-film links are available from published
plays/shared games; file uploads and in-app playback are unavailable. Provider
links require independent access, and saving them proves no rights or playback.
Playbook authoring/review/court-movement playback is available from team administration;
local database and native SDK verification passed, while device interaction and
hosted verification remain pending.
Photo review is available inside local/shared player and possession drafts. Choose
a photo, review recognized text, map existing fields and confirm values; applying
changes only the unsaved buffer. Whole-form notation/player mapping is not inferred.
On-device recognition can misread zero as O; representative marked-form accuracy
and device interactions remain unverified. No app photo/text persistence or upload occurs; Photos may create temporary
provider files. Possession turnover answers require explicit Unanswered/Yes/No
review; they are never inferred from recognized text.
There is no live tracking in any phase.

### Where to find connected features

| Feature | Path and current limit |
| --- | --- |
| Account | Account tab; private device configuration, email link/code verification, session Retry/sign-out. Hosted SQL readback passed; signed permission acceptance pending; real SMS disabled. |
| Owner administration | Account → Team administration; membership admission, roster add/edit/archive, separate grants and bounded delegation. Historical identities retained. |
| Shared statistics | Team administration → Shared games and statistics; games, individual/table box scores, independent paired possessions and player paint totals. No automatic upload of local records. |
| Completion and review | Shared game details; server-confirmed independent completion, approved edit requests, review/publication and accepted summaries. Possession zero conversion uses the confirmed warning flow. |
| Metrics | Accepted shared summaries; missing inputs stay unavailable. Only accepted versions affect agreed metrics and reconciliation. |
| Sheets status | Shared game details, owner only; server outbox status and Retry. Live Google delivery disabled and unverified. |
| Photo review | Existing local/shared drafts; map/confirm recognized values, apply to unsaved input, then explicitly Save. Real form accuracy unverified. |
| Plays and video links | Team administration → Playbook; authored movement and reviewed revisions. Published plays link practice resources; shared games link Game Film. Video files/playback incomplete. |

Saved play/media recovery preserves earlier proposals as read-only history.
After an uncertain response, explicitly Reload and confirm attachment to a
validated recovered draft; input buffers are retained and Save remains separate.
Media history is filtered by selected play/game before transfer.
Approved statistical corrections likewise retain stale unfinished drafts as
read-only history; an authorized reviewer must approve a current-version edit
request before its recovered working draft can receive retained entries.

### Release readiness

This branch is not a completed hosted integration or release. Nonproduction
signed access/lifecycle acceptance, team email delivery, trusted Google
worker configuration and actual video upload/transfer enforcement remain blocked.
New UI needs iPhone/iPad rotation, larger text, VoiceOver, keyboard/Save and
recovery/photo interaction checks. Simulator inspection recovered, but native
input failed with `-10005: noWindowsAvailable`; those interactions remain unverified. Earlier owner
verification does not verify new screens. Real branding/icon, signing/distribution
and explicit production/release approval remain outstanding. No paid service,
public submission or automatic production-data upload is enabled.

The owner-requested polish audit added unsaved-navigation confirmations, pending
field locks/progress, clearer admission next actions and protected-content hiding
after confirmed server denial. Recovery buffers remain private until an authorized
reload; no persistent connected cache or full offline sync was added. Native
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
| Local practice entry | Games → Add game → game details → box-score/possession/player paint-touch drafts → Save draft → read-only summary. Saved only on this device; not official data. |
| Join the team | Account → private server configuration → email sign-in on the same device → Team administration. Request admission if needed; pending admission grants no active-member access. SMS remains disabled. |
| Enter shared statistics | Team administration → Shared games and statistics → game → editable dataset → Save → explicit completion → submit for review, or authorized publication. Server reply determines status. |
| View accepted statistics | Shared game → accepted summary. Accepted versions drive supported metrics/reconciliation; missing inputs remain unavailable. |
| Correct completed data | Request edit → authorized reopen approval → new draft → edit/save/complete → review/publication. Accepted history stays intact; retained stale buffers require explicit authorized attachment and Save. |
| Owner/delegate administration | Team administration → roster/members/grants/delegation. Archive preserves history; capability use and permission to grant it are separate, server-enforced authorities. |
| Plays and practice film | Team administration → Playbook → author saved movement/review/publish → published play → practice-video links. Metadata does not prove file upload or playback. |
| Game film and photo input | Shared game → Game Film links; eligible authors submit, owner reviews. Existing draft → photo review → map/confirm → Apply → explicit Save. Photo Apply does not complete/publish. |

Loading, empty, pending admission, failed requests and denied access must have
different messages and next actions. Unfinished provider/media work remains
identified above. Scouting reports for upcoming opponents follow ADR0003. Bounded native PDF
input preparation is tested; there is no report upload screen or verified private
report storage/retrieval yet.

### Technical documentation

- [Architecture and source map](ARCHITECTURE.md): modules, storage and integration boundaries.
- [Security boundaries](SECURITY.md): authority, controls and verification gaps.
- [Testing and acceptance](TESTING.md): suites, safe prerequisites and remaining gates.
- [Glossary](GLOSSARY.md): local/shared data, completion, publication and recovery terminology.

Update this flow section when visible navigation or lifecycle changes; keep
technical contracts in their own documents rather than duplicating them here.

Open `TeamStats/TeamStats.xcodeproj` in Xcode. Select an iPhone/iPad simulator
to run; physical-device signing requires the developer's own Apple account.
Owner confirmed private hosted sign-in and matching app/Auth Users UUID. Trusted
SQL account verification and dashboard Free/phone-disabled checks now passed.
The owner reports successful reviewed activation. Independent hosted readback
verified nine history entries, protections on20 app tables, active owner membership
and one bootstrap audit. Signed distinct-user workflow checks remain pending.
Most simulator verification has used 26.4; actual 26.0 and physical devices remain
untested. The approved official Supabase Swift SDK is pinned to 2.55.3; connected
account source is implemented and tested with isolated SDK responses; trusted hosted
SQL activation readback passed; shared workflows have passed isolated local integration, with signed hosted acceptance still pending.

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
