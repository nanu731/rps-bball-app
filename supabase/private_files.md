# Private scouting PDFs and practice clip bytes

Migration `202610120003_private_file_resources.sql` adds a separate immutable-file
lifecycle. Existing video-link tables, grants, records and historical versions
remain unchanged. It never imports local statistics. Full-game files stay on Hudl.
The trusted gateway is **isolated loopback development only**; hosted delivery is
unavailable until actual capacity, validator hosting and strict$0 protection pass.
No provider plan, payment, external sender or production configuration is changed.

## Identity, visibility and approval

A resource targets an existing same-team shared game (`scouting`) or currently
published play (`practice`). Resources retain their identity; each upload operation
creates a fresh version/object path. No overwrite, deletion or automatic eviction
is exposed. Scouting requires separate `scouting.upload` / `scouting.read` grants;
these names extend the whitelist without issuing any live grants. Only the owner
approves scouting publication. Current published scouting viewing needs read
permission; archived/previous accepted document retrieval is owner-only. Currently eligible authors
can inspect their own pending/failed metadata for recovery; rejected scouting history is
owner-only. Losing a
scouting-upload grant conceals these records and blocks pending-byte retrieval.

All active members can propose pending practice clips. For the **new byte feature**,
`practice.upload` or `practice.publish` permits an eligible author to publish their
own validated clip without individual approval. Existing link semantics are
unchanged. Only the owner approves another person's submitted file; review/grant
administration is separate. Published clips are visible to active members. Every
reserve, upload authorization, trusted finalization, publication and retrieval
rechecks a verified live Auth session and current team/capability authority.
Service-role commands do not derive authority from client-writable metadata.

## Public interface

`file_resources` stores kind, game/play target, current accepted pointer and archive
status. `file_resource_versions` stores operation identity, author, revision,
`uploading/ready/submitted/rejected/published/failed`, metadata and trusted byte
receipt. Read-only authenticated grants plus RLS filter both tables. List by team
and selected target **before transfer**, using
`file_resources!file_resource_versions_team_id_resource_id_fkey!inner(...)` when
embedding parents. Do not fetch all team history and hide it on the device.

- `file_reserve(p_team_id,p_resource_id,p_kind,p_target_id,p_operation_id,
  p_declared_bytes,p_title,p_notes='',p_base_published_version_id=null)` returns a
  stable version. Repeat the same operation to reconcile a lost reservation reply;
  changing identity/length/source raises `40001`. Corrections pass the captured
  accepted pointer; each version receives a distinct immutable object path.
- `file_save(p_team_id,p_version_id,p_expected_revision,p_title,p_notes)` edits only
  the author's uploading/ready metadata. Incomplete title/notes may be saved.
- `file_transition(...,p_action,p_reason='')` accepts submit/publish/approve/reject.
  Submission/publication needs nonempty title and exact trusted receipt. Submitted
  content freezes; accepted/rejected/failed history cannot be rewritten. Approval
  compares the current accepted base and preserves the old version on conflict.
- `file_archive(p_team_id,p_resource_id,p_expected_published_version_id)` is owner
  only and retains metadata/bytes/history.
- `file_upload_access(p_operation_id,p_reconcile=false)` refreshes current signed
  user authorization immediately before the worker claims that operation.
- `file_delivery(p_team_id,p_version_id,p_operation_id)` reserves one complete-file
  transfer, returning version ID/length/SHA256/type, never a bearer URL.

Access failure is `42501`, stale/conflicting operation `40001`, invalid fields
`22023`, and unknown/stale/exhausted trusted capacity `P0001`. These discrepancies
are recoverable errors, never successful empty data or fabricated uploads.

## Capacity, recovery and byte gateway

The private `file_budget` row starts **unknown**. A trusted operator must configure
an explicit bounded allowance and freshness deadline for the synthetic local
project. That is not a measured workload or hosted Free-plan feasibility claim.
Budget locking serializes aggregate reservations across teams; account locking and
a unique active-upload index initially allow one active upload per account.

Reservations count uploading, interrupted, rejected, failed and retained versions.
Expiry/missing-object reconciliation never releases that accounting or deletes
work. Storage readback after upload, explicit uncertain-upload reconciliation and
each whole-file delivery consume conservative transfer allowance before fetching.
A retry that transfers again needs a new charged delivery operation; a claimed
operation cannot fetch twice. Pending capacity failure preserves input/history.
There is no automatic quota reset, cleanup or hosted billing-safety claim.

`private_file_gateway.py` accepts a private0600 configuration containing loopback
REST/Storage endpoints, publishable and service keys, pinned validator executable,
pinned PDF renderer configuration, private temporary directory and listen port.
`mode` must be `isolated_local` and `hosted_enabled` must be false. Credentials stay
server-side; no keys, provider responses, contacts or object paths are logged.
HTTP redirects are denied. One sequential local gateway process is the supported
initial runtime; no hosted multiworker deployment is claimed.

The gateway routes are authenticated `POST /uploads/{operationUUID}`, explicit
`POST /uploads/{operationUUID}/reconcile` with zero body, and
`GET /files/{versionUUID}?operation={newDeliveryUUID}`. The GET route reserves its
own delivery using the signed token; an optional earlier reservation is idempotent.
Uploads must match their exact reserved length. An uncertain PUT is never replayed:
reconciliation reads actual private bytes, validates/digests them and finalizes the
same version. Confirmed missing bytes mark the attempt interrupted; a new operation
can be started while its conservative old allocation remains retained.

The pinned [Storage insertion route](https://github.com/supabase/storage/blob/v1.79.36/src/http/routes/object/createObject.ts) uses `x-upsert:false`; successful PUT alone is insufficient.
The gateway uses the strict authenticated [object route](https://github.com/supabase/storage/blob/v1.79.36/src/http/routes/object/getObject.ts) and reads back actual stored bytes and checks their exact digest/length
before its service-only receipt command. Only service-role can invoke claim,
finalize and delivery operations. The private bucket has a restrictive policy
blocking anon/authenticated read/write even in the presence of another permissive
Storage policy, so direct SDK paths cannot bypass transfer admission.

## Trusted validation

Scouting is PDF, maximum5MiB; practice is MP4/H.264 with optional AAC, maximum10MiB,
30 seconds and1920×1080. These are conservative development bounds from ADR0004,
not expected basketball frequency or measured provider capacity. No silent
conversion/compression. File-type labels, client hashes and client receipts are
untrusted.

The pinned subprocess reads `{path,kind}` JSON and returns
`{valid,media_type,byte_count,sha256,details,failure_reason}`. The gateway independently
checks actual byte length/digest/type plus bounded page/codec/duration/dimension
results; a missing or altered validator fails closed. PDF details use `pageCount`;
clip details use `duration,width,height,videoCodec,audioCodec`. Validator execution
has a60second wall deadline,45second per-process CPU bound,512MiB process-group RSS
monitor, bounded output/files/descriptors, no core dumps and one concurrent decode.
The renderer path/hash are trusted operator configuration, not upload fields.
Actual native parser/renderer verification is a separate recorded check.

Delivery returns a complete integrity-checked body, SHA256 header and `no-store`,
not a remotely ranged AVPlayer URL. Optional app retention/offline playback is a
native feature with its own restart/account/space checks. Previously delivered
copies cannot reliably be recalled; every future remote operation rechecks current
authority. This is not full offline shared-stat synchronization.

## Evidence and remaining gates

The missing-command tracer failed before implementation. The rollback SQL suite
passed69 checks against the actual approved local Postgres instance: authenticated
commands, missing/zero/oversized/overflow/target validation, state/revision/approval,
RLS and service-only receipt denial, retained budget accounting, session/revocation,
archive/history and transfer exhaustion. Its injected **protocol receipts are not
actual Storage or content-validation evidence**. It rolls back the entire new schema
and every synthetic identity/audit row; existing records are untouched.

Twenty-four stdlib HTTP/subprocess gateway tests passed, covering exact-length actual
HTTP route response, durable readback/digest, interruption, lost acknowledgment,
explicit reconciliation without overwrite, denial/revocation, private error
sanitization and pins, plus five previously failing monitoring/orphan-child cases and the observed
Storage `NoSuchKey`/HTTP400 recovery regression. Monitoring
failure denies validation; every launched group is killed and its parent reaped
before the parser lease is released. Unconfirmed cleanup keeps the parser blocked
until trusted operator recovery. The provider and validator are explicitly synthetic external
fixtures; they do not establish real Storage, PDF/AV decode, hosted enforcement or
device playback. Actual isolated integration on2026-10-12 passed **67 checks**, using server SQL
revision `9bfac9d`, gateway revision `6eb0446`, and trusted validator revision
`e619698`. These include fixture/identity/setup checks, not67 distinct features.
The fresh synthetic stack retained only reviewed migration003;11 independent
RLS/ACL/bucket/migration-history/default-unknown readbacks passed before use.
No hosted activation/bootstrap was rerun. The earlier runtime and original
simulator records were untouched.

Four independently signed local Auth sessions exercised actual private Storage,
full pinned native PDF/H264/AAC validation, exact durable digest/length, owner review,
ordinary pending clip submission and authorized own-author publication. Real
reader/uploader/anonymous-role tokens were accepted by Storage before all direct
private-bucket reads/writes were denied. Pending/nonmember retrieval, immediate
read-grant revocation and old-JWT denial after actual Auth logout passed. Actual
truncated input remained unconfirmed; real missing-object reconciliation allowed
one fresh immutable operation while retaining the old reservation. Encrypted PDF
bytes failed trusted validation without an upload receipt. Accepted clip replacement
retained the prior version/body. Concurrent same-account requests admitted exactly
one active upload; different actors in different teams could not overrun the shared
aggregate budget. No bytes, identities, charges or records were deleted.

The actual Storage version returns a missing key as HTTP400 with
`code=NoSuchKey` and `statusCode=404`; the public recovery regression failed first
and now treats only that verified shape (or HTTP404) as missing, without mistaking
other failures for absent bytes. Initial native/Auth REST response-shape/HTTP204
expectations were harness repairs, not application defects. Synthetic per-run
budget allowances are explicit trusted local configuration and never establish
hosted cost safety.

Three actual native validator cases also passed through the repaired resource
supervisor (PDF, H264 and H264/AAC). Native app upload/download, AVPlayer playback,
restart/offline retention/space/UI and hosted capacity/cost acceptance remain
separate checks. The gateway and provider are real **local** services; no hosted
file feature, production release or physical-device acceptance is claimed.

### Validator/gateway repair verification — 2026-10-12

Repair source `de575eb` passed20 actual native parser/process tests and25 gateway
tests, including actual supervised1080×1920 H264. The clip bound is orientation
independent: long edge≤1920, short edge≤1080; dimensions and bytes stay unchanged.
The portrait gateway mismatch failed first and now accepts the native receipt.
The original16 parser cases remain covered, with two added file cases and two
owned-process supervision cases. No iPhone/iPad UI or physical-device acceptance
is implied by these Mac-native checks.

A synthetic MP4 containing an external local `dref` declaration was accepted by
the original pinned validator. That fixture retains internal samples, so the
result does **not** prove external-file decoding or an exploited filesystem read.
The new validator requires bounded self-contained `url ` reference entries before
AVFoundation, and sets `AVURLAssetReferenceRestrictionsKey` to `forbidAll`.
The declaration now fails before decoding, emits no receipt and leaves the
separate synthetic file untouched. No external network reference was followed.

Native test execution now owns a process group, enforces its deadline, kills all
owned descendants, waits for the parent and verifies group disappearance before
returning results. Both parent-timeout/orphan-renderer tests failed first and now
pass. Production supervision remains the gateway's separate CPU/RSS/concurrency
contract. A checked word-sized pointer identity also handles the observed
CoreGraphics opaque-pointer/wrapper importer difference; the repaired worker
rebuilt with Xcode Swift6.3/MacOSX26 SDK and passed the PDF graph cases.

The repaired executable and new portrait fixtures have distinct private paths/
pins; original binaries, fixtures and all local/provider records remain intact.
The unchanged67-check shared-budget harness was deliberately not rerun during
concurrent native-client fixture work. Root integration must switch only its own
ignored trusted configuration/pin and verify the new native byte client. Hosted
capacity, deployment, provider rights and$0 acceptance remain gated.
