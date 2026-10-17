# Recovery preparation

This is a preparation/runbook boundary, not verified hosted disaster recovery or
release approval. Strict budget: $0. No external backup destination, retention,
automatic backup, paid restore, production action or provider activation is chosen.
UI acceptance remains separately PARTIAL in [TESTING.md](TESTING.md).

## Recoverable inventory

| Domain | Required state | Boundary |
| --- | --- | --- |
| Saved local drafts | Application Support `games.json`, `box-scores.json`, `possessions.json`, `player-paint-touches.json`; game UUIDs, temporary-player strings, possession UUID/team/number, optional counts and unanswered turnovers | Version1 `LocalDraftBackup`; excludes unsaved input, shared caches, credentials and media. No automatic upload or conversion to real players. |
| Team identity/authority | `teams`, `team_memberships`, `delegation_envelopes`, `capability_grants`, `roster_entries`, `roster_entry_revisions`, `team_audit_events` in `public` | Preserve UUIDs, revisions, expiry/revocation and history; never infer owner authority from email/phone. |
| Games/statistics | `games`, `stat_datasets`, `stat_versions`, `stat_edit_requests`, `stat_user_preferences` in `public` | Preserve draft/completed/published distinctions, accepted pointers, optional values and covered historical roster. |
| Export state | `stat_export_outbox`, `stat_export_snapshots`, `stat_export_destinations`, `stat_export_deliveries` in `public` | Preserve accepted-version binding, queued/uncertain/delivered facts and attempts. Restoring does not authorize redispatch. Sheets is not a backup. |
| Plays/media metadata | `plays`, `play_versions`, `media_resources`, `media_resource_versions`, `file_resources`, `file_resource_versions` in `public` | Preserve game/play/version relationships, immutable review targets and accepted pointers. Hudl films remain external. |
| Private file operations | `team_private.file_budget`, `file_uploads`, `file_deliveries` | Preserve reservations, uncertain transfers and charged capacity; do not release allowance merely because an operation expired. Unknown hosted capacity stays disabled. |
| Database enforcement | Schemas, functions/owners/search paths, triggers, constraints, RLS/policies, grants, extensions and `supabase_migrations.schema_migrations` | All22 public tables and3 private tables are covered by the drill. Migration history stays inaccessible to clients and outside the exposed Data API schemas. |
| Auth | Verified user UUIDs and linked provider identities/verification/MFA state needed for account continuity; current authorization and revocation boundary | Real managed Auth recovery is not implemented/tested here. Device sessions, refresh tokens, PKCE and offline actor stamps are not portable authority. Require fresh sign-in and trusted UUID reconciliation; do not silently remap owners. |
| Uploaded object bytes | Every retained `teamstats-private` object key with version binding, byte count, SHA256, content type and corresponding file metadata; include pending/rejected/uncertain bytes that still occupy capacity | Database dumps contain metadata, **not object bytes**. Inventory and recover objects separately; missing bytes are a failure, not an empty bucket. |
| Explicit retained device clips | Account/team/version manifest and complete verified bytes, if owner policy elects to preserve them | Not an authoritative media backup. Copied sessions/stamps must not revive access. Remote originals and known revocation must be reconciled. |
| Configuration / secret references | App/project/bundle/version and public endpoint/key references; Auth redirects/provider/sender settings; exposed schemas; bucket privacy/limits; worker tool pins/capacity gates; export bindings | Version source/configuration where safe. Privately inventory references to database credentials, signing material, server-role credentials, SMTP/OAuth credentials, `TEAMSTATS_EXPORT_SERVICE_TOKEN` and `TEAMSTATS_GOOGLE_ACCESS_TOKEN`. Never place their values in Git, backup logs or client exports. |

Provider-managed Auth/Storage schema versions, signing and delivery configuration
need a separate verified provider procedure. The isolated drill uses clearly marked
platform stand-ins, not a complete copy of those services. A full database archive
may contain highly sensitive Auth material; the current tool cannot export an
existing database and has no hosted mode.

## Minimal $0 approach

Use an explicit, quiescent four-store export for device drafts. Validate it before
recovery; four independently valid files do not establish a cross-store snapshot.
The Foundation recovery seam reuses the actual models/loaders, rejects unsupported
versions, broken game relationships and occupied destinations, stages privately,
then publishes all four stores with one sibling-directory move. It is offline
tooling, not an in-app import screen; app startup never calls it. A process death
may leave a clearly named `.partial` staging directory, not a completed destination.

For shared data, plan an independent logical database backup plus separate object
inventory/bytes and private configuration references. Keep schema/roles/constraints,
RLS and retained history together. Verify provider-managed prerequisites before any
real export, and verify transfer/storage fits free allowances before downloading.
Never dump real records merely to test this procedure. Git/revision history and
Google Sheets cannot replace these backups.

The existing app export is plaintext. Synthetic drill artifacts are private local
files/directories, **not encrypted backups**. An owner-selected encrypted private
destination and verified free encryption/retention arrangement remain required
before real operational backup. SHA256 checks detect corruption; they do not
authenticate an untrusted backup author. No external destination or encryption
service has been configured.

## Executable synthetic proof

- `LocalDraftBackup.restore(_:toNewDirectory:)` and `LocalDraftBackupTests` restore
  a hand-authored fixture and reopen all four actual stores. They check identities,
  metadata/relationships, missing/zero, historical unanswered turnover and refusal
  without publishing partial data or changing an occupied/symlink destination.
- `supabase/recovery_drill.py` requires PostgreSQL17 tools, an explicitly confirmed
  isolated loopback cluster, and a new private output folder. It creates two new
  `teamstats_recovery_*` databases from `template0`; it never dumps, resets or drops
  an existing database. A loopback hostname alone is not proof of isolation: the
  operator must verify the owned local service, not a tunnel to a real project.
- The source gets all13 ordered migrations and synthetic records. An actual custom
  `pg_dump` archive is restored using single-transaction, exit-on-error `pg_restore`
  into the second new database, **without reseeding it**. All30 fixture tables,
  policies and effective ACL/RLS/function-security properties are compared. SQL
  assertions test existing rows, relationships, immutable history, live/missing
  synthetic session references, allowed members, denied outsiders and private bytes.
  Synthetic claims are database-policy evidence, not signed Auth-service recovery.
- Object source → separate backup → fresh restored directory is a second round
  trip. Keys/lengths/hashes match restored Storage metadata. Invalid/missing bytes,
  traversal, symlinks, duplicate keys and occupied destinations fail. Interrupted
  copies have no complete receipt; retry refuses that destination. No Storage API,
  actual PDF/video validation, authorization activation or hosted retrieval is proved.
- Only a final `receipt.json` marks a complete database drill; `plan.json` identifies
  retained new databases if a stage fails. Object recovery requires a valid
  `recovery-complete.json` and verified manifest bytes. Earlier failed/partial
  artifacts remain available. No worker, scheduler or provider is started.

Database success must never hide a failed/missing object artifact. Before enabling
any recovered service, recheck current grants/revocations and authenticate afresh;
restored old sessions/grants must not resurrect withdrawn authority. Restore into
an isolated destination first, fence outbound delivery, and reconcile queued or
uncertain exports/uploads with actual external state before any explicit replay.

## CI and cost boundary

No previous workflow existed. `.github/workflows/checks.yml` uses a standard
`ubuntu-24.04` GitHub-hosted runner only when the repository is public, a SHA-pinned
official checkout action with persisted credentials disabled, and a digest-pinned
official PostgreSQL17 test container. Repository visibility and existing Actions
enablement were verified2026-10-16; no billing/payment/settings change was made.
[GitHub's current billing policy](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
states standard hosted runner use is free for public repositories. The job skips
before runner allocation if visibility becomes private. No larger/self-hosted
runner, cache, artifact upload, deployment, secret or privileged PR trigger is used.
Container credentials are public synthetic fixtures, valid only in that job.

The pipeline runs existing portable export/gateway/relay tests, object recovery
tests, fresh migrations and synthetic database restoration. It does not claim
full pgTAP, native media parser, Xcode, real Auth/Storage, Google or hosted recovery
coverage. Native26.4 CI remains deferred until its runner/toolchain is established.
Local command results, YAML validity and actual remote execution are separate in
TESTING.md. PostgreSQL uses the PostgreSQL license; official image-build scripts
and checkout use MIT. Container OS packages retain their upstream licenses. No new
development-tool dependency was installed on the owner's Mac.

## Release rollback / forward fix

1. Identify the app build/source, backend migration tip, configuration revision,
   affected records and last known good artifacts. Preserve current bytes, errors,
   permissions/history and unsaved work. Fence outbound workers; do not erase data.
2. Determine compatibility before replacing an app binary. Prefer additive backend
   fixes that support both installed clients; preserve RPC shapes, UUIDs, nil/zero
   semantics and expected-revision guards. If a prior app cannot read current local
   or shared schemas, stop that downgrade and prepare a compatible forward fix.
3. A Git revert changes code, **not database or local records**. Do not run destructive
   down migrations, recreate a team/owner, reset a provider or restore an old database
   over current state. Data repair/recovery is separately reviewed, owner-authorized
   and rehearsed in an isolated destination with identified divergence/loss.
4. Before reopening access, verify row/object completeness, UUID relationships,
   accepted pointers/history, missing/zero, RLS/grants and current revocations. Check
   fresh sign-in, denied/stale commands, draft Save/reopen and the affected UI path.
   Reconcile external Sheets/object effects before explicitly resuming a worker.
5. Record tested scope and remaining limits. Obtain separate release/production
   authorization; this runbook or a green synthetic job grants neither.

## Owner decisions still open

- `TODO_BACKUP_DESTINATION`: private encrypted location, access holder and verified $0 arrangement.
- `TODO_BACKUP_RETENTION`: frequency, retained versions and expiration/deletion policy.
- `TODO_RECOVERY_RPO_RTO`: acceptable data loss and downtime, including authorization changes.
- `TODO_SECURITY_REPORTING_CHANNEL`: private incident/reporting route and responsible recovery contact.

No defaults were invented. [Supabase's backup guidance](https://supabase.com/docs/guides/platform/backups)
distinguishes database backups from Storage bytes and recommends independent Free
project exports. Its [CLI recovery procedure](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)
requires provider-specific handling; this synthetic drill does not verify it.
