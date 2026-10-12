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
permission; archived/previous accepted document retrieval is owner-only. Authors
can inspect their own pending/failed/rejected metadata for recovery.

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

Storage insertion uses `x-upsert:false`; successful PUT alone is insufficient.
The gateway reads back actual stored bytes and checks their exact digest/length
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
passed65 checks against the actual approved local Postgres instance: authenticated
commands, missing/zero/oversized/overflow/target validation, state/revision/approval,
RLS and service-only receipt denial, retained budget accounting, session/revocation,
archive/history and transfer exhaustion. Its injected **protocol receipts are not
actual Storage or content-validation evidence**. It rolls back the entire new schema
and every synthetic identity/audit row; existing records are untouched.

Eighteen stdlib HTTP/subprocess gateway tests passed, covering exact-length actual
HTTP route response, durable readback/digest, interruption, lost acknowledgment,
explicit reconciliation without overwrite, denial/revocation, private error
sanitization and pins. The provider and validator are explicitly synthetic external
fixtures; they do not establish real Storage, PDF/AV decode, hosted enforcement or
device playback. Actual local Storage/native-validator integration, concurrent
signed accounts, native upload/download/restart/space/UI and hosted capacity/cost
acceptance remain separate checks. No migration or trusted budget has been applied
to the hosted project by this slice.
