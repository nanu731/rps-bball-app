# rps-bball-app

TeamStats is a native SwiftUI app for after-game high-school basketball statistics
on iPhone and iPad (minimum iOS/iPadOS 26.0). Managers enter box scores,
team possessions, and individual paint-touch totals; players view saved stats.

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
hosted delivery and setup remain unverified. Shared entry/review and accepted summaries are accessible from Account → Team
administration → Shared games and statistics. These use real server commands;
local games are kept separate. Native fixtures and real local SDK workflows passed; hosted setup
and two-device UI checks are still pending. The owner can inspect per-game server export status with independent error/Retry. A trusted [export worker](supabase/exports.md) is implemented with Google disabled
by default; actual Sheets delivery, full-form photo accuracy and videos remain
incomplete. Private reviewed practice/game-film links are available from published
plays/shared games; file uploads and in-app playback are unavailable. Provider
links require independent access, and saving them proves no rights or playback.
Playbook authoring/review/playback is available from team administration;
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

## Project and planning

Open `TeamStats/TeamStats.xcodeproj` in Xcode. Select an iPhone/iPad simulator
to run; physical-device signing requires the developer's own Apple account.
Most simulator verification has used 26.4; actual 26.0 and physical devices remain
untested. The approved official Supabase Swift SDK is pinned to 2.55.3; connected
account source is implemented and tested with isolated SDK responses; a hosted
project is not configured and shared workflows have passed isolated local integration, not hosted verification.

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
