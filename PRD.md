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
- Collected fields are specified below; definitions and input examples still
  require owner clarification. Do not add collection fields without agreement.
- Live tracking is excluded entirely, including from future phases.

## Phase 1 — After-game manual entry

Managers enter the owner's specified data through an easy-to-use interface.
Players can view the agreed box scores and statistical summaries.

### Confirmed collected data

**Player box-score game totals:**

- Points.
- Rebounds.
- Assists.
- Turnovers.
- Steals.
- Blocks.
- Fouls.
- Charges drawn.
- Three-point shots made and missed, as separate counts.
- Two-point shots made and missed, as separate counts.
- Free throws made and missed, as separate counts.

**Player advanced-data game totals:**

- Each of our players' total paint touches in the game.

**Game possession data:**

- Number of possessions in the game; separate-team versus combined counting
  is not yet specified.
- Individual possession records for both home and away teams, containing:
  - Number of paint touches.
  - Number of offensive rebounds.
  - Shot types taken: two-pointer, three-pointer, and/or free throws.
  - Whether the possession resulted in a turnover.

Possession records are entered after games. They do not authorize live tracking.
The owner has not specified shot outcomes, counts per shot type, shot order,
player attribution within possessions, or points scored per possession.
Do not treat those as collected data or infer them from separate game totals.
Opponent player box scores and opponent player paint-touch totals have not been
requested; the confirmed opponent data is possession-level team data.

### Definitions to resolve

- TODO_FIELD_DEFINITIONS: counting conventions, required/optional fields, whether
  rebounds means total rebounds, and handling missing values versus recorded zero.
- TODO_PAINT_TOUCH_DEFINITION: what qualifies, whether repeated touches count,
  and whether possession paint touches are linked to particular players.
- TODO_POSSESSION_BOUNDARIES: when a possession starts/ends, whether an offensive
  rebound continues it, and how free throws or period endings are handled.
- TODO_POSSESSION_TOTAL_SCOPE: separate home/away totals or combined game total;
  entered total versus total computed from complete possession records.
- TODO_POSSESSION_SHOT_DETAIL: shot-type presence versus counts or individual
  attempts; whether outcomes and sequence are actually recorded.
- TODO_GAME_IDENTIFICATION: how games, teams, home/away status, and player records
  are identified and associated with one another.

### Analysis direction

The owner wants team-specific and individualized advanced statistics, with
deductive calculations, inductive pattern finding, and abductive hypotheses
from the dataset. The app must distinguish measured totals, derived metrics,
observed associations, and hypotheses. Advanced statistical analysis does not
automatically require AI-generated interpretation.

Candidate analyses for discussion, not yet an approved metric list:

- Shooting percentages from makes / (makes + misses), and points by shot type.
- Paint touches per possession and the share of possessions with a paint touch.
- Possession turnover frequency, compared across recorded paint-touch counts.
- Offensive rebounds per possession and shot-type patterns by paint-touch count.
- Individual game/season profiles using each player's box score and paint touches.

Definitions and denominator rules must be agreed before implementing metrics.
Possession records need sufficient completeness for possession-based comparisons.
Patterns involving paint touches can support hypotheses; they do not by themselves
establish that paint touches caused a particular outcome.
Player-level possession effectiveness requires player attribution that has not
been confirmed. Scoring efficiency by possession category requires scoring or
shot outcomes linked to those possessions; game totals alone cannot supply it.

Requirements to finalize before implementation:

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
- Entered points can be checked against 2 × two-point makes + 3 × three-point
  makes + free-throw makes; flag discrepancies for review rather than silently
  overwriting recorded values. This validation rule is proposed for confirmation.
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
- No fabricated team roster, school branding, additional data fields, or statistical claims.
- No implementation or dependency installation until the owner authorizes it.

## Release decisions

- TODO_BUDGET: backend, extraction, and distribution budget.
- TODO_DISTRIBUTION: pilot group and long-term app distribution method.
- TODO_RELEASE_CRITERIA: agreed device coverage and end-to-end checks.

Backend choice does not determine which advanced stats are possible: collected
inputs and documented calculations do. Do not expand collection scope merely
to enable a metric without the owner's agreement.
