# Connected statistic versions

The authenticated RPCs below derive the author from a verified live Auth session
and recheck active membership and current capabilities while holding the team
lock. Clients cannot write these tables directly. Statistical revisions are
independent of the team's administration `access_revision`.

## Interface

Every argument below has the `p_` prefix. UUIDs are JSON strings. Dataset types:
`box_scores`, `our_possessions`, `opponent_possessions`, `player_paint_touches`.

- `stats_create_game(team_id, game_id, date, opponent, home_away, game_type)`:
  date is `YYYY-MM-DD`; home_away is `home`/`away`; game_type is
  `regularSeason`/`playoff`. A caller-owned stable game UUID makes identical
  retries idempotent. Changed metadata under the same UUID fails with `PT409` (HTTP 409).
- `stats_open_draft(team_id, game_id, dataset_type)`: returns the author's
  existing draft on retry. Completed data needs an approved edit request.
- `stats_save_draft(team_id, version_id, expected_revision, records,
  covered_roster = [])`: replaces the complete record batch atomically. A
  repeated save using its old revision fails with `PT409` (HTTP 409), so a caller must
  reload after an ambiguous network result. Draft contradictions remain saved.
- `stats_save_drafts(team_id, items)`: an atomic batch returning a version array.
  Items are `{version_id: UUID, expected_revision: Int, records: [...],
  covered_roster: [...]}` (`covered_roster` defaults to `[]`). Pass one to four
  unique editable versions, such as both independently numbered possession
  sheets. Any stale/invalid/unauthorized item rolls back every item and audit
  event. Total JSON stays within 4 MiB; possession record counts are uncapped.
- `stats_complete(team_id, version_id, expected_revision,
  confirm_roster = false, confirm_numeric_zeros = false,
  suppress_numeric_warning = false)`: box/paint completion requires explicit
  roster confirmation. Possession blanks become zeros only on explicit
  confirmation or this author's previously confirmed suppression preference.
  Suppression is saved only as part of a successful confirmed completion.
- `stats_submit(team_id, version_id, expected_revision)`: completed author data
  enters the relevant review queue.
- `stats_publish(team_id, version_id, expected_revision)`: author publication
  requires `stats.publish` or ownership. It never allows editing completed data.
- `stats_review(team_id, version_id, expected_revision, approve,
  reason = '')`: submitted data requires `stats.review` or ownership; ordinary
  reviewers cannot approve their own submission. Rejecting data keeps it frozen.
- `stats_request_edit(team_id, source_version_id, expected_revision,
  reason = '')`: active viewers of published data or authors of their own
  completed data may request a revision. Identical open requests are idempotent.
- `stats_review_edit(team_id, request_id, expected_revision, approve,
  reason = '')`: requires `datasets.reopen` or ownership; ordinary reviewers
  cannot approve their own request. Approval returns a new author-owned draft
  copied from the authorized source and never overwrites an existing draft.
- `stats_preferences(team_id)`: returns `{suppress_numeric_warning: Boolean}`
  for the authenticated user only.

Version-returning commands return an object with `id`, `team_id`, `game_id`,
`dataset_id`, `dataset_type`, `author_user_id`, `revision` (positive integer), `status`
(`draft`, `completed`, `submitted`, `rejected`, `published`), `records`,
`covered_roster`, `base_published_version_id`, `created_at`, `updated_at`,
`review_actor_user_id`, `review_reason`.
Edit request commands return the request row (`id`, `team_id`,
`source_version_id`, `requester_user_id`, `revision`, `status`, `reason`,
`review_reason`, `working_version_id`, timestamps); approved `stats_review_edit`
returns `{request: <row>, version: <version>}`; rejection has `version: null`.
Game-returning commands return `id`, `team_id`, `date`, `opponent`, `home_away`,
`game_type`, `publication_generation`, `created_by`, `created_at`.

## Record format

All records are JSON arrays with the existing native field names. Unknown
fields, role/publication metadata, duplicate players/possession IDs/numbers,
wrong game/team/roster IDs, temporary IDs, fractional/negative/overflow counts
are rejected. Counts fit Swift `Int` (0 through 9223372036854775807). Missing
keys and JSON null are preserved during saves; zero is explicit. A 4 MiB JSON
request ceiling guards resource abuse; there is no basketball possession cap.

Box score: `{gameID: UUID, playerID: UUID, values: {...}}`. The allowed values
are `points`, `offensiveRebounds`, `defensiveRebounds`, `assists`, `turnovers`,
`steals`, `blocks`, `fouls`, `chargesDrawn`, `twosMade`, `twosMissed`,
`threesMade`, `threesMissed`, `freeThrowsMade`, `freeThrowsMissed`.

Paint touch: `{gameID: UUID, playerID: UUID, total: Int?}`. Covered roster for
box/paint is `[{id: UUID, version: Int}]`; each entry references a real player
and an existing immutable roster revision on this team. On completion, its
player set must equal the record player set and cannot be empty. Optional
measurements stay missing. No roster record is manufactured by the server.

Possession: `{id: UUID, gameID: UUID, team: 'ours'|'opponent', number: Int,
values: {...}, turnover: Boolean?}`. The allowed values are `paintTouches`,
`offensiveRebounds`, `twosMade`, `twosMissed`, `threesMade`, `threesMissed`,
`freeThrowsMade`, `freeThrowsMissed`. Each dataset contains one team's
independent contiguous 1..n numbering. Empty sheets cannot be completed. Every
added record needs Yes/No turnover to complete; drafting preserves historical
unanswered values. Conversion only fills numeric blanks of existing records;
no empty paired cells or placeholders are created.

Scoring contradictions and derived overflow block completion while leaving the
draft intact. Exact scoring comparison requires points and all three makes;
otherwise only a proven entered-makes lower-bound contradiction blocks it.

## Reads, conflicts, and delivery

Authenticated clients may select `games`, `stat_datasets`, `stat_versions`,
`stat_edit_requests`, `stat_user_preferences`, and `stat_export_outbox` under
RLS. Drafts and unsubmitted completed versions are author-private. Submitted
and rejected proposals are visible to their author and relevant stats reviewers.
Published history is visible to active team members and immutable. Removed,
nonmember, expired and revoked-session actors cannot read even their own data.
Pending edit requests also expose their frozen source to `datasets.reopen`
reviewers so a decision can be based on the actual data. Edit request review
is scoped to `datasets.reopen`; export outbox reads require
ownership. Read current accepted records via a dataset's `published_version_id`.

All mutation commands use the entity's `expected_revision`; stale operations
fail `PT409` (HTTP 409). Forbidden access uses `42501`; invalid collected data uses `22023`.
Publication additionally compares the draft's captured published base with the
current accepted pointer under the game lock. Acceptance advances a per-game
publication generation and inserts exactly one immutable outbox item for the
accepted version, together with the pointer and append-only audit event.
An older proposal cannot overwrite a newer acceptance. Outbox delivery to Google
Sheets is not implemented by this migration, and no hosted integration is claimed.

## Verification

On 2026-10-11, the migration executed on the approved disposable native local
Supabase Postgres 17.11 runtime. `supabase/tests/stat_versions.sql` passed all
136 pgTAP checks through bundled `pg_prove`. Tests use synthetic fixture identities
and transactions that roll back, covering authenticated public commands, actual
RLS reads, missingness, strict validation, atomic batches, completion confirmation,
review/reopening, accepted history/outbox, stale bases and live access revocation.
The game/batch public-command tests were observed failing before those commands
were applied. These SQL checks do not prove hosted deployment, real delivery,
physical-device behavior, or Google Sheets export.

## Explicit stale-draft recovery (migration009)

Apply `202610110009_stat_draft_recovery.sql` once after the existing lifecycle
migration; earlier migrations stay unchanged. A captured authenticated regression
showed that approval of a current V2 edit was blocked by an author's unfinished V1
draft. The missing-turnover draft could not honestly be marked complete to free
the slot.

An authorized current-source edit approval now retains only a **stale-base**
requester's saved draft as read-only `superseded`, preserving records, covered
roster and historical missing answers exactly. It creates the normal approved
working copy from the authorized current source and records immutable nullable
`recovery_source_version_id`. Same-base unfinished drafts still reject approval.
Superseded is not completion and cannot request completed-source edits. Accepted
pointers, export generations and existing rows are unchanged by recovery; no
historical backfill, zero conversion, approval bypass or deletion occurs.

The native model accepts this read-only status and verifies each recovery link
against an approved edit request, current author/game/dataset and accepted base.
Missing, forked, cyclic, unapproved or revoked-access snapshots fail closed. After
explicit Reload, the entry screen separately confirms attaching retained buffers:
only its server-version metadata changes. Typed values, missing answers, paired
rows and historical roster labels remain until explicit Save. An uncertain
approval is never automatically replayed. Existing photo review wiring is intact.

Verification: the SQL red case failed with40001, and the native pre-fix read test
failed on the unknown saved status. Migration009 then passed37 actual rollback
PostgreSQL checks, including unchanged records/outbox, same-base denial, readonly
history, revoked reviewers and expired-session denial. The original136 lifecycle
checks also passed after the shared trigger/command repair. Swift syntax parsing
passed; affected native fixture/build checks are assigned to the integrator.
Actual attachment/keyboard/navigation interaction remains unverified.
