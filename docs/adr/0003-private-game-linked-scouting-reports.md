# Private game-linked scouting reports

Adopted through the owner-authorized Council on2026-10-12: five independent
analyses, five fresh reviews of anonymized proposals, and chairman synthesis.
Use PDF only, at most5 MiB, linked to an existing same-team Game UUID (including
future games). This avoids a second opponent directory and a second identity
source. Separate `scouting.upload` and `scouting.read` capabilities identify
eligible contributors/viewers; a coach label or ordinary membership grants
neither. Active uploaders inspect their own pending submissions, and the owner
inspects all. Publication requires owner approval; current published viewing
requires active membership plus read authority (or owner authority).

Replacements create immutable versions; the previous publication stays current
until atomic, expected-version-checked approval succeeds. Archive hides normal
view/download while retaining bytes/history; archived/history retrieval is
owner-only initially. No automatic expiry, deletion or reuse of old object IDs.
Recheck live authority at finalization, publication and each retrieval. Avoid
persistent bearer links; bytes already delivered cannot be recalled.

The file ceiling is a product limit, not provider capacity/$0 evidence. Trusted
aggregate storage and transfer limits must be established from actual available
capacity before activation, counting pending/reserved/retained/orphaned bytes.
Fail closed when capacity is unknown or full. Idempotent upload identities and
atomic reservations protect concurrent/retried transfers; uncertain byte success
requires reconciliation rather than automatic deletion/re-upload.

Native selection/validation and server lifecycle source/tests may proceed with
synthetic inputs. Only authoritative validated, durably stored private bytes can
establish an upload. Client checks, metadata and fake receipts cannot. Actual
private storage/validation/retrieval/quotas, report rights and cost acceptance
remain gates; extra local Storage tooling is unapproved. These defaults introduce
no live grants, hosted migration or provider activation. The nine deployed
migrations remain unchanged. PDF structure/readability/encryption checks must
also be enforced by trusted infrastructure; local validation is preparation only.
