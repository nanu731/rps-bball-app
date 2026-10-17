# Integrated shot capture with independent reconciliation

Owner scope amendment,2026-10-17. Add an optional iPad-first shot recorder inside
TeamStats rather than a second app, reusing roster/game identity and permission
boundaries. One designated manager captures our player-attributed field goals,
team-level opponent field goals and side-panel free-throw attempts/results.
This is the narrow exception to historical no-live-tracking rules; existing
box-score/possession/paint-touch entry remains after-game.

Keep shot events separate from official after-game datasets. Reconcile points and
available makes/attempts without merging totals or inferring locations. Score
agreement cannot establish that missed attempts were recorded; coverage/review
claims remain distinct. On2026-10-17 the owner selected designated-manager
confirmation of all field-goal/free-throw attempts followed by owner or authorized
statistics-reviewer approval for the reviewed version. Manager confirmation alone
does not establish Coverage complete; edits require renewed confirmation/review.
This resolves the policy decision, not implementation or acceptance.

The alternative standalone app adds another release and data-integration boundary
for the same users/games. Local durable capture and controlled deferred submission
are necessary for the courtside workflow; they do not authorize general offline
shared-data synchronization. Server authority governs upload/review/publication.

This records product direction, not implemented behavior, activation or release
acceptance. Detailed requirements and unresolved decisions live in
[PRD.md](../../PRD.md#in-game-shot-recorder-amendment--2026-10-17).
