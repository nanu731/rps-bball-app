# rps-bball-app

TeamStats is a native SwiftUI app for after-game high-school basketball statistics
on iPhone and iPad (minimum iOS/iPadOS 26.0). Managers enter box scores,
team possessions, and individual paint-touch totals; players view saved stats.

## Current implementation

Local game creation, temporary roster, manual stat drafts, and read-only game
summaries are implemented. Scoring checks flag exact mismatches and proven
partial-score contradictions. The latest consolidated warning presentation still
awaits owner manual verification. All data is currently local and unreviewed.

The Account tab implements email-link and code verification, secure session
restore, retry and sign-out. Configure an authorized nonproduction server's URL
and publishable key privately on the device. Allow the exact email redirect
`com.narayanlekhi.teamstats://auth/callback` in Supabase Authentication's URL
Configuration. Request a sign-in email and open its link on the same device; PKCE
binds the exchange to that device's Keychain challenge. Typed email codes remain
supported when the configured sender supplies them. New Free projects using the
default sender cannot edit templates; do not upgrade for codes. Remote SMS stays
disabled under the $0 budget. Actual local Auth/gateway/native SDK tests passed;
hosted delivery and setup remain unverified. Shared entry/review source is being
integrated. Sheets delivery, photo autofill, animated plays and videos remain
incomplete.
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
