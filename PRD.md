# TeamStats — Product Requirements

Status: working draft; implementation has not been authorized.
Last updated: 2026-10-08.

## Purpose and users

Create an app for a high school basketball team so managers can enter collected
data after games and players can easily view their box scores and advanced stats.
Also provide a shared playbook where coaches draw and save plays, team members
view plays in motion, and approved practice videos are linked to the relevant plays.
Plan for approximately 100 potential users, including coaches and players.

## Confirmed decisions

- Build a native app in Swift using SwiftUI and Xcode.
- Use Supabase as the shared backend.
- All statistical entry happens after games; playbook authoring is independent
  of the after-game entry schedule.
- Phase 1: manual entry.
- Phase 2: photo extraction that autofills an editable entry form.
- Upload recorded data to a spreadsheet.
- Collected fields are specified below; definitions and input examples still
  require owner clarification. Do not add collection fields without agreement.
- Live tracking is excluded entirely, including from future phases.
- A dynamic playbook and approved practice videos are required components;
  their position relative to the statistics phases remains to be decided.

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

- One combined game possession total, not separate home/away totals.
- Individual possession records for both home and away teams, containing:
  - Number of paint touches.
  - Number of offensive rebounds.
  - Shot types taken: two-pointer, three-pointer, and/or free throws.
  - Made/missed shot results within the possession.
  - Whether the possession resulted in a turnover.

Possession records are entered after games. They do not authorize live tracking.
The owner has not specified counts per shot type, shot order, player attribution
within possessions, or whether points per possession are recorded explicitly.
Do not treat those as collected data or infer them from separate game totals.
Opponent player box scores and opponent player paint-touch totals have not been
requested; the confirmed opponent data is possession-level team data.

### Confirmed definitions and custom metric

- Paint touch: a player with the ball intentionally establishes two feet in
  the paint. Preserve this team definition in labels and calculations.
- An offensive rebound continues the same possession. Track its tally within
  that possession rather than automatically starting a new possession.
- Real Possessions is the owner's custom metric:
  `game possessions + offensive rebounds - turnovers`.
  Preserve its name and formula; do not substitute a different possession
  estimate. The game possession count is combined across teams; the team scope
  of offensive rebounds and turnovers still needs confirmation.
  Real Possessions is a derived metric, not a change to possession boundaries.

### Definitions to resolve

- TODO_FIELD_DEFINITIONS: counting conventions, required/optional fields, whether
  rebounds means total rebounds, and handling missing values versus recorded zero.
- TODO_PAINT_TOUCH_COUNTING: whether repeated qualifying touches by the same
  player count separately, and whether possession touches identify players.
- TODO_POSSESSION_BOUNDARIES: remaining start/end conventions, including
  free throws and period endings; offensive-rebound continuation is settled.
- TODO_POSSESSION_TOTAL_SOURCE: entered combined total versus total computed
  from complete home/away possession records.
- TODO_REAL_POSSESSIONS_SCOPE: whether offensive rebounds and turnovers in the
  formula are combined across both teams or limited to our team.
- TODO_POSSESSION_SHOT_DETAIL: made/missed tallies by shot type versus individual
  attempts; whether attempts are recorded in order. Shot outcomes are confirmed.
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

Real Possessions is a confirmed requested metric, with its aggregation scope
pending clarification; the candidates above remain proposed.

Definitions and denominator rules must be agreed before implementing metrics.
Possession records need sufficient completeness for possession-based comparisons.
Patterns involving paint touches can support hypotheses; they do not by themselves
establish that paint touches caused a particular outcome.
Player-level possession effectiveness requires player attribution that has not
been confirmed. Scoring efficiency by possession category can use the confirmed
shot outcomes once their representation and completeness are clarified; game
totals alone cannot supply possession-specific outcomes.

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

## Required component — Dynamic playbook and practice videos

Confirmed scope:

- Coaches can draw plays within the app and save them to the team's playbook.
- Team members can view saved plays with dynamic playback so they can see the
  play in action, not just a static drawing.
- Plays should be clear, readable, and attractively presented.
- Practice videos can be uploaded, linked to the corresponding plays, and made
  available to team viewers only after approval.
- This component serves coaches and players; it is not live game tracking.

Proposed simplest implementation for discussion:

- A court editor with player/ball markers and movement paths, authored as steps.
- Animate those saved steps for playback, with pause, replay, and step navigation.
- Display approved practice clips alongside each saved play.
- Store editable play instructions/geometry so changes do not require redrawing
  a flattened image. Do not assume automatic animation from arbitrary sketches
  or automatic motion extraction from videos.

Open decisions:

- TODO_PLAYBOOK_PRIORITY: placement before/after photo autofill and first-release scope.
- TODO_PLAY_AUTHORING: required drawing tools, movement/pass representation,
  animation authoring method, and playback controls.
- TODO_PLAY_PERMISSIONS: who can create, edit, publish, and view plays.
- TODO_VIDEO_APPROVAL: permitted uploaders, approving roles, and pending/rejected
  visibility; unapproved videos must not be accessible to ordinary team viewers.
- TODO_VIDEO_LIMITS: file types, size/duration, storage budget, and upload behavior.
- TODO_PLAY_VIDEO_LIFECYCLE: edits, replacements, removal, and whether approval
  must be repeated after changes.

Proposed acceptance criteria, pending owner confirmation:

- A coach can draw, save, reopen, and edit a real team play.
- An authorized viewer can play the movement animation and read the court diagram.
- A practice video remains restricted until an authorized approver publishes it.
- Approved clips play within the corresponding play's view.
- Unauthorized users cannot edit plays, approve clips, or retrieve restricted media.

## Security direction

Use the Supabase publishable key in the app; keep privileged Supabase keys,
AI credentials, and spreadsheet secrets on trusted server infrastructure.
Enforce team and role access through database policies, including RLS on exposed
tables, and protect role/approval fields from user tampering. Protect uploaded
images and practice videos through storage policies. Video approval must be
enforced by backend access controls, not only hidden in the interface.

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
