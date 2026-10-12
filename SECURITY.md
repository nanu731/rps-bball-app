# TeamStats security boundaries

Reviewed 2026-10-12 against integrated source through `e7b119e` and reviewed file UI. This is a control/verification
map, not a certification. Read [ARCHITECTURE.md](ARCHITECTURE.md)'s source map,
[PRD.md](PRD.md), and [backend contracts](supabase/README.md) for detail.

## Assets and trust

Protect accounts/sessions, roster identities, unpublished and accepted statistics,
private plays/media, permission grants and audit history. Treat clients, numeric
forms, image text, external links and writable account metadata as untrusted.
The Data API verifies signed tokens; SQL checks the live account/session and current
team authority. Trusted provider administration is a separate privilege boundary.

| Actor | Authority boundary |
|---|---|
| Unauthenticated account / nonmember | No access to protected team records |
| Verified pending member | Admission request is not membership approval |
| Active member | Authorized viewing and permitted contribution; publication/review are separate |
| Capability holder | Only granted operations; no implicit power to grant capabilities |
| Delegate | Enumerated grantable capabilities, team scope and finite expiry; no self-escalation, onward delegation or owner replacement |
| Owner | Team administration and protected review within the documented contract; immutable owner identity |
| Trusted setup/export administrator | Privileged bootstrap/worker access outside the app, never via client secrets |

## Database and command enforcement

Migration 001 establishes membership, roster history, grants, delegation and audit.
Subsequent migrations implement reviewed statistics, exports, plays and media.
App tables enable RLS and have explicit grants. Direct client table writes are
revoked; fixed-search-path commands derive the actor from verified server identity,
check current authorization, and enforce expected revisions and transaction rules.
Sensitive decisions wait for a successful server reply.

Owner bootstrap requires trusted verification of the actual account and live session;
email/phone/role fields submitted by a client cannot establish ownership. Inspect
existing schema/history before activation; do not run resets or unreviewed dashboard
rewrites. Migration-history schema privileges/exposure must be checked explicitly;
the SQL editor's RLS warning is not proof of public exposure or permission safety.

Accepted versions and historical roster identities survive revisions/archival.
Reopening needs approved authority; publication bypass is not an editing exemption.
Audit events accompany the enforced commands. See [statistics](supabase/statistics.md),
[plays](supabase/plays.md) and [media](supabase/media_resources.md) for contracts.

## Credentials, device data and revocation

Protected administrator identification uses the team-scoped
`team_administrator_identities` command. Current owner, membership administrator or
bounded delegate authority is checked on the server; only existing same-team
memberships are returned. Email and phone appear only when independently confirmed
in trusted Auth fields. Missing contacts retain the Auth UUID fallback; writable
metadata never confers identity or authority. Ordinary members cannot request this
private contact list. Confirmed denial clears the native protected snapshot;
other contact-load failures offer Retry without impersonating an empty team.

Only project URL/publishable configuration may enter the native client. Privileged
database, Supabase, Google and sender credentials stay in trusted configuration,
never source, URLs shared publicly, logs or handoffs. Build environment variables
do not hide secrets bundled in an app.

[SecureSessionStorage](TeamStats/TeamStats/SecureSessionStorage.swift) uses
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, with synchronization disabled.
Auth callback uses a device-bound PKCE challenge and verified identity. Provider
configuration, delivery/recovery limits and real revocation behavior still require
hosted verification; a successful sign-in proves none of those permission tests.

Connected server denial conceals affected content and requires authorized recovery.
Do not describe that as proof that all downloaded data has been securely erased.
In-memory buffers, account switching, backgrounding and process termination need
device checks. Local legacy JSON is a separate store; atomic writes protect write
integrity, not confidentiality. OS/file protection and backup behavior remain to be
verified. No automatic upload or migration of existing local data is permitted.

## Untrusted input and integrations

- Validate counts/IDs/allowed fields/revisions on the server as well as the client.
  Bound batches and responses; parameterize operations rather than constructing SQL
  from user values. Draft missing values must not be silently normalized to zero.
- On-device OCR produces proposals, not authority. Bounded photo reads and explicit
  mapping/confirmation precede changes; applying a proposal does not save/publish.
- Keep media review private. A reviewed link does not establish ownership, upload
  security or private playback. Private uploads use immutable reservations, deny-all client bucket policies,
  trusted actual-byte validation and concurrency-safe aggregate admission.
  Hosted capacity/configuration remains unverified and fails closed.
- Export worker credentials are server-only. Versioned receipts/fences prevent
  older deliveries from becoming latest accepted data. Google delivery is disabled;
  fixture tests are not Google authorization/delivery evidence.

## Open acceptance gates and cost boundary

The strict budget is $0. SMS and external sender/Google delivery are not activated;
no paid plan, overage commitment or new service is implied by documentation.
Verify actual nonproduction RLS/grants, anonymous/nonmember denial, bounded
delegation, stale commands, session revocation, and approved corrections after
trusted activation. Test with distinct synthetic accounts, not destructive changes
to the real owner or student records. Audit logging exists locally; hosted evidence
and operational monitoring remain separate work.

No browser HTML frontend, cookie-based web session or payment flow exists here;
web headers/CSRF/payment controls are conditional, not passed native-app checks.
See [TESTING.md](TESTING.md) for evidence and release gates. Production/release
requires separate owner approval.

## Private security reporting and recovery responsibility

`TODO_SECURITY_REPORTING_CHANNEL`: the owner must choose a private reporting
route before external pilot use. No contact is invented here, and GitHub private
vulnerability reporting is not claimed enabled. Until a route is published, do
not post credentials, student records, private provider identifiers or exploit
details in public issues. Provide a minimal sanitized description through an
owner-approved private channel once available; share sensitive evidence only by
an explicitly agreed secure method. No response-time promise is established.

The owner coordinates incident response and approved restoration with trusted
provider administrators. Ordinary membership, review or delegated grant authority
does not authorize database access/restore. Identify and contain the affected
scope, preserve evidence privately, and rotate/revoke an exposed credential before
coordinated cleanup. No unapproved record deletion, provider reset or public
disclosure follows automatically from a report.

See [architecture recovery boundaries](ARCHITECTURE.md#backup-and-recovery-boundary).
Local-data protection/backup behavior, account-switch retention and restore testing
remain open. `TODO_BACKUP_RECOVERY_POLICY` must identify an approved operator,
retention/recovery objectives and a $0-compatible verified method; documentation
must not imply paid provider backups or tested disaster recovery.

## Maintenance

Commit metadata is public separately from file contents. Use the owner's verified
GitHub noreply identity for future commits; check both effective author and
committer email, including environment/agent overrides, before committing/pushing.
Changing future configuration does not remove previous metadata or hide the author
name. Historical identity remediation requires a private inventory, coordinated
preservation plan and explicit approval before rewriting refs or force-pushing.

Update this document when grants, authentication/session storage, privileged
commands, data retention or external upload/export boundaries change. Link test
evidence rather than claiming protection from UI restrictions or provider defaults.
Keep private identity/setup/evidence out of public documentation and commit only
explicit reviewed paths.

## Private files and retained clips — current boundary

Practice clips and scouting PDFs have separate capabilities; scouting publication
requires owner review. Only eligible authors may use their own clip-publication
bypass. Exact immutable versions, live sessions and current published visibility
are checked before transfer. Unknown capacity denies admission. Failed/interrupted
uploads and retained history remain charged; expiry does not free occupied bytes.
The development limits are10MiB/30 seconds/H264 with optional AAC/1080p and5MiB PDF,
not proof of the team's actual workload or hosted Free-tier feasibility.

The trusted local validator checks self-contained MP4 references and full decode;
PDF graph inspection and bounded rendering reject active/encrypted/malformed inputs.
Process containment and response sanitization are tested, not exhaustive hostile
fuzzing or OS-decoder resource certification. All original/new local runtime
listeners were audited loopback-only; privileged configuration remains private.

Retained clips are hash-verified and scoped to a previously server-verified actor.
Restore also requires the saved session and actor stamp to agree. Sign-out/known
Auth denial clears memory and durably locks the stamp; failed writes independently
attempt removal of the session and stamp. If both writing and removals fail, the
app reports a storage error but cannot guarantee a durable lock after restart;
device secure-storage recovery is required. Files are preserved, not remotely
recalled. Offline rights may be unknown and are explicitly disclosed. Current
remote access always requires server authorization. Full app/device acceptance
of these states remains pending separately from model tests.
