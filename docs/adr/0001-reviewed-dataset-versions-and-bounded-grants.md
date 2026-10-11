# Reviewed dataset versions and bounded grants

Adopted through the owner-authorized Council on 2026-10-11. Authentication,
active team membership, roster identity, operational capabilities and delegated
grant authority are separate. Published data is visible to active team members;
pending proposals are visible to their author and relevant reviewers.

Use separate stats review/publication, completed-dataset reopening, roster and
membership administration, and play/practice-film/game-film capabilities. Owner
delegation enumerates grantable capabilities, team scope and expiry; it permits
no self-grants, onward delegation or owner replacement. Authority is checked by
the server when each command commits, with an audit event. Possessing an
operational capability does not confer authority to grant it.

Each team's possession sheet, our-player box scores and player paint-touch totals
are independently completed/versioned. Entry completion, review and publication
remain distinct. Completion confirms game/covered roster and valid entered data;
optional box-score/player-total blanks remain missing. Added possession numeric
blanks become zeros only through the confirmed completion command and per-user
warning preference. New completion requires answered turnovers; historical nil
answers remain unchanged until explicitly corrected with authority.

Accepted versions are immutable. Approved edit requests open revisions without
hiding published data; expected-version checks reject stale saves/approvals.
Ordinary publishing bypass never bypasses completed-dataset edit approval.
Publication, audit and a versioned export job commit atomically. Sheets export
must not allow an older retry to replace a newer accepted version.

Explicit temporary identities are excluded from official publication/export and
are never converted or reused for actual players. No automatic upload of local
records. Missing inputs and zero denominators remain honest in calculations.
Repeated paint-touch counting remains unresolved; no inferred player attribution.

These are adopted design defaults, not evidence of implemented server security.
Both email and phone account lifecycles and provider costs require verified
configuration/tests before production. No release/deployment approval is implied.
