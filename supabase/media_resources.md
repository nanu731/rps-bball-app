# Reviewed video-link resources

Migrations005/007/008 follow team access, statistical games and play revisions. It stores
user-authored HTTPS **link metadata only**. It does not upload, download, embed,
probe a provider URL or establish video ownership, private playback or Hudl rights.
Open provider links only through explicit user action. Provider login/access may
still be required; a published TeamStats link cannot make a provider video private.
Never put credentials/access tokens into a link. Fragments, credential query keys,
userinfo, non-HTTPS, malformed percent escapes and oversized values are rejected.
URLs use the default HTTPS port or443; URL2048/title120/notes1000 are request bounds,
not basketball/media-duration limits. Incomplete drafts may have empty title/link.

## Game Film: supported Hudl shortcuts

Migration `202610120001_hudl_shortcuts.sql` restricts new game-film draft saves,
submissions and publication to safe HTTPS destinations on `hudl.com` or
`www.hudl.com` (default port or443). This deliberately narrow host allowlist is
based on Hudl's documented team-library sharing route, not a claim that every
Hudl product/subdomain is supported. Lookalikes, trailing-dot/encoded authorities,
unsupported subdomains and credential-bearing URLs fail closed. A supported host
does not prove that an individual path exists or that the user can access it.

The additive guard leaves existing links, revisions, publication pointers, grants
and audit records untouched. Historical non-Hudl links remain readable and are
explicitly labeled earlier provider links in native detail. Copying an earlier
proposal into a successor preserves saved text; its next Save/submission requires
an explicitly replaced supported destination or blank incomplete draft. A pending
unsupported historical link cannot be newly approved; the owner can reject it with
guidance without altering its URL. Generic historical-response validation remains
separate from stricter new-input validation, so old records do not break loading.

Film stays on Hudl: no full-game file upload, embedding, scraping, export or offline
film download is provided. Opening requires an explicit tap. Hudl separately
requires its account/team access; TeamStats membership/publication cannot confer
that authority. See [Hudl Share Video & Data](https://support.hudl.com/s/article/share-video-and-data-new-hudl-fb?language=en_US&topic=Review_and_Share_Video_V3).
Real authorized-link opening, sign-in, unavailable-link and denied-provider cases
on both device types remain acceptance gates. Synthetic URLs are never opened.

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
Version reads use a target-scoped PostgREST inner embedding with the verified
`media_resource_versions_team_id_resource_id_fkey` relationship. Both team and
selected parent kind/play/game UUID filters apply before transfer, retaining RLS
and ordered pagination; unrelated team video history is not fetched then hidden
locally. The reverse published-pointer relationship is not implicitly selected.

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

### Lost recovery acknowledgment

Migration008 records a nullable, unique same-resource `recovery_source_version_id`
only when resume creates its fresh draft. Prior history stays null; no guessed
relationship or automatic backfill. A lost successful response must not cause
blind retry. Reload updates the editor's old revision metadata even if now
superseded, and a validated helper identifies exactly one current own editable
successor through a unique same-author/same-resource immutable lineage chain.
Intermediate proposals must be read-only superseded revisions; missing, forked,
cyclic, cross-author or noncurrent paths cannot attach text. Stale bases, ambiguous matches, changed
revision and lost contribution eligibility cannot attach retained typed text.

Attachment requires explicit confirmation and rechecks the captured successor ID
and revision. It swaps editor revision metadata only; current typed text stays
unsaved until a separate Save. Source history and accepted pointers remain intact.
No provider operation occurs. The native lost-response tracer actually committed
its synthetic recovery then failed the acknowledgment; before this fix it failed
at successor identification after Reload. Actual view tapping remains unverified.

## Strict $0 file-upload/playback contract — not implemented by links

A future trusted upload service must establish **known current project capacity**
and free-plan status before authorizing bytes. No payment details, paid SMS/AI,
overages or plan upgrade are authorized. Unknown/stale budget status fails closed.
The provider's50MB ceiling is not an app allowance: choose a lower application
limit and make it explicit; full game film is excluded from TeamStats storage.

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
Necessary free Storage/Functions/Imgproxy tooling is now owner-authorized; actual
installation and trusted capacity enforcement remain separately verified. Link tests cannot substitute for actual object upload/download,
provider rights, billing-disabled evidence, hosted RLS or device playback checks.

## Evidence

A missing-command tracer failed before implementation; the actual isolated
Postgres rollback suite passed78 checks (synthetic identities only). All fourteen
native media fixtures passed, including lost recovery replies, chained attachment,
denied attachment and target-scoped reads. The read-filter regression was observed
failing first; the actual local Auth/PostgREST/SDK practice and film workflow then
passed with the explicit FK embedding. Native SDK
fixtures exercise validation/save/retry/current authority; device interaction,
hosted services and actual external-provider access are separate checks. No
existing runtime/simulator records are overwritten by these tests.

### Hudl-only shortcut slice — 2026-10-12

Slice source is commit `adde255` (based on `dcf13bc`); the initial test results
below apply to its Hudl validation changes, not later integrated features.
The native Save tracer first failed because a film accepted an unrelated HTTPS
host. After kind-specific validation, all18 native media tests passed on iPhone
Simulator26.4, including host/blank validation and historical-film recovery without
rewriting saved links. The actual loopback command tracer also failed before the
additive guard; after it,24 Hudl checks and78 existing media regression checks
passed. Each SQL run rolled back fixture rows and migration DDL; postflight
confirmed the new validator was absent from that existing runtime. No hosted
migration, provider-link opening or actual Hudl/device UI acceptance is claimed.
The existing opt-in SDK lifecycle fixture now supplies a never-opened Hudl URL
for film; that named real SDK workflow has not been rerun for this slice.

### Reviewed query-parser repair — 2026-10-12

An authenticated command tracer reproduced server acceptance of a credential
parameter after a second question mark, while native validation rejected it.
The additive migration replaces the existing private validator's query extraction
with the entire substring after the first question mark. Existing stored URLs are
not rewritten; unsafe new practice/film saves and transitions are blocked.
Harmless extra question marks remain valid. At base `adde255` plus this repair,
26 Hudl and79 media regression checks passed in rollback-only loopback SQL.
Exact tested migration SHA256: `59627e8761ecb92e1398f7366ed1304501ef578b1d3e715e8d38ee29fdf70c23`.
Native parity regression and post-integration checks are recorded separately;
this SQL result is not hosted/provider acceptance.
