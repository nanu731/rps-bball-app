# Web sessions and explicit clock authority

Adopted implementation direction, 2026-11-11; activation and acceptance are separate.

The web pilot adds practice plans/results and game capture alongside existing,
independent manual-statistics datasets. Existing `practice.*` permissions govern
videos and confer no practice-collection authority. New `sessions.*` capabilities
must be explicit, default-denied, and checked against the live verified Auth
session, active team membership and current grants inside each transaction.

Use bounded, discriminated JSON snapshots with strict server validation rather
than new tables/RPCs for every coach-defined drill. Snapshot the roster revisions,
plan, nine configured spot labels and collection definitions. Counts remain
missing or explicit zero; makes cannot exceed attempts. Our shots require a real
team roster identity; opponent attempts are team-only. Free throws have no court
location. Event/correction identities, original readings and append-only history
must survive saves, corrections and Undo. A whole-document replacement must not
bypass these rules. Local identities are never imported automatically.

Keep clock authority outside editable snapshots. One explicitly assigned recorder
controls a server-anchored reference clock, with expected clock revisions and an
assignment fencing token. Handoff invalidates previous writers. Captured readings
remain historical observations; later clock corrections never rewrite them and
this clock is not synchronized with an official scoreboard.

Submission freezes an exact snapshot. Authorized independent review/publication
advances an accepted pointer transactionally, retaining prior publications.
Approved correction requests create a new working proposal. Accepted shared
results never include pending/local observations or double-count manual totals.

Mutations retain a stable operation ID and payload binding. Identical retries
return the original authorized receipt; changed payload reuse conflicts. Receipt
lookup rechecks current authority, preventing old IDs from revealing denied data.
Uncertain replies require receipt/readback reconciliation before another command;
no universal exactly-once delivery or general offline synchronization is promised.

Five independent Council lenses favored this approach over per-field normalized
infrastructure or documentation-only preparation. Peer reviews used anonymized
compact excerpts, not full originals; this limits the review process. They added
current-authority receipt lookup, atomic publication, append-prefix validation and
reversal integrity as explicit checks. No hosted migration, grants, bootstrap,
provider activation, delivery or release is authorized by this decision.
