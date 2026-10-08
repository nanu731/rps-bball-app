# TeamStats — Project Context and Development Sequence

Last updated: 2026-10-08.
Status: requirements draft; Step 3 complete, implementation at `1c3c314`.
Local game creation and both box-score entry modes are implemented, including
blank-versus-zero semantics, draft storage, and shot/points discrepancy flags.
The owner confirmed the remaining iPhone table scrolling/keyboard checks and
iPad new-game Save/details checks passed. Simulator verification used 26.4;
actual 26.0 and physical devices remain untested. Next: local paired possession
draft entry only. Completion/edit requests follow backend authorization; cross-sheet comparison
follows possession entry.

## Workspace and source of truth

Workspace: `/Users/narayanlekhi/Documents/ChatGPT/Basketball stats input app`.
Existing Xcode project: `TeamStats/TeamStats.xcodeproj`.
App source: `TeamStats/TeamStats/`.
Owner-specified public GitHub repository: `https://github.com/nanu731/rps-bball-app`.
Use this existing project and repository. Do not create a replacement project,
nested Git repository, alternate app, or workspace outside this folder.

Read applicable AGENTS.md instructions, PRD.md, and WORKFLOW.md before work.
PRD.md is authoritative for detailed product requirements. WORKFLOW.md defines
coordination and handoffs. This file is the concise entry point and sequence.
Resolve contradictions using the owner's latest explicit decisions; report them
rather than quietly inventing requirements.

## Product context

- High school basketball app for approximately 100 users, including players,
  managers, and coaches. Native Swift/SwiftUI, supporting iPhone and iPad.
- Minimum iOS/iPadOS 26.0. Game fields: date, opponent, our team's home/away
  status, and regular season/playoff. No scrimmages.
- Supabase holds official stats. Google Sheets receives automatic one-way
  exports of published data and accepted corrections.
- All statistical entry is after games. Manual entry first, photo autofill later.
  Absolutely no live game tracking in any phase.
- Initial pilot focuses on manual stats. Online submission first; offline sync
  is low priority. Playbook, videos, and photo extraction follow the pilot.
- Signup supports both email and phone as options; do not require both from
  every user. Authentication details and account linking still need agreement.
- Any app user can submit stats and corrections for owner approval. Selected
  owner-authorized users may publish without case-by-case approval.
- Coaches draw/save plays, and viewers see animated movement. Practice videos
  link to plays. Authorized users upload without individual review; other users
  upload pending clips that only the owner may approve for team viewing.
- A Game Film menu lets coaches/managers upload recorded videos linked to games,
  with the same owner-authorized upload bypass and pending review for other
  eligible uploaders. It follows the manual-stats pilot; no livestreaming or
  automatic video-to-stat extraction is requested.
- Hudl is the likely game-film recording source. Exported-file upload versus Hudl
  links is unresolved; do not assume direct API access or build an integration yet.
- Owner-managed permissions apply to stats, plays, and videos. Separate versus
  shared permission grants remains unresolved.

## Data scope

Player game totals: points, offensive rebounds, defensive rebounds, assists,
turnovers, steals, blocks, fouls, charges drawn, and made/missed counts for twos,
threes, and free throws. Derive total rebounds from offensive + defensive.
Record each of our players' game-total paint touches separately.

Manual box scores support both individual-player and whole-roster table entry
against the same records. Blank means not entered, not zero. Check entered points
against shot makes; preserve discrepancies for correction rather than overwriting
them. Compare game-total box-score points with advanced-sheet possession scoring
when both matching datasets are complete; missing data is not a passed check.

For each team's possessions: paint-touch count, offensive-rebound count,
made/missed tallies by shot type, and turnover outcome. No shot sequence is
collected. Offensive rebounds continue the same possession.

Pair our team's nth possession on the left with the opponent's nth on the right;
each team has independent numbering. Provide reversible entry-complete checkboxes
for the team sheets; unchecked sheets leave the game labeled incomplete data.
Legal possession groups all actions until the opponent legally possesses the
ball, including free throws and offensive rebounds. Period-ending possessions
with actions count; no-action holds until the buzzer do not count.
Completed datasets require an edit request approved by the owner or an authorized
dataset-editing reviewer before changes; revised data needs completion again.
Build drafts first; enforce completion/edit requests later with authenticated
backend permissions. Reviewer scope and reopen details remain to be settled.

Visual direction: restrained native SwiftUI, system typography, clear forms and
tables, consistent spacing and readable contrast. Avoid the owner's listed
gradient/card/animation/font/copy tropes; see PRD.md for the explicit exclusions.
No separate redesign is authorized by these preferences alone.

Paint touch means intentionally establishing two feet in the paint with the ball.
Real Possessions is calculated separately for each team:
`team possessions - team turnovers + team offensive rebounds`.
The revised source notation `FTmade/attempted` yields misses = attempted - made.
A revised PDF draft is available as `rpsadvstatsdraft-revised.pdf`, pending owner
confirmation; old makes-only FT notation cannot supply misses.

Exclude 50/50 balls, ATOs, transition flags, shot-style classifications, timeouts,
quarter-score checkpoints, and any other unrequested collection fields.
Printed PDF names/numbers are arbitrary. Temporary arbitrary roster names/numbers
are explicitly permitted until the owner supplies the fixed roster after tryouts.
Label that roster as temporary; do not invent actual school branding or game stats.
Use obvious TODO markers and truthful empty states for missing owner content.

## Security and review

Publishable Supabase key in the app; secret/privileged keys, spreadsheet
credentials, and AI secrets on trusted infrastructure only. Use Supabase Auth,
RLS, protected owner-managed grants, private media policies, HTTPS, secure
credential storage, and database/server validation. UI restrictions alone do
not establish permission enforcement.

Proposed correction behavior: retain published data while edits await review.
Only accepted changes affect stats and exports. Confirm this before implementing.
Do not add dependencies, restructure files, or delete work without owner approval.

## Remaining owner input by milestone

Foundation can proceed with empty states; it does not require a roster or secrets.

Before final entry/schema work: completed notation examples,
possession/page mapping, remaining paint-touch/possession boundary definitions,
player visibility, enrollment rules, and pending-edit/permission-granularity choices.

Before connected services: Supabase project details (public URL/key only in chat),
owner account identification, auth-provider setup, and Google Sheets destination.
Never ask the owner to paste privileged keys into a handoff.

For GitHub publication: use the owner-specified public repository above. No
remote was configured at the earlier planning inspection; inspect current state
and preserve any remote commits when connecting it.

Current PDF references in the workspace root: `rpsadvstatsdraft-revised.pdf` and
`boxscorestatsheet-revised.pdf`. Both include game type and home/away checkboxes.
`boxscorestatsheet.pdf` remains an unchanged copy of the original template.
A fresh local chat in this same checkout can read these files without inheriting
the planning chat's attachment history. Future supplied files must be saved in
the workspace if they are to be reliably shared across chats.

Before photo import: owner confirmation of the revised advanced PDF and marked
shot/tally examples. The actual roster will be supplied later; labeled temporary
names/numbers are authorized and must remain easy to replace.
Before playbook/video work: editor controls, review details, and media limits.
Before Game Film: eligible upload/view roles, large-file limits, storage budget,
and whether practice/game video grants are shared or separate.

## Development sequence

Each milestone may require several bounded prompts. Complete only the assigned
task, verify it, commit relevant changes, and return the short handoff.

1. Foundation: inspect the existing project/Git state, verify baseline builds,
   and establish simple iPhone/iPad navigation with truthful empty states.
   Connect/push GitHub only once the owner specifies the destination.
2. Resolve entry-specific open requirements; build local box-score, possession,
   and individual paint-touch entry against the agreed fields.
3. Implement local viewing and agreed calculations, including Real Possessions;
   validate against owner-approved examples without inventing sample game data.
4. Configure Supabase tables, Auth, membership, permission grants, and RLS.
   Confirm any dependency installation before adding the SDK.
5. Connect submissions, owner review, authorized publishing, corrections, and
   viewing. Verify with accounts having different permissions.
6. Implement one-way Google Sheets export with correction/duplicate handling.
   Confirm whether export must precede the pilot or immediately follow it.
7. Pilot manual stats on iPhone/iPad; resolve observed issues.
8. Add photo extraction into the existing entry/review workflow.
9. Add dynamic play authoring/viewing, linked practice videos, and Game Film
   uploads/playback linked to game IDs, with backend permission enforcement.
   Reuse common media behavior; split these into bounded prompts. Their relative
   order can be refined later.
10. Verify the complete app, finish distribution requirements, and release more widely.

## Coordination and handoff

Only one chat edits app code at a time. The planning chat owns decisions and
prompts; the implementation chat executes the current prompt. Context-file work
must also be coordinated to prevent overlapping edits.

Preserve existing work and staged changes. Commit only task-relevant files with
descriptive messages; never use a blanket commit to absorb unrelated work.
No force pushes, history rewrites, or deletion of existing work.

Step 1/2 handoffs and verification limitations are recorded in WORKFLOW.md.
Current minimum is 26.0. Build/simulator checks used 26.4; actual execution on
26.0 is unverified because that runtime is not installed.

Return 150–250 words, maximum 300, with:
`STEP`, `RESULT`, `CHECKS`, `GIT`, `DECISIONS`, `BLOCKERS / HUMAN INPUT`, `NEXT`.
Include branch/commit identifiers, dirty state, actual check results, and any
remaining human action. Do not repeat the whole PRD or include secrets.
