# rps-bball-app

TeamStats is a native SwiftUI app for after-game high-school basketball statistics
on iPhone and iPad (minimum iOS/iPadOS 26.0). Managers enter box scores,
team possessions, and individual paint-touch totals; players view saved stats.

## Current implementation

Local game creation, temporary roster, manual stat drafts, and read-only game
summaries are implemented. Scoring checks flag exact mismatches and proven
partial-score contradictions. The latest consolidated warning presentation still
awaits owner manual verification. All data is currently local and unreviewed.

The Account tab implements email/phone code requests, verification, secure session
restore, retry and sign-out. Enter an authorized nonproduction server's URL and
publishable key privately on the device; do not use a secret/service-role key.
Remote SMS is disabled under the strict $0 budget. Actual hosted delivery and
delivery is not yet verified. Server access/roster source and isolated
SQL tests are in `supabase/`; actual local database, Auth/gateway and native SDK
checks passed. Hosted integration is not configured.
Shared storage, completion/review, reconciliation, Google Sheets export, photo
autofill, animated plays and videos remain incomplete.
There is no live tracking in any phase.

## Project and planning

Open `TeamStats/TeamStats.xcodeproj` in Xcode. Select an iPhone/iPad simulator
to run; physical-device signing requires the developer's own Apple account.
Most simulator verification has used 26.4; actual 26.0 and physical devices remain
untested. The approved official Supabase Swift SDK is pinned to 2.55.3; connected
account source is implemented and tested with isolated SDK responses; a hosted
project is not configured and shared data workflows are not implemented.

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
