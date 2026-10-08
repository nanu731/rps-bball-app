# TeamStats — Product Requirements

Status: working draft; implementation has not been authorized.
Last updated: 2026-10-08.

## Purpose and users

Create an app for a high school basketball team so managers can enter collected
data after games and players can easily view their box scores and advanced stats.
Also provide a shared playbook where coaches draw and save plays, team members
view plays in motion, and practice videos are linked to the relevant plays under
owner-controlled upload permissions.
Plan for approximately 100 potential users, including coaches and players.

## Confirmed decisions

- Build a native app in Swift using SwiftUI and Xcode.
- Support both iPhone and iPad. Android and browser interfaces are not part of
  the confirmed device scope.
- Use Supabase as the shared backend.
- All statistical entry happens after games; playbook authoring is independent
  of the after-game entry schedule.
- Phase 1: manual entry.
- Phase 2: photo extraction that autofills an editable entry form.
- Supabase holds the official stats; automatically export published data and
  accepted corrections to Google Sheets. Spreadsheet edits do not update the app.
- The initial pilot focuses on after-game manual stats. Photo autofill, animated
  plays, and practice videos remain required later components, not pilot blockers.
- Offline entry is low priority. Start with online submission and do not build
  offline synchronization for the initial pilot unless a demonstrated need arises.
- Collected fields are specified below; definitions and input examples still
  require owner clarification. Do not add collection fields without agreement.
- Live tracking is excluded entirely, including from future phases.
- A dynamic playbook and permission-controlled practice videos are required components;
  their position relative to the statistics phases remains to be decided.
- Account signup supports both email and phone number as available methods.
  Do not require every user to provide both identifiers unless later requested.
- The app owner grants unrestricted practice-video upload permission to selected
  accounts. Those accounts do not require case-by-case owner approval to upload.
  Other accounts can upload pending videos for owner review; those videos are
  not available to team viewers until the owner approves them.
- Any app user may enter, propose edits to, and submit stats for publication,
  subject to case-by-case owner approval. The owner may authorize selected
  accounts to do so without case-by-case approval.
- Owner-managed authorization also applies to submitting/publishing plays and
  practice videos. Specific permission controls for each content type must be
  defined; an account must not be able to authorize itself.
- Supplied PDF forms are layout/shorthand references, not authority to expand
  collection scope. The owner's explicit field list and exclusions take priority.
- All printed player names and jersey numbers in those PDFs are arbitrary.
  The owner will provide the actual roster later; use TODO_TEAM_ROSTER until then.

## Reviewed input references

Reviewed both one-page PDFs visually and through text extraction on 2026-10-08:

- Advanced sheet: `/Users/narayanlekhi/Library/Messages/Attachments/36/06/54D45273-0649-483A-A926-38B60C9B299B/rpsadvstatsdraft.pdf`.
- Box-score sheet: `/Users/narayanlekhi/Downloads/boxscorestatsheet.pdf`.

These are blank templates, not completed game records or verified sample data.
Do not seed player profiles, jersey numbers, school branding, or game statistics
from them. Their legends describe the source notation, not app instructions.
These local reference paths may need replacement if files move; this summary
preserves the relevant layout context without requiring the templates to be copied.

Advanced-sheet layout:

- A separate player paint-touch tally section and a possession log.
- Each numbered log row pairs our-team and opponent columns: paint touches,
  offensive rebounds, and shot/turnover shorthand.
- Two printed row blocks numbered 1–20 and 21–40; this is a page layout, not a
  maximum number of possessions the app may store.
- Our-team/opponent columns must map to the correct home/away identities for
  each game; do not assume our team is always the home team.
- The source header includes a half label; whether page/half grouping is needed
  for entry or later photo import remains open. Do not add a period stat by default.
- Circled two/three shot symbols denote makes. Plain and underlined shot symbols
  also carry shot-style meaning on the source; ignore that style distinction.
- `FT0`, `FT1`, `FT2`, and `FT3` describe free throws made, not an explicit tally
  of attempts or misses in the currently reviewed PDF. The owner will revise the
  sheet to use `FTmade/attempted`, such as `FT1/1`, `FT1/2`, and `FT2/2`.
  This new notation is confirmed, but the revised PDF has not yet been reviewed.
  Do not infer misses from the old makes-only notation.
- `TO` denotes a turnover; use the confirmed possession turnover field.

Box-score layout:

- One row per printed player with a shots cell and counting-stat columns.
- Offensive and defensive rebounds appear separately; the owner confirmed both
  as app input fields. Calculate total rebounds as their sum.
- The shots column does not explain its notation. Obtain a marked example before
  specifying photo parsing. Keep the confirmed made/missed fields in manual entry.
- The source has no separate points column; points remain a requested app field.
- The source column labeled Charges maps to the requested charges drawn field.

Excluded source-only fields:

- 50/50 balls, after-timeout (ATO) flags, transition/fast-break flags.
- Off-the-dribble versus catch-and-shoot classifications and quarter-end flags.
- Quarter/overtime score checkpoints and timeout tracking.
- Any other statistical field not in the owner's confirmed collection list.

Roster names/numbers are unresolved owner content, not optional sample data.
Game-identification metadata must be agreed separately from statistical fields.

## Phase 1 — After-game manual entry

Managers enter the owner's specified data through an easy-to-use interface.
Players can view the agreed box scores and statistical summaries.

### Stats approval and pilot scope

All app users can contribute after-game stats and corrections. Ordinary users'
submissions require owner approval before becoming published data. Selected
owner-authorized users can enter, edit, and publish without individual approval.
Owner review must apply to edits of existing records as well as new submissions.

Proposed implementation behavior: preserve the currently published version while
a correction awaits review; only accepted changes affect player statistics and
the spreadsheet export. Keep the author's identity and approval state attached
to each submission. These details require confirmation before implementation.

The first pilot exercises manual box-score/possession entry, account access,
owner review and permission grants, and published-stat viewing on iPhone/iPad.
The exact pilot metric list and Google Sheets inclusion remain to be finalized.
Do not include photo extraction, play animation, or video upload in that pilot.
Online submission is the starting approach; show failures clearly without
claiming that unsent changes have reached the shared database. Local draft
recovery can be considered separately; offline sync is not a pilot requirement.

### Confirmed collected data

**Player box-score game totals:**

- Points.
- Offensive rebounds.
- Defensive rebounds.
- Total rebounds, calculated as offensive rebounds + defensive rebounds.
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

- Possession counts attributable to each team are needed for each team's Real
  Possessions. The latest clarification supersedes the earlier combined-only
  interpretation; the entry/derivation method for team counts remains open.
- Individual possession records for both home and away teams, containing:
  - Number of paint touches.
  - Number of offensive rebounds.
  - Separate made/missed tallies for two-pointers, three-pointers, and free throws.
  - Whether the possession resulted in a turnover.

Possession records are entered after games. They do not authorize live tracking.
Shot data uses tallies by type and outcome, not ordered individual attempts.
The owner has not specified player attribution within possessions or whether
points per possession are recorded explicitly.
Do not treat those as collected data or infer them from separate game totals.
Opponent player box scores and opponent player paint-touch totals have not been
requested; the confirmed opponent data is possession-level team data.

### Confirmed definitions and custom metric

- Paint touch: a player with the ball intentionally establishes two feet in
  the paint. Preserve this team definition in labels and calculations.
- An offensive rebound continues the same possession. Track its tally within
  that possession rather than automatically starting a new possession.
- Revised possession free-throw notation is `FTmade/attempted`: the numerator is
  free throws made and the denominator is free throws attempted, not a percentage.
  Free throws missed = attempted - made. For example, `FT1/2` means one made,
  two attempted, and one missed. Sum counts across entries rather than averaging
  the fractions. This supplies the same made/missed counts used by manual entry.
  Propose validation of nonnegative whole-number counts with made <= attempted;
  flag invalid or unreadable entries instead of silently correcting them.
- Real Possessions is the owner's custom metric:
  `that team's game possessions - that team's turnovers + that team's offensive rebounds`.
  Preserve its name and formula; do not substitute a different possession
  estimate. Calculate home and away Real Possessions separately using only the
  respective team's inputs, never the combined game total as each team's base.
  Real Possessions is a derived metric, not a change to possession boundaries.

### Definitions to resolve

- TODO_FIELD_DEFINITIONS: remaining counting conventions, required/optional
  fields, and handling missing values versus recorded zero. Separate offensive
  and defensive rebounds are confirmed.
- TODO_TEAM_ROSTER: actual player names and jersey numbers from the owner.
- TODO_SOURCE_NOTATION: a marked example of box-score shot notation.
- TODO_REVISED_ADVANCED_SHEET: obtain and review the owner's updated PDF with
  `FTmade/attempted` notation; the existing PDF still uses makes-only notation.
- TODO_SOURCE_PAGE_MAPPING: whether paired row numbers represent each team's
  own nth possession, and how multiple pages/halves map into a full game.
- TODO_PAINT_TOUCH_COUNTING: whether repeated qualifying touches by the same
  player count separately, and whether possession touches identify players.
- TODO_POSSESSION_BOUNDARIES: remaining start/end conventions, including
  free throws and period endings; offensive-rebound continuation is settled.
- TODO_POSSESSION_TOTAL_SOURCE: whether team counts are entered or derived from
  complete possession records, and whether a combined total is also displayed.
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

Real Possessions is a confirmed requested metric calculated separately for each
team; the candidates above remain proposed.

Definitions and denominator rules must be agreed before implementing metrics.
Possession records need sufficient completeness for possession-based comparisons.
Patterns involving paint touches can support hypotheses; they do not by themselves
establish that paint touches caused a particular outcome.
Player-level possession effectiveness requires player attribution that has not
been confirmed. Scoring efficiency by possession category can use the confirmed
made/missed tallies once data completeness is established; game
totals alone cannot supply possession-specific outcomes.

Requirements to finalize before implementation:

- TODO_COMPLETED_INPUT_EXAMPLES: blank templates reviewed; obtain marked entries
  to verify tally/shot notation and completeness before photo extraction.
- TODO_MANUAL_ENTRY_FLOW: entry order, game identification, and correction behavior.
- TODO_ADVANCED_STATS: desired metrics and formulas supported by collected inputs.
- TODO_STATS_REVIEW_DETAILS: review interface, rejection/resubmission, and pending
  correction behavior. Owner approval and selected-user bypass are confirmed.
- TODO_PERMISSION_GRANULARITY: separate owner grants for stats, plays, and videos
  versus one shared trusted-contributor permission.
- TODO_PLAYER_VISIBILITY: own stats, all team stats, or another access policy.
- TODO_SHEETS_EXPORT: spreadsheet destination, row/tab layout, export timing,
  and handling failures. Supabase is authoritative; export is one-way.
- TODO_DRAFT_RECOVERY: minimum protection for unsent form edits; offline entry
  and synchronization are low priority and excluded from the initial pilot.
- TODO_ACCOUNT_ENROLLMENT: team invitations and baseline access after signup.
- TODO_AUTH_FLOW: verification, recovery, and linking email/phone methods to the
  same account when applicable. Both signup methods are confirmed.
- TODO_DEVICE_TEST_MATRIX: supported iOS/iPadOS versions and representative
  iPhone/iPad screen sizes. Both device families are confirmed.

Proposed acceptance criteria, pending owner confirmation:

- An app user can enter and submit an actual after-game record or correction.
- Ordinary-user submissions require owner approval; authorized users can publish
  without case-by-case review. Users cannot approve their own pending submissions
  unless granted the appropriate authority by the owner.
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
- Practice videos can be uploaded and linked to corresponding plays.
- The app owner controls which accounts may upload without individual approval.
  Authorized uploaders do not need owner permission for each video upload.
- Users without that permission can upload pending clips for owner review.
  Pending clips are not available to ordinary team viewers until the owner
  approves them. Do not impose case-by-case review on authorized uploaders.
- The app owner grants upload permissions and approves pending videos.
- This component serves coaches and players; it is not live game tracking.

Proposed simplest implementation for discussion:

- A court editor with player/ball markers and movement paths, authored as steps.
- Animate those saved steps for playback, with pause, replay, and step navigation.
- Display practice clips alongside each saved play under the agreed visibility rules.
- Store editable play instructions/geometry so changes do not require redrawing
  a flattened image. Do not assume automatic animation from arbitrary sketches
  or automatic motion extraction from videos.

Open decisions:

- TODO_PLAYBOOK_PRIORITY: later placement relative to photo autofill; the manual
  stats pilot comes first and excludes the playbook and practice videos.
- TODO_PLAY_AUTHORING: required drawing tools, movement/pass representation,
  animation authoring method, and playback controls.
- TODO_PLAY_REVIEW_DETAILS: owner approval workflow for ordinary contributors,
  edit rights and viewing rules. Selected users may be authorized to submit plays
  without case-by-case approval; coach drawing remains required.
- TODO_VIDEO_REVIEW_DETAILS: owner review interface, rejection/resubmission
  behavior, and pending-video access for the uploader. Owner approval before
  team viewing is confirmed for users without unrestricted upload permission.
- TODO_VIDEO_LIMITS: file types, size/duration, storage budget, and upload behavior.
- TODO_PLAY_VIDEO_LIFECYCLE: edits, replacements, removal, and whether approval
  must be repeated after changes.

Proposed acceptance criteria, pending owner confirmation:

- A coach can draw, save, reopen, and edit a real team play.
- An authorized viewer can play the movement animation and read the court diagram.
- An owner-authorized uploader can upload without a separate owner approval step.
- An account without unrestricted upload permission can submit a pending clip
  but cannot publish it or access another user's restricted pending media.
- Only the owner can approve a pending clip for team viewing or grant unrestricted
  upload permission. Approval makes that clip available in its linked play.
- Clips permitted for team viewing play within the corresponding play's view.
- Unauthorized users cannot edit plays, approve clips, or retrieve restricted media.

## Security direction

Use the Supabase publishable key in the app; keep privileged Supabase keys,
AI credentials, and spreadsheet secrets on trusted server infrastructure.
Enforce team and role access through database policies, including RLS on exposed
tables, and protect role/approval fields from user tampering. Protect uploaded
images and practice videos through storage policies. Owner-granted upload
permissions and any required approval must be enforced by backend access
controls, not only hidden in the interface. Store grants against authenticated
account IDs, not editable email/phone strings, and do not let users grant
themselves upload permission. Owner-only permission management is required.

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
- TODO_PILOT_DETAIL: metrics included, pilot participants, and whether Google
  Sheets export is required in the first pilot or the next iteration.

Backend choice does not determine which advanced stats are possible: collected
inputs and documented calculations do. Do not expand collection scope merely
to enable a metric without the owner's agreement.
