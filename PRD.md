# TeamStats — Product Requirements

Status: working requirements; current implementation and verification evidence
are recorded in PROJECT_CONTEXT.md and WORKFLOW.md. End-to-end authorization
below supersedes older bounded-step stopping rules; open provider gates remain.
Last updated: 2026-10-17.

## Purpose and users

Create an app for a high school basketball team so managers can enter collected
data after games and players can easily view their box scores and advanced stats.
An optional iPad-first shot recorder also collects in-game field goals and free
throws under the narrow owner scope amendment below.
Also provide a shared playbook where coaches draw and save plays, team members
view plays in motion, and practice videos are linked to the relevant plays under
owner-controlled upload permissions.
Provide a Game Film menu with game-linked Hudl shortcuts; full-game video files
remain on Hudl. Practice clips linked to plays are uploaded and viewed in TeamStats.
Plan for approximately 25 regular users (about 10 players and 15 staff), with
additional initial testers whose number and media usage remain unspecified.

## Value, pain, and intended audience

- Value: one accessible team app for entering, checking, reviewing, and viewing
  after-game statistics, with plays and corresponding videos added later.
- Pain addressed: the owner collects paper-form data and needs an easier input
  and player-viewing workflow, including detection of inconsistent scoring data.
  No measured time savings or unsupported claims about current usage are asserted.
- Intended audience (ICP): this high-school basketball team, approximately 25
  regular users plus initial testers. Managers/coaches contribute; players view; the owner manages
  approvals and grants. This is not a general commercial customer acquisition plan.

## Confirmed decisions

- Build a native app in Swift using SwiftUI and Xcode.
- Support both iPhone and iPad. Android and browser interfaces are not part of
  the confirmed device scope.
- Minimum supported iOS/iPadOS is 26.0, including subsequent 26.x releases.
- Game metadata: date, opponent, our team's home/away status, and game type
  (regular season or playoff). Scrimmages are outside the requested scope.
- Use Supabase as the shared backend.
- Box-score, possession-sheet and player paint-touch entry remain after games.
  The shot-recorder amendment below is the only authorized in-game exception;
  playbook authoring is independent of the after-game entry schedule.
- Phase 1: manual entry.
- Phase 2: photo extraction that autofills an editable entry form.
- Supabase holds the official stats; automatically export published data and
  accepted corrections to Google Sheets. Spreadsheet edits do not update the app.
- The initial pilot focuses on after-game manual stats. Photo autofill, animated
  plays, practice videos, and game film remain required later components, not pilot blockers.
- Offline entry is low priority. Start with online submission and do not build
  offline synchronization for the initial pilot unless a demonstrated need arises.
- Collected fields are specified below; definitions and input examples still
  require owner clarification. Do not add collection fields without agreement.
- In-game collection is limited to the optional shot recorder below. Live game
  clocks, possession tracking, substitutions and lineup tracking remain excluded.
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
- Game Film provides optional Hudl links associated with games; full-game files
  stay on Hudl. Practice clips linked to plays are the required in-app video
  upload/playback scope. Preserve separate eligibility, publication bypass and
  owner review for submitted link metadata; do not upload full-game files.
- Supplied PDF forms are layout/shorthand references, not authority to expand
  collection scope. The owner's explicit field list and exclusions take priority.
- All printed player names and jersey numbers in those PDFs are arbitrary.
  The owner will provide a fixed actual roster after tryouts. Temporary arbitrary
  names and numbers are now explicitly authorized for development. Label the
  temporary roster visibly and keep it replaceable; do not treat it as real data.
  Latest owner instruction requires roster management: add/edit/archive players,
  preserving historical stats and stable identities. Temporary identities must
  not silently become actual players.

### Owner administration and delegated completion workflow (2026-10-11)

The owner now authorizes an end-to-end Matt Pocock engineering workflow with
LLM Council choosing unresolved product/technical defaults within explicit scope.
This replaces the one-bounded-feature stopping rule for the forthcoming completion
prompt; existing requirements, verified data and security boundaries still apply.
Council must not invent actual roster/branding, credentials, budgets or results.

Provide an owner administration UI to grant/revoke capabilities, manage the
roster, and delegate selected authorization administration to other members.
Delegation must be bounded and revocable, server-enforced and auditable; delegated
admins cannot expand their own authority or remove/replace the owner. Choose
the detailed capability model through Council and record the decision before coding.
Archive roster entries without erasing historical statistics. Actual destructive
deletion remains subject to the owner's existing approval preference.
Additional collection fields outside the owner-approved shot-recorder amendment,
or expansion into web/Android, remain unauthorized. Council cannot broaden scope.

### Pilot, delivery target and contact amendment — 2026-10-17

The owner approves a shared-manual-statistics first pilot while automatic Google
Sheets and media integrations remain unfinished. This is scope approval, not
deployment/distribution or release acceptance. Later agreed features remain
required; the owner targets 2026-11-17, subject to verified provider/device gates.
The new shot recorder must be planned explicitly against that target, without
silently delaying or redefining the pilot. Pilot participants, distribution and
final acceptance criteria remain open.

Owner-selected support/security/deletion-request contact:
happybuddha1008@gmail.com. This authorizes the contact route, not automatic email
transmission, a response-time promise, deletion execution or retention policy.

The owner allocates at most 10 GB of existing Google storage to private encrypted
backups, leaving personal headroom. The cap covers retained backup generations,
not app/media hosting or additional purchased storage. Backup encryption, access
holder, retention, transfer feasibility and actual hosted recovery remain to be
verified. No real-data upload or automatic old-backup deletion is authorized here.

### In-game shot recorder amendment — 2026-10-17

Status: owner-authorized product scope; not implemented or accepted yet. Keep this
inside TeamStats, with iPad-first capture and charts accessible to authorized team
viewers on iPhone/iPad. This supersedes blanket historical no-live-tracking rules
only for the following field-goal/free-throw workflow. Reuse existing game/roster
identities and owner-controlled authority; a standalone second app is not planned.

**Collection workflow**

- One designated manager records both teams for a game. Make the active team,
  our selected player, court orientation and pending action unmistakable.
- Our field goal: select an existing player, tap the court location, explicitly
  distinguish two versus three points and record Make or Miss. Keep the flow fast;
  any geometry suggestion remains correctable, especially near the arc.
- Opponent field goal: choose Opposing team, tap location, distinguish two/three
  points and record Make/Miss. Opponent player attribution/roster is not required.
- Free throws use a separate button beside the court. Choose our player or the
  opposing team, enter attempts (quick 1/2/3 and another positive count), then mark
  each attempt Make/Miss. Mixed outcomes must work; two attempts Make then Miss
  are FT1/2. Pending unanswered attempts remain pending, not silently missed.
- A made field goal contributes its confirmed 2/3 value; a made free throw adds 1.
  Free throws appear in a separate tally, not fabricated court-location dots.
- Provide immediate confirmation, Undo and correction of wrong player/team,
  location, shot value, result or free-throw entry. Retain correction provenance
  for shared records; do not silently erase accepted history.
- Court coordinates/orientation must survive resizing and rotation. Locations
  are manager observations, not precise camera measurements. Do not infer a game
  clock, possession ID or official chronology from an entry timestamp.

**Reliability and authority**

- Persist captured/pending events through app interruptions without requiring
  game-venue connectivity. This narrowly authorizes local shot capture and
  controlled later submission, not general offline shared-stat synchronization.
- Use stable event/session identities, explicit pending/confirmed/error states,
  replay-safe submission and current server authorization. Local capture is not
  proof of permission to upload/publish after a grant/session changes.
- One designated recorder and an explicit handoff prevent overlapping work.
  Stable IDs prevent retransmission duplicates, not two people independently
  recording the same attempt; overlapping sessions need visible review.
- Model permissions and review using existing server-enforced patterns. Ordinary
  players do not gain recording, approval or permission-administration rights.
  Authorized recording does not imply unrestricted publication or delegation.

**Reconciliation, coverage and charts**

- Store shots separately from after-game box scores, possession tallies and paint
  totals. Link by team/game/player identities. Compare totals, never add separate
  datasets together or manufacture shots/locations to force agreement.
- Independently per team, recorded points = 2 × made twos + 3 × made threes + made free
  throws. Compare against an independently confirmed official score; absent
  official data is Unavailable, not zero or a passed check.
- The owner wants matching points to inform complete coverage and discrepancies
  shown otherwise. Score agreement alone cannot establish attempted-shot coverage:
  unrecorded misses leave points unchanged. Keep Score reconciled and Coverage
  complete separate. Owner-confirmed policy (2026-10-17): the designated manager
  explicitly confirms that every field-goal and free-throw attempt was recorded,
  followed by approval from the owner or an authorized statistics reviewer.
  Manager confirmation alone is awaiting review, not Coverage complete. Record
  confirmation and approval against the reviewed capture version; later edits
  require renewed confirmation and review. Keep available made/attempted-total
  comparisons visible; approval does not independently prove every attempt or
  location was recorded. This policy is approved; implementation and acceptance
  remain separate.
- Compare player/team 2PT/3PT/FT makes and attempts against available official
  after-game inputs; identify missing, matching and discrepant values. Preserve
  both sources and correction/review history. Partial capture remains useful.
- Show team/player recorded-shot maps, attempts, makes/misses and conversion by
  supported zones, with sample counts and coverage/review status. Opponent charts
  show shot origin, attempts and points allowed without invented player identities.
  Matching totals do not prove every location correct. Do not infer defender
  distance, shot quality, possession efficiency or missing attempts.

Build synthetic courtside workflow/model/permission/recovery checks first, then
inspect the native prototype and test interruption/Undo/FT1/2/multiple teams.
Record actual iPad interaction/rotation/accessibility separately from model proof.
Unknown free hosting or unavailable real-game examples remain gates; synthetic
success is not real-game accuracy or release approval.

## Visual direction

### Human-use polish reference (2026-10-11)

Owner-requested reference: Lincoln Devine,
[11 tells that your app was vibe coded](https://lincolndevine.com/guides/polish/).
Read successfully in browser; do not commit its token-bearing access URL or copy
the article/prompts into the repository. Use the following as an audit rubric,
not evidence these behaviors already pass:

1. Immediate feedback for pending saves; safe rollback on failure.
2. Distinct loading states without misleading blank screens.
3. Consider safe cached viewing for returning users.
4. Native pressed/disabled feedback and comfortable touch targets.
5. Connection failures preserve recoverable input.
6. Empty screens explain the next permitted action.
7. Duplicate taps/retries must not create duplicate operations.
8. Plain-language errors with a recovery action.
9. Keyboard-safe fields and Save controls.
10. Consistent readable light/dark appearance.
11. Navigation/backgrounding must not silently discard drafts.

Apply to native SwiftUI and the actual membership/review workflow. Pending
membership is different from an empty roster; show the appropriate next step.
Never optimistically assert a permission grant, completed sheet, approved edit,
published statistic or accepted video before server confirmation. Any cache or
draft recovery must be account/team scoped, protected and cleared/inaccessible
after sign-out, account change or revoked access. Credentials are not form drafts;
keep raw sensitive diagnostics out of logs. Bound retries and use server-enforced
idempotency/revision checks where applicable. Do not automatically replay privileged
actions after reconnection. Existing offline-sync deferral still applies.

Audit existing flows first, fix demonstrated gaps in coherent slices, and record
physical-device/slow-network/low-power tests separately from simulator evidence.
Do not add decorative loading effects or blanket parallel screen rewrites.

### Lightweight brand and UI standards

Working product name: TeamStats. Primary maroon is confirmed for this Rutgers Prep
team app; official school hex remains unknown. DESIGN_SYSTEM.md records a
provisional accessible light/dark palette. Logo: `TODO_TEAM_LOGO`; final icon:
`TODO_APP_ICON`. Actual roster: `TODO_TEAM_ROSTER`. Use factual, short
labels tied to basketball tasks; never invent school identity or outcomes.
Use DESIGN_SYSTEM.md for actual native rules; never present provisional colors as official specifications.

Use system text styles with Dynamic Type, semantic foreground/background colors,
and clear light/dark contrast. Prefer native navigation, forms, lists, buttons,
pickers, alerts, and counters. Target at least 44-point interactive areas.
Use a consistent spacing rhythm (8/16/24 points where appropriate), adapting
for accessibility rather than forcing fixed dimensions. Numeric displays may
use monospaced digits. Error text must have a textual/icon cue, not color alone.
Reserve error red for invalid input and failed operations with text/icons. Saveable scoring discrepancies use a calm informational notice; use the confirmed maroon accent through documented semantic tokens.
Use native scrolling, keyboard-safe Save, and accessibility labels identifying
player/team/field. These are forward standards, not authorization for a broad
refactor. The owner-approved consolidated scoring warning is a reusable pattern.

Owner-requested design reference: apply
[apple-design](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md)
to this native SwiftUI app. Translate its interaction, typography, feedback,
and accessibility principles to platform controls; do not introduce its web
libraries or glass effects that conflict with the owner's explicit exclusions.

Use a restrained native SwiftUI interface with system typography, readable
contrast, consistent spacing, clear tables/forms, and purposeful system icons.
The owner explicitly rejects purple-to-blue gradients, gradient hero text,
emojis in headings, ubiquitous Inter or Lucide icons, colored-border cards,
glassmorphism cards, low-contrast dark mode, badges above headlines, untouched
shadcn UI, scroll fade-ins, cursor-following beams, buttons fading on hover,
inconsistent spacing, excessive em dashes, generic buzzword copy, serif italic
accents, Space Grotesk paired with Instrument Serif, and grain over gradients.
Apply this direction to future work; do not start a separate redesign without
an assigned task. Maroon is confirmed; official hex, logo and final icon remain owner-provided.

## Reviewed input references

Reviewed both one-page PDFs visually and through text extraction on 2026-10-08:

- Advanced sheet: `/Users/narayanlekhi/Library/Messages/Attachments/36/06/54D45273-0649-483A-A926-38B60C9B299B/rpsadvstatsdraft.pdf`.
- Box-score sheet: `/Users/narayanlekhi/Downloads/boxscorestatsheet.pdf`.
- Unchanged workspace copy for other local chats: `boxscorestatsheet.pdf`.
- Revised workspace forms: `rpsadvstatsdraft-revised.pdf` and
  `boxscorestatsheet-revised.pdf`, with regular-season/playoff and our-team
  home/away checkboxes added. Their page layouts were rendered and checked.

These are blank templates, not completed game records or verified sample data.
Do not treat their printed players as the actual roster, or seed real school
branding or game statistics from them. Temporary roster content is separately
authorized for development. Their legends describe notation, not app instructions.
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
  This notation has been included and visually checked in the revised draft.
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

Actual roster names/numbers remain unresolved owner content. Temporary arbitrary
roster names/numbers are explicitly permitted. Game metadata is now confirmed
as date, opponent, home/away, and regular-season/playoff.

## Phase 1 — After-game manual entry

Managers enter the owner's specified data through an easy-to-use interface.
Players can view the agreed box scores and statistical summaries.

### Stats approval and pilot scope

Confirmed manual box-score behavior:

- Offer both single-player entry and whole-roster table entry for a selected game.
  Both modes edit the same records; switching modes must not duplicate or lose data.
- Empty numeric fields mean not entered. Zero must be entered explicitly.
  Preserve this distinction in storage, displays, and calculations.
- Points must agree with shot makes. Keep the entered value visible and flag
  discrepancies with `2 * two-point makes + 3 * three-point makes + FT makes`;
  never silently overwrite source values or treat missing inputs as zero.
- For incomplete made-shot inputs, sum only valid entered makes as a scoring
  lower bound. If that bound exceeds entered points, warn immediately with
  “Points disagree: entered 4; entered made shots imply at least 21.” for points
  4 / three-point makes 7 / other makes blank. Blanks remain unentered in storage.
  Without a proven contradiction show “Check incomplete”, never a match.
- With points and all three made-shot categories entered, compare exact equality.
  Missing points, invalid scoring inputs and arithmetic overflow must give honest
  incomplete/unavailable states. Misses contribute no points and are not required.
  Share the check across individual entry, roster table and summary. In entry,
  use one restrained “Check scoring” notice near the top, above mode controls.
  Use a small informational icon, readable native typography and restrained semantic
  color, without a red alert block, modal or acknowledgment. Briefly explain that
  entered points and made baskets differ. Show selected-player discrepancies in
  individual mode and all affected players in table mode; use inline disclosure for
  multiple-player details. Preserve exact mismatch versus partial lower-bound detail.
  Update/remove feedback immediately without moving focus or repeatedly announcing
  it while typing. Discrepancies remain saveable drafts; invalid numeric input and
  save failures keep their distinct blocking/recovery behavior. Keep larger text,
  VoiceOver, fields and Save usable. This owner decision (2026-10-15) supersedes the
  prominent red-warning heading requirement; validation/completion rules do not change.
- Approved first native visual slice: game-details matchup/score context, read-only
  compact box score with expandable player details and explicit Edit, and connected
  individual/table entry. Use the approved maroon sports-ledger hierarchy; no web
  embedding or unrelated Account/administration/playbook/media/scouting redesign.
  Missing scores never appear as zero; incomplete aggregates identify entered inputs.
- Hide the horizontal scroll indicator in overflowing box-score tables using supported
  native SwiftUI controls. Preserve horizontal swiping, vertical access, player/column
  context, keyboard/accessibility navigation and larger text. A partial next column
  or quiet static hint may reveal overflow; no replacement progress track or animation.
- Game-total box-score points must agree with the corresponding team's total
  points derived from made shots on the advanced possession sheet. Perform that
  comparison only when the required matching datasets are available/complete.
  Until possession entry exists, show that the cross-sheet check is unavailable,
  rather than claiming it passed or flagging absent data as a discrepancy.
- Local drafts may be incomplete. Completion/publishing rules remain to be
  finalized before backend approval is implemented.

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
The exact pilot metric list remains open. The owner permits automatic Google
Sheets and media delivery to follow the first pilot; both remain later requirements.
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

Latest possession-input clarification (supersedes unanswered-turnover defaults):
- Numeric fields may stay blank; do not require tedious zero entry to save drafts.
  Blank remains unentered while drafting. At possession-sheet completion, blank
  numeric fields mean no events and are explicitly saved as zero after the
  confirmation flow below. This does not change box-score blank semantics.
- New possession records default turnover to No. Preserve historical stored
  unanswered turnover values; do not rewrite existing data merely on opening it.
- Provide accessible +1/-1 controls for every possession count alongside direct
  numeric entry. From blank, + starts at 1; minus is disabled for blank/zero;
  zero stays explicit. Clearing the field restores blank. Reject invalid/overflow
  arithmetic, and do not silently correct invalid typed input.
- Owner manual verification found vertical rows scroll but paired columns cannot
  be swiped on either device. Investigate/fix horizontal access where content
  overflows; no horizontal movement is needed when both columns genuinely fit.
  iPad keyboard-visible save and relaunch persistence passed.

Possession-sheet completion confirmation:
- If added possession records have blank numeric fields, show a popup explaining
  that these fields will become zero. Offer Confirm and Go back. Go back leaves
  values and completion unchanged; confirmation saves zeros and completion together.
- Include “Don't show this again” as a per-user preference. Persist it only after
  confirmation. Later explicit completion actions by that user may convert blanks
  to zeros without repeating this popup. This does not bypass validation, editing
  permissions, review, or publication approval.
- Apply zero conversion only to numeric fields in existing records for the sheet
  being completed; never create possessions from empty paired placeholders.
  This does not convert historical unanswered turnover values to No.
- If validation or saving fails, do not claim completion succeeded. Draft saving
  alone never converts blanks to zeros. Secure completion and preferences follow
  authenticated-account implementation, not the current local draft task.

- Each team has its own sequence, paired left to right: our team's nth
  possession beside the opponent's nth possession. This is an entry layout,
  not a claim that both occurred simultaneously or in an exact shared order.
- Provide a reversible entry-complete checkbox for each team's possession sheet.
  Unchecked means incomplete data; returning completed data to editing requires
  a request approved by the owner or an authorized dataset-editing reviewer.
  A checked sheet is marked complete. The game remains incomplete if either
  team's sheet is unchecked. This is data-entry status, not owner approval or
  publication. Completed data must not be freely editable: approve the edit
  request before allowing changes, and revised data requires completion again.
  Preserve accepted data while requests are pending. Reviewer permission scope,
  reopen/recompletion details, and any box-score completion requirement must be
  resolved before connected implementation. Local draft entry comes first;
  do not simulate secure approval with device-local flags.

- Possession counts attributable to each team are needed for each team's Real
  Possessions. The latest clarification supersedes the earlier combined-only
  interpretation; the entry/derivation method for team counts remains open.
- Individual possession records for both home and away teams, containing:
  - Number of paint touches.
  - Number of offensive rebounds.
  - Separate made/missed tallies for two-pointers, three-pointers, and free throws.
  - Whether the possession resulted in a turnover.

Possession records are entered after games. They do not authorize live possession
tracking; the separate shot-recorder amendment does not change these boundaries.
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
- The owner's possession definition starts when a team legally has possession
  and groups actions until the opponent legally has possession. This includes
  free throws, offensive rebounds, and fouls; it does not add a foul collection
  field to possession records. Holding the ball until the period ends does not
  count as a possession when no actions occurred before the buzzer. A possession
  with actions, including shots/free throws, counts even if the opponent never
  legally possesses the ball before the period ends. Preserve this custom rule.
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

- TODO_FIELD_DEFINITIONS: remaining counting conventions and required fields
  for completion. Separate offensive/defensive rebounds and blank-versus-zero
  semantics are confirmed.
- TODO_TEAM_ROSTER: fixed actual player names/numbers after tryouts. Development
  can proceed with a visibly labeled temporary roster; this is not a blocker.
- TODO_SOURCE_NOTATION: a marked example of box-score shot notation.
- TODO_REVISED_ADVANCED_SHEET: obtain and review the owner's updated PDF with
  `FTmade/attempted` notation. A revised draft, `rpsadvstatsdraft-revised.pdf`,
  has been created and visually checked; owner confirmation is pending. It removes
  the 50/50 section and possession-modifiers legend, expands paint-touch space,
  and uses made/attempted FT notation. Other right-hand legend content is retained
  as requested, but excluded shot-style fields remain outside app scope.
- TODO_SOURCE_PAGE_MAPPING: paired row numbers represent each team's own nth
  possession, now confirmed; multiple page/half mapping still needs agreement.
- TODO_PAINT_TOUCH_COUNTING: whether repeated qualifying touches by the same
  player count separately, and whether possession touches identify players.
- Possession boundaries: legal-possession grouping and inclusion of free throws
  are confirmed. Period-ending possessions with actions count; no-action holds
  until the buzzer do not count.
- TODO_POSSESSION_TOTAL_SOURCE: whether team counts are entered or derived from
  complete possession records, and whether a combined total is also displayed.
- Use stable internal identifiers to associate games, players, and stat records;
  do not use editable display names as record identity. Game metadata is confirmed.

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
- TODO_MANUAL_ENTRY_DETAILS: entry order, completion rules, and correction review.
  Both single-player and roster-table entry are confirmed.
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
- Check entered points against 2 × two-point makes + 3 × three-point makes +
  free-throw makes; flag discrepancies rather than silently overwriting values.
- Compare game-total box-score points with matching advanced-sheet points when
  both datasets are complete. Distinguish incomplete/unavailable checks from
  actual disagreements. These consistency requirements are confirmed.
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
  The strict $0 budget still applies with 25 regular users and additional testers.
  Evaluate private Supabase Storage against actual clip sizes, retention and
  download demand before activation; no capacity or provider choice is verified
  by the smaller audience alone.
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

## Required component — Game Film

Owner decision (2026-10-12), superseding full-game file upload requirements:

- Keep full-game film on Hudl; TeamStats does not host or download those files.
- Provide optional Hudl shortcuts associated with each game's stable ID, date,
  opponent, type and home/away status. Opening a link uses the provider's supported
  web/app destination; native embedding or offline game-film access is not promised.
- Preserve existing coach/manager eligibility, owner approval for ordinary
  submissions and separately granted publication bypass for link metadata.
- TeamStats permissions protect link metadata. Hudl independently controls film
  access; TeamStats admission does not grant a Hudl account or film permission.
- This is outside the initial manual-stats pilot. No livestreaming, automatic
  video-to-stat extraction, Hudl scraping or automatic exports are authorized.
- Practice clips linked to plays remain the required in-app upload/playback
  component, with optional offline downloads, private storage and the existing
  owner-controlled review flow. Capability approval is per user, not per download.
  Already delivered copies cannot reliably be recalled after revocation; future
  remote access still checks current permissions.

Remaining verification:

- TODO_HUDL_LINK_ACCEPTANCE: test a real, authorized link on iPhone and iPad,
  including provider sign-in, unavailable links and denied provider access.
- Actual practice-clip formats, sizes, retention, storage/transfer capacity and
  offline-download behavior still require validation under the $0 budget.

Acceptance criteria:

- Eligible coaches/managers submit game-linked Hudl shortcuts without selecting
  or uploading a full-game file. Existing review and bypass rules apply.
- Authorized viewers identify the linked game and open a published shortcut;
  the interface clearly indicates that film is viewed through Hudl.
- Missing links and provider access requirements have honest guidance. Saving
  a URL is not evidence of working playback, provider rights or native integration.
- Existing game-film proposals, grants and history are retained; this scope
  decision does not authorize deleting records or weakening access controls.

## Required component — Upcoming-opponent scouting reports

Owner addition (2026-10-12): coaches can upload scouting reports for the next
team we play. Include this in the next continuation specification/task graph;
it is not authorization to interrupt the current hosted-activation task.
Associate each report with its intended opponent/upcoming matchup. Exact game
linkage versus opponent-only reports needs a decision before implementation.
Do not invent report content or automatically generate scouting conclusions.

Council defaults adopted2026-10-12: PDF only, at most5 MiB, linked to an existing
same-team shared Game UUID including future games. Owner-granted `scouting.upload`
and `scouting.read` remain separate from membership or coach labels. Pending access
is uploader/owner only; the owner approves publication. Published access needs
current active membership/read authority (or owner authority). Replacement approval
atomically advances an immutable version; archive hides ordinary access while
retaining bytes/history, initially inspectable only by the owner.

See [ADR0003](docs/adr/0003-private-game-linked-scouting-reports.md) for tradeoffs,
revocation/retry/capacity safeguards. Native file validation/source tests may
proceed; actual upload remains unimplemented and blocked by trusted private
storage/validation/transfer-capacity/$0 acceptance. A5 MiB product ceiling does
not establish provider affordability. No current grants, hosted migrations or
services change from adopting these defaults; existing video rules remain separate.

## Security direction

Use the Supabase publishable key in the app; keep privileged Supabase keys,
AI credentials, and spreadsheet secrets on trusted server infrastructure.
Enforce team and role access through database policies, including RLS on exposed
tables, and protect role/approval fields from user tampering. Protect uploaded
images, practice videos, and game film through storage policies. Owner-granted upload
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

- In-game entry is restricted to the shot-recorder amendment. No game-clock,
  possession, substitution or lineup tracking or public live-score broadcast.
- No fabricated actual team roster, school branding, additional data fields, or
  statistical claims. The owner authorizes labeled temporary roster names/numbers.
- Implementation and necessary free tooling are authorized within current owner scope;
  paid/uncertain-cost actions and actual tool confirmations remain separately gated.

## Release decisions

- Budget is strictly$0; provider feasibility/capacity and distribution still need verification.
- TODO_DISTRIBUTION: pilot group and long-term app distribution method.
- TODO_RELEASE_CRITERIA: agreed device coverage and end-to-end checks.
- TODO_PILOT_DETAIL: metrics, participants, distribution and acceptance criteria.
  Automatic Google Sheets/media delivery may follow the first manual-stat pilot.

Backend choice does not determine which advanced stats are possible: collected
inputs and documented calculations do. Do not expand collection scope merely
to enable a metric without the owner's agreement.

## Current implementation acceptance — 2026-10-12

Private play-linked clips and game-linked scouting PDFs now have source-level
native draft/review/viewing paths and actual isolated Auth/Storage/validator/native
playback evidence. Optional retained clips are account/team/version scoped; current
remote authority is always checked. Full-game film remains Hudl shortcuts, and
photos remain on-device proposals. Full shared-data offline sync is deferred.
The Lincoln/native polish rubric still requires rendered device acceptance: a build
or independent source review does not pass light/dark/rotation/Dynamic Type/VoiceOver,
keyboard Save, delayed/failed writes, unsaved navigation or known-access-loss checks.
Hosted Free capacity is unknown and denies delivery by default. No local records
are auto-uploaded, approval is not optimistic, and release is not authorized.

## Current remaining-work reconciliation —2026-10-17

[READINESS.md](READINESS.md) consolidates the remaining product/engineering work,
provider/configuration gates, owner policy/content, device/accessibility acceptance
and release-only prerequisites against the111-item reliability audit. Earlier
TODO lists remain historical context; adopted permission/completion/defaults are
not reopened. Scheduling source/local tests do not establish activated Google
delivery, hosted recovery, device acceptance or release readiness. No new collection
field, metric, live tracking or offline-sync requirement is introduced.

## Account-deletion request boundary2026-10-17

Prepare authenticated self-request intake separately from deletion execution. The
Account screen requires explicit confirmation and a validated server receipt before
acknowledging that a request is recorded. Repeated requests/readback retain one
immutable receipt per account; missing backend capability is unavailable. The
account remains active. No deletion date, notification/handling route, processing
status or legal-compliance claim is invented. Retention, shared-history attribution,
ownership transfer, backup treatment and eventual execution/receipt policy remain
owner decisions. Source-only migration16 is not activated on existing environments.
See ADR0005 and TESTING for isolated evidence and remaining deployment acceptance.
