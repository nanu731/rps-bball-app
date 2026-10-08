# TeamStats — Product Requirements

Status: working draft; implementation has not been authorized.
Last updated: 2026-10-08.

## Purpose and users

Create an app for a high school basketball team so managers can enter collected
data after games and players can easily view their box scores and advanced stats.
Plan for approximately 100 potential users, not a single-device personal tool.

## Confirmed decisions

- Build a native app in Swift using SwiftUI and Xcode.
- Use Supabase as the shared backend.
- All entry happens after games.
- Phase 1: manual entry.
- Phase 2: photo extraction that autofills an editable entry form.
- Upload recorded data to a spreadsheet.
- The owner will supply the actual collected data fields; do not invent them.
- Live tracking is excluded entirely, including from future phases.

## Phase 1 — After-game manual entry

Managers enter the owner's specified data through an easy-to-use interface.
Players can view the agreed box scores and statistical summaries.

Requirements to finalize before implementation:

- TODO_COLLECTED_DATA: exact fields, units, definitions, and required/optional status.
- TODO_INPUT_EXAMPLES: existing forms or spreadsheet examples supplied by the owner.
- TODO_MANUAL_ENTRY_FLOW: entry order, game identification, and correction behavior.
- TODO_ADVANCED_STATS: desired metrics and formulas supported by collected inputs.
- TODO_PUBLISHING_RULES: who may submit, approve, publish, and correct data.
- TODO_PLAYER_VISIBILITY: own stats, all team stats, or another access policy.
- TODO_SPREADSHEET_SERVICE: Google Sheets, Excel, or another service.
- TODO_DATA_AUTHORITY: database or spreadsheet as the official source; determine
  whether coaches must edit official records in the spreadsheet.
- TODO_OFFLINE_REQUIREMENTS: whether drafts must survive connectivity loss and
  when uploads should retry.
- TODO_ACCOUNT_ENROLLMENT: team invitations, login method, and role assignment.
- TODO_DEVICE_COVERAGE: confirm iPhone/iPad needs and any Android/browser access.

Proposed acceptance criteria, pending owner confirmation:

- A manager can enter and correct an actual after-game record using agreed fields.
- An authorized player can view published records and agreed calculated stats.
- Missing inputs remain visibly missing; never manufacture values or metrics.
- Calculations match manually verified examples supplied or approved by the owner.
- Retried submissions do not duplicate records; corrections update the intended record.
- Spreadsheet integration respects the agreed official source and access rules.
- Database permissions reject unauthorized reads, writes, and role changes.

## Phase 2 — Photo autofill

Add photo capture or selection after the manual workflow is working and verified.
Extract the same agreed fields into the manual-entry form so both methods share
validation and submission behavior.

Proposed requirements, pending owner confirmation:

- Show extracted values for human review before upload/publication.
- Leave unreadable or ambiguous values visibly unresolved instead of guessing.
- Allow correction of every extracted value.
- Test extraction against actual team forms and manually verified records.

Open decisions:

- TODO_PHOTO_FORMATS: handwriting, printed tables, screenshots, and layout variation.
- TODO_EXTRACTION_PROVIDER: choose after evaluating representative images.
- TODO_PHOTO_HANDLING: image access, retention, deletion, and external processing.
- TODO_EXTRACTION_ACCEPTANCE: agreed accuracy/review criteria and usage budget.

## Security direction

Use the Supabase publishable key in the app; keep privileged Supabase keys,
AI credentials, and spreadsheet secrets on trusted server infrastructure.
Enforce team and role access through database policies, including RLS on exposed
tables, and protect role/approval fields from user tampering. Protect uploaded
images through storage policies.

Use Supabase Auth, HTTPS, secure session credential storage, server/database
validation, and authentication rate limits. Return only authorized data. Use
safe SDK queries or parameterized SQL. Review dependency vulnerabilities.
Cookie and browser-header requirements apply if a web interface is introduced.
Custom encryption and bot protection need assessment against the final scope.

## Explicit exclusions

- No live game tracking, live scoring, real-time event entry, game clocks,
  substitutions, or live lineup tracking.
- No fabricated team roster, school branding, data fields, or statistical claims.
- No implementation or dependency installation until the owner authorizes it.

## Release decisions

- TODO_BUDGET: backend, extraction, and distribution budget.
- TODO_DISTRIBUTION: pilot group and long-term app distribution method.
- TODO_RELEASE_CRITERIA: agreed device coverage and end-to-end checks.

Backend choice does not determine which advanced stats are possible: collected
inputs and documented calculations do. Do not expand collection scope merely
to enable a metric without the owner's agreement.
