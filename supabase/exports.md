# Accepted-version Sheets export

Source implementation and synthetic checks are available. Google delivery is
**disabled by default**. No Google credentials, hosted worker, schedule, billing
verification or live Sheet write has been established by this slice. Supabase is
the authoritative source; spreadsheet edits never update the app. Local records
and temporary player identities are never imported by this worker.

## Server interface

Migration `202610110003_stat_exports.sql` depends on the existing team-access and
stat-version migrations. It adds immutable canonical accepted snapshots plus
separate reservation/delivery state. An outbox insertion captures the accepted
version, game metadata and referenced historical roster labels in the same
publication transaction, without requiring a configured destination. Existing
accepted outbox facts are backfilled without modifying old versions or jobs.
Drafts, completed entries and pending proposals never become export jobs.

The payload is the exact UTF-8 `payload_text` emitted by PostgreSQL's `jsonb::text`,
with its SHA-256. The worker hashes those bytes, rather than reserializing JSON.
Missing counts display `Not entered`; explicit zero displays `0`. Snapshot tabs
contain metadata and a human-readable box-score/player-total/possession grid.
Historical names/jerseys come from the accepted roster revision, not the current
roster label. Inputs, labels, numbers and ledger data use literal `stringValue`.
Formula-like labels cannot become formulas.

| Command | Trusted parameters and behavior |
| --- | --- |
| `stats_export_configure` | `p_team_id`, `p_spreadsheet_id`, `p_ledger_sheet_id`, `p_snapshot_min`, `p_snapshot_max`, `p_ledger_rows`; immutable trusted team-to-Sheet mapping and bounded disjoint reservations; exact configuration retries are safe; rebinding fails |
| `stats_export_jobs` | `p_limit` (1–10; default 3); pending/reserved/failed job IDs, no delivered jobs |
| `stats_export_reserve` | `p_job_id`; returns full accepted UUID, canonical payload/hash, immutable destination, distinct nonnegative `sheet_id`, reserved zero-based ledger row and state; retries return the same binding |
| `stats_export_finish` | `p_job_id`, `p_receipt`; receipt must exactly contain the accepted UUID/hash/destination/sheet ID/ledger row returned by reserve; only the trusted worker may attest verified readback |
| `stats_export_fail` | `p_job_id`, `p_error_code`; fixed sanitized code, same job stays retryable; late failures do not undo delivered state |
| `stats_export_status` | `p_team_id`; live authenticated owner session only; versions, generation, queued/reserved/failed/delivered, attempts, safe error code and delivery time |
| `stats_export_latest` | `p_team_id`; live owner only; greatest accepted publication generation independently per game/dataset, including truthful pending state |

Worker commands are revoked from PUBLIC, anonymous and authenticated clients;
only `service_role` can execute them. Destinations/payload tables have no client
read/write access; owner delivery-table reads expose only status columns through
RLS and require current session/membership. The service credential has broad
backend privilege and must remain on the trusted runtime; an export-only service
identity remains a future hardening/deployment requirement. No service token or
Google credential belongs in iOS, source, logs, ordinary JSON configuration or a
handoff. This slice does not activate a hosted service identity.

## Write fence and verified receipts

Every accepted version receives a distinct database-reserved snapshot ID and
nonoverlapping ledger row. Allocation serializes on the team and never derives an
ID from a truncated UUID/hash. One team owns one destination; sharing a destination
between teams is refused. Exhaustion fails explicitly without recycling IDs.

One Sheets batch includes explicit-ID `AddSheet`, snapshot cells and the reserved
ledger row. `AddSheet` duplicate-ID rejection fences the whole atomic batch;
there is no Sheets current-cell compare-and-swap. Existing IDs are only read and
compared, never rewritten. The worker checks observed ledger collisions, existing
snapshot identity, expected bounds and the fixed latest-view prerequisite.
Full snapshot cells and the ledger receipt must equal the accepted UUID, payload
hash and expected grid before acknowledgement. HTTP success alone is insufficient.
Timeouts/concurrent duplicates may recover by bounded full readback; mismatches
remain conflicts on the same job. Old jobs never write newer snapshot locations or
replace a shared latest pointer. A matching ledger observed during a concurrent
same-job completion triggers readback rather than another write.

Collaborators can still modify/delete Sheet exports, and Google offers no atomic
condition over their unrelated writes. Restrict automated writers and protect
these ranges operationally. Observed collisions fail; concurrent outside editor
writes cannot be absolutely fenced by this protocol. Delivered status records
verified delivery at that time, not permanent tamper-proof storage. Supabase
accepted history remains authoritative.

## Fixed latest view

Before enabling delivery, the trusted operator must prepare a private destination
with a `TeamStats Ledger` tab at the configured ledger sheet ID and at least the
configured row capacity/eight columns. Row 1 contains these literal headers:

`Game ID | Dataset | Generation | Accepted version | Payload SHA-256 | Sheet ID | Snapshot tab | Revision`

The allocated snapshot-ID range must exclude all existing tabs (including the
ledger and latest-view tabs). The destination must also have a `TeamStats Latest`
tab with this exact static formula in **A2**, as exported by `LATEST_FORMULA`:

```text
=IFERROR(LET(entries,FILTER('TeamStats Ledger'!A2:H100001,'TeamStats Ledger'!A2:A100001<>""),ordered,SORT(entries,1,TRUE,2,TRUE,3,FALSE),keys,ARRAYFORMULA(INDEX(ordered,0,1)&"|"&INDEX(ordered,0,2)),FILTER(ordered,ARRAYFORMULA(MATCH(keys,keys,0))=SEQUENCE(ROWS(ordered)))),"")
```

The worker only verifies this formula; delivery jobs never write it. The projection
sorts game/dataset and descending fixed-width 20-character decimal generation,
then selects the first row per game/dataset. This avoids floating-point conversion
of bigint generations. No dynamic user value is interpolated into a formula. The
projection identifies latest **delivered** snapshots; the server latest command
identifies latest **accepted** versions and reports undelivered state. Those are
different during delivery lag. Isolated Google calculation/newest-first readback
passed with the repaired formula below; loopback fixtures test prerequisites and
SQL tests verify the server projection. Automated worker delivery, operational
destination capacity and collaborator behavior still require acceptance.

## Trusted runtime and budget gate

`sheets_export.py` uses Python 3.11+ and standard-library `urllib` for actual HTTPS
transport. Its callable interface is `run_once(backend, google, max_jobs=3)`; one
run handles at most three jobs, one atomic batch/job, and at most 20 Google
requests (default 16). Requests time out within 30 seconds (default 15); payloads
are bounded to 1.9 MB and reads to 2.1 MB. Oversized accepted datasets fail visibly
instead of being truncated. Redirects are refused. Backend/provider error bodies
are never logged. Quota/timeouts remain failed/retryable; no unbounded retries or
scheduler is installed. A later trusted scheduler may invoke bounded runs with
backoff, using current credentials and the same persisted reservations.

Private runtime JSON requires `backend_rest_url`; `google_enabled` defaults to
false. To explicitly enable Google, the operator must verify billing is absent or
disabled, current API policy/quotas and the strict zero-charge condition, then
supply `google_enabled: true` (literal Boolean only; other types are refused) and a timezone-aware
`billing_disabled_verified_at` timestamp no more than 24 hours old. This is an
operator attestation, not automatic proof of account billing state. Credentials
are injected into `TEAMSTATS_EXPORT_SERVICE_TOKEN` and
`TEAMSTATS_GOOGLE_ACCESS_TOKEN` by the trusted runtime; the worker does not obtain,
refresh or log OAuth credentials. Expired tokens fail truthfully. The initial
private Sheet exists separately, but is not configured/edited by this slice.
No quota increase, billing account, paid plan, cloud runtime or Google write is
approved or performed here. Current pricing must be rechecked before activation.

## Evidence and remaining integration

Actual local PostgreSQL 17.11: 54 pgTAP assertions passed with synthetic
transactional fixture users/sessions. Tests cover client RPC/table denial, live
owner access, publication-only queueing, immutable payloads, historical labels,
missing/zero, stable retries, disjoint bounded ranges, binding/hash acknowledgement,
visible failure, receipt idempotency and latest accepted generation. All synthetic
SQL fixtures roll back; preexisting records remain intact. Multi-connection
reservation timing has not been measured by this SQL test.

Twenty Python standard-library tests pass using actual loopback HTTP/urllib and
an explicitly synthetic Google protocol fixture. They exercise same-version
races, newer-before-older disjoint writes, timeout-applied recovery, timeout retry,
existing-ID/false-hash/cell and ledger conflicts, partial/quota errors, literal
formula-like content, latest-view preflight, bounded requests, disabled/expired
budget evidence and backend success/failure recording. These are contract fixtures,
not Google integration evidence. The later isolated calculation check below is
actual Google evidence. Worker credentials, billing proof, worker batch/readback,
hosted service setup and scheduler/backoff remain open. Native status presentation
is implemented; rendered acceptance and production deployment are separate gates.

Protocol references: [atomic batches](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/batchUpdate),
[explicit AddSheet IDs](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/request#AddSheetRequest),
[bounded spreadsheet reads](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/get),
[SORT](https://support.google.com/docs/answer/3093150),
[FILTER](https://support.google.com/docs/answer/3093197),
[Sheets limits and current billing policy](https://developers.google.com/workspace/sheets/api/limits).

## Actual formula acceptance — 2026-10-13, c06c7a7 plus formula repair

An isolated private Google Sheet with synthetic rows exposed a calculation defect:
the earlier unwrapped key concatenation selected only the first game/dataset group.
Wrapping that concatenation in `ARRAYFORMULA` returned all three tested groups.
Actual Sheets readback verified a newer correction, late older rows, an identical
row retry without duplication, and exact maximum-bigint generation text. The failing
formula and six synthetic history rows are retained privately; the operational
destination, permissions and automated delivery remain unchanged. All20 affected
worker protocol tests passed; those HTTP fixtures do not execute Google's formula
engine. This is destination calculation evidence, not automated export acceptance.
