# Reviewed video-link resources

Migrations005/007 follow team access, statistical games and play revisions. It stores
user-authored HTTPS **link metadata only**. It does not upload, download, embed,
probe a provider URL or establish video ownership, private playback or Hudl rights.
Open provider links only through explicit user action. Provider login/access may
still be required; a published TeamStats link cannot make a provider video private.
Never put credentials/access tokens into a link. Fragments, credential query keys,
userinfo, non-HTTPS, malformed percent escapes and oversized values are rejected.
URLs use the default HTTPS port or443; URL2048/title120/notes1000 are request bounds,
not basketball/media-duration limits. Incomplete drafts may have empty title/link.

## Identity and authority

Practice resources target a stable **currently published play** in the same team;
film targets an existing shared game UUID. Target identity/kind never changes.
All active members may submit practice links; `practice.upload` is not required
for ordinary practice submission. Film contribution requires `film.upload` (owner
assigns eligibility to coaches/managers). Owning `film.publish` alone does not
establish film eligibility. `.publish` grants bypass review for eligible authors'
own valid drafts; they never approve another contributor's pending resource.

Only the protected team owner approves/rejects pending videos. Legacy
`practice.review`/`film.review` grants inspect pending/rejected metadata, not final
approval. Existing grants/audit stay intact. Unsubmitted drafts are author-private;
active members read accepted history. Removed/nonmembers and expired/revoked live
Auth sessions cannot read or execute commands. All mutations use the common team
and Auth-session locks; membership/capabilities are rechecked before commit.
Protected tables have read-only authenticated grants and explicit RLS. No client
owner bootstrap, direct protected writes or record deletion is exposed.

## Public commands

- `media_open_draft(team, resource, kind, target, source?)`: stable resource UUID
  retries return the existing author's draft. New resources start empty. Select a
  published or own rejected source for a fresh successor; submitted revisions are
  frozen. Published pointer stays intact while a correction is proposed.
- `media_save_draft(team, version, expected_revision, title, link_url, notes)`:
  eligible author only; atomically validates fields and advances revision. No lost
  response replay using an old revision; client reloads and retains unsaved text.
- `media_transition(team, version, expected_revision, action, reason)`:
  submit/publish/approve/reject. Submission needs title/valid link. Publication is
  atomic with current-base comparison, accepted pointer and append-only audit.
  Accepted/rejected versions remain immutable. Rejected proposals can seed a new
  draft without changing previous history.

`media_resources` stores stable linkage/current accepted pointer;
`media_resource_versions` stores drafts/frozen accepted history. Native UI is
`MediaResourcesView(teamID:kind:targetID:targetTitle:account:)`. Wire it only from
published play details and connected shared game details; it never reads/uploads
local JSON or converts temporary player identities. Lists distinguish load error
from empty data and offer Reload; editor preserves typed text while loading current
revision after conflict. Save is available in the navigation bar and form; native
keyboard Done dismisses typing. Large text uses wrapping system styles/sections.

### Explicit recovery after a newer acceptance

An existing author draft is never silently replaced/rebased by selecting a newer
published source. After another author publishes, `media_resume_draft(team,
version, expected_revision, expected_published_version_id)` checks both current
identities under locks, freezes the saved old proposal as `superseded` and copies
its metadata into a fresh draft against the checked current accepted pointer.
The old proposal remains author-readable and immutable; publication is unchanged.
This is an explicit user action, not record deletion. The native editor retains
current typed text separately, so unsaved edits stay visibly unsaved against the
fresh draft; saving before resuming is optional. Pending submitted records remain
frozen until the owner rejects them or accepts a nonstale proposal.

## Strict $0 file-upload/playback contract — not implemented by links

A future trusted upload service must establish **known current project capacity**
and free-plan status before authorizing bytes. No payment details, paid SMS/AI,
overages or plan upgrade are authorized. Unknown/stale budget status fails closed.
The provider's50MB ceiling is not an app allowance: choose a lower application
limit and make it explicit; no promise that full game film fits Free storage.

Reserve storage bytes and conservative transfer allowances atomically, keyed by
stable resource/version/user/team with finite expiry. Concurrent upload requests
must not collectively exceed known remaining capacity. Reconcile reservations
against actual verified object bytes before publishing metadata; expired/failed
reservations release accounting without deleting source work. Trusted type/content,
size and ownership checks must reject unsupported or oversized uploads before
publication. Never trust client MIME/byte count, arbitrary bucket path or user
submitted owner identity. Server-enforced private policies must deny pending-object
access to ordinary viewers and stop removed/revoked users. Accepted successors use
new immutable object identities, not overwrite old video history.

Playback admission must account for egress/transfers and recheck current membership
before issuing bounded access. Unknown quota, provider rights or capability is a
blocked operation, not a successful upload/playback. No silent compression,
deletions, eviction, public bucket or external transfer workaround. Raw private
provider tokens stay trusted; no service-role/Google/media secrets ship in iOS.
Actual Storage/Functions/Imgproxy tooling and trusted capacity enforcement remain
separately gated. Link tests cannot substitute for actual object upload/download,
provider rights, billing-disabled evidence, hosted RLS or device playback checks.

## Evidence

A missing-command tracer failed before implementation; the actual isolated
Postgres rollback suite passed73 checks (synthetic identities only). Native SDK
fixtures exercise validation/save/retry/current authority; device interaction,
hosted services and actual external-provider access are separate checks. No
existing runtime/simulator records are overwritten by these tests.
