# TeamStats product context

## Positioning

One high-school basketball team's practice-and-game planning, capture and review
workspace. PROJECT_DIRECTION.md records confirmed direction and pending owner
questions; it is the current planning source of truth.

## Operating context

Coaches prepare practices and choose collection priorities. Managers record practice
shooting and selected game observations; players and coaches view authorized,
reviewed results. The confirmed primary product is a responsive React/TypeScript
web app for phone, iPad and desktop with existing Supabase; Swift remains legacy.
The pilot includes practice plans/PDFs, nine-spot player shooting, FT conditioning,
game shots, selected events and manual box scores/possessions/player paint touches.
Our-team shots are player-attributed; opponent shots are team-only. A running game
clock and simple reusable collection templates are confirmed. Detailed clock
operation, nine-spot layout and drill protocols remain unresolved.
The web pilot is implemented under web/ with local and signed isolated-service
checks documented in web/README.md. SwiftUI/Supabase remains preserved legacy work.
Source and local evidence do not establish hosted deployment or device acceptance.
Budget: strictly $0. Do not activate services based on assumed free allowances.

## Confirmed finished web experience — 2026-11-17

Email/password accounts require email verification and owner-approved team access,
with password recovery, sign-out and continuing sessions. Players view their own,
other players' and team statistics/shot charts, practice plans and practice stats.
Both individual-game views and season totals are required. Coaches and managers
also record, correct and verify stats, including their own entries; retain who
entered and verified each version. Coaches and managers have identical plan and
statistics permissions: both can upload PDFs and use the plan builder. This
supersedes the earlier manager upload restriction. The owner retains every
capability while also serving as a manager.

Signup collects first and last name and a requested Player, Manager or Coach
role. After email verification, applicants wait on a clearly labeled preview
with feature guidance and no real team data. Notify the privately configured
owner email of each verified access request; the owner reviews the applicant
and confirms or changes their role through authenticated administration. Email
verification and requested roles never grant team access. Preserve existing
approved accounts, prevent duplicate requests, and keep pending requests
reviewable if email delivery fails. Approval activates only the permissions
confirmed by the owner and enforced by the server.

Support both PDF plan uploads and the editable plan builder. Share upcoming plans
independently of practice-result publication. Players can view shared plans but
cannot upload or edit them.
Keep published results separate from staff drafts and independent statistical
sources separate in season totals. PROJECT_DIRECTION.md records the delivery
sequence and acceptance requirements. These are confirmed requirements, not
evidence of completed authentication, uploads, permissions or season views.

## Evidence on hand

Existing source, backend contracts and TESTING.md record native/local/hosted checks
with scoped limitations. PRD.md and native planning ledgers are historical reference.
They do not prove browser, handwriting or courtside acceptance. Coach notes name
nine-spot shooting and drills but do not define locations or protocols.

## Product principles

Preserve the approved maroon sports ledger, compact aligned viewing, spacious touch
entry, calm scoring notices and accessible horizontal statistics. Follow
DESIGN_SYSTEM.md; native details need browser adaptation. Use Impeccable,
apple-design and UI/UX Pro Max without a competing visual system.
Record evidence before interpreting it. Missing is not zero; saved is not reviewed.
Retain source/history, current server authority and user corrections. OCR/voice
proposals require review. Preserve native work and original records.

Unknown owner facts stay visible: TODO_NINE_SPOT_LAYOUT, TODO_DRILL_PROTOCOL,
TODO_TEAM_ROSTER, TODO_TEAM_LOGO, TODO_OFFICIAL_MAROON_HEX.
