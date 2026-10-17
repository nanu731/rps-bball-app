# TeamStats

Language for after-game team statistics, designated shot capture and reviewed team content.

## Language

**Game**: A stored game identity used for after-game statistics and optional designated shot capture, independent of its date or opponent label.

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

**Hudl shortcut**: A game-linked destination opened in Hudl, which independently
controls its account and film access. It is not a TeamStats-hosted film.

**Practice clip**: A short team video associated with a play. It is separate from
full-game film and transient stat-sheet photographs.

**Offline clip**: A previously authorized practice clip explicitly kept on a
device for playback without a connection. Delivered copies cannot reliably be recalled.

**Private file version**: One retained, independently validated document or clip
proposal; approval refers to that exact version rather than another replacement.

**Capacity reservation**: An allowance held for a specific transfer or retained
file. A failed or expired operation does not imply its occupied space is free.

**Publication bypass**: Permission for an eligible author to publish their own
valid submission without individual review; it does not create uploader eligibility
or permission-administration authority.

**Scouting report**: A coach-contributed document for a specific upcoming matchup,
linked to that game's identity rather than an opponent-name match.

**Scouting report version**: A retained document proposal or accepted revision;
a new proposal does not replace the currently approved report.

**Verified offline actor stamp**: Device-private identity last confirmed by Auth,
matched to the saved session before retained clips may be discovered. It grants no
remote authority and does not establish current team rights while offline.

**Entered-data subtotal**: A sum of known inputs, identified as incomplete when
required values are missing; it is not a final statistical conclusion.

**Shot capture**: The designated manager's in-game recording of field-goal
locations/results and free-throw results for both teams.

**Recorded attempt**: A captured field goal or free throw, not evidence that every
attempt in the game was captured.

**Free-throw series**: A chosen number of free-throw attempts with individually
recorded make/miss results; unanswered attempts remain unfinished.

**Score reconciled**: Recorded shot points agree with an independently confirmed
official team score. This does not prove complete attempt coverage.

**Coverage complete**: A distinct claim that the full game's attempts were
captured; its confirmation and review rules are separate from score agreement.

**Designated recorder**: The manager assigned to capture a game's shots, with
an explicit handoff when responsibility changes.

**Shot journal**: A device-local, versioned history of captured and pending attempts,
corrections and Undo reversals. It does not establish server permission or review.

**Captured location**: A schematic full-court normalized observation with an explicit
attacking basket. Display flipping does not move the stored physical origin.

**Recorder assignment revision**: The server-confirmed handoff boundary for one
game's designated recorder; cached knowledge never authorizes a later upload.

**Shot batch receipt**: The server acknowledgement of one frozen capture revision,
not acknowledgement of edits made while that revision was being sent.
