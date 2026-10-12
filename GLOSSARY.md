# TeamStats

Language for after-game team statistics and reviewed team content.

## Language

**Game**: An after-game record identified independently of its date or opponent label.

**Temporary player**: A visibly provisional roster identity that is never reused for a real player.

**Paint touch**: A player intentionally establishes two feet in the paint with the ball.
Repeated-touch counting remains unresolved; no player attribution is inferred from team records.

**Possession**: Actions from legal team possession until the opponent legally possesses the ball;
free throws and offensive rebounds remain within it. Period-ending actions count; no-action holds do not.

**Paired row**: Each team's independently numbered nth possession displayed side by side.
_Avoid_: Chronological pair, simultaneous possessions

**Draft**: Unfinished editable collected data; blank numeric inputs remain unentered.
_Avoid_: Published record, completed dataset

**Superseded draft**: Retained saved proposal made read-only by an explicit
recovery or approved current-version correction. It remains incomplete and
unreviewed; it is never a completed or accepted dataset. Unsaved editor content
requires separate confirmed attachment to a validated working draft and explicit Save.

**Completed dataset**: Data explicitly marked entry-complete; this does not establish review or publication.
_Avoid_: Approved data, official statistics

**Published dataset**: An accepted shared version confirmed by the server and visible to authorized viewers.
_Avoid_: Submitted draft

**Edit request**: A request for authorized approval to reopen a completed dataset for revision.

**Real Possessions**: The owner's team-specific metric: game possessions minus turnovers plus offensive rebounds.
_Avoid_: Estimated basketball possession formula


**Play revision**: Saved user-authored geometry and movement steps; a published
revision is retained when a new draft is proposed. Generic diagram marker numbers
do not establish actual player identity.

**Photo proposal**: Untrusted on-device recognized text and mapped candidate values
that require review before entering an existing draft.

**Media resource**: A private practice-video or game-film submission. Metadata or
a link alone does not establish upload, provider rights, or playback.

**Publication bypass**: Permission for an eligible author to publish their own
valid submission without individual review; it does not create uploader eligibility
or permission-administration authority.

**Scouting report**: A coach-contributed document for a specific upcoming matchup,
linked to that game's identity rather than an opponent-name match.

**Scouting report version**: A retained document proposal or accepted revision;
a new proposal does not replace the currently approved report.
