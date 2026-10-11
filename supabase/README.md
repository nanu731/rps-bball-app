# Local team access slice

This directory contains a Postgres migration and synthetic behavior tests for
team membership, capabilities, bounded owner delegation and roster history.
It is a source draft until it has run against actual Supabase Auth/Postgres.
No hosted configuration, real owner identity, student data or automatic local
record upload is included. This slice does not implement shared statistical
submissions, completion, publication, exports, plays or media storage.

The strict budget is $0. The configuration is for a disposable local runtime:
email is captured by the local inbox, real SMS providers and delivery hooks are
disabled, and one reserved fictional phone number has a local test code. That
code is not SMS-delivery evidence. Default local email may contain a magic link;
typed email OTP template parity remains unverified. The pinned native runtime
rejects custom email-template `content_path`, so this draft does not enable it.
The setting names follow the [official v2.120.0 template](https://github.com/supabase/cli/blob/v2.120.0/apps/cli-go/pkg/config/templates/config.toml),
including `local_smtp`; actual CLI validation is still required. Do not apply this configuration to a hosted
project or enable paid providers. Native CLI installation and runtime
setup require owner approval; neither is installed by this source draft.

## Trust and bootstrap

The trusted server administrator must first verify the actual owner's account
in Supabase Auth. Only then may that administrator insert a team with its
`owner_auth_uuid` set to that verified Auth UUID. The insert verifies the account,
creates its active membership and records the bootstrap audit event atomically.
There is deliberately no authenticated team-create or owner-bootstrap RPC. Email,
phone, user-submitted roles and writable account metadata cannot establish owner
identity. Do not put the real UUID or administrative credentials in this file.

Owner UUIDs are immutable and owner membership cannot be removed or downgraded.
All client table writes are revoked; administration goes through fixed-search-path
security-definer commands. Each mutating command serializes on the team, checks
its verified server session and current active membership, checks current grant
authority and the expected access revision, performs its change and appends an audit event in one transaction.
Expired/removed Auth sessions deny access even when a JWT has not expired yet.
The signed JWT is still validated by the Supabase gateway; callers cannot be
allowed to choose database claims themselves in a deployed runtime.

Operational capabilities and permission to grant them are separate. An owner
may grant/revoke capabilities for other active members. Owner-issued envelopes
allow a delegate to grant/revoke only enumerated capabilities in one team,
bounded by finite expiry. No self-grants, onward delegation or owner changes are
allowed. A delegated grant records its source envelope and becomes ineffective
when that envelope expires/is revoked or its delegate loses active membership.
Removing/downgrading a member revokes that member's old grants and envelopes;
readmission does not revive them. The owner retains all operational capabilities.

## Public interface

All commands require a verified, nonanonymous Auth account and a live server
session identified by the JWT `session_id`. Every command except admission
request also requires active team membership. Parameter names below are the
PostgREST RPC argument names; dates are finite timestamp strings and IDs are UUIDs.

| RPC | Parameters and result |
| --- | --- |
| `team_request_membership` | `p_team_id`; requests own pending admission, never activates it; own current status string |
| `team_set_membership` | `p_team_id`, `p_user_id`, `p_status` (`pending`, `active`, `removed`), `p_expected_access_revision`; owner or `members.manage`; void |
| `team_access` | `p_team_id`; own current `user_id`, `is_owner`, `can_propose_stats`, effective `capabilities`, current `grant_envelopes`, `access_revision`; JSON |
| `team_set_capability` | `p_team_id`, `p_user_id`, `p_capability`, `p_enabled`, `p_expected_access_revision`, optional `p_expires_at`; separate owner/envelope authority; void |
| `team_delegate` | `p_team_id`, `p_user_id`, `p_allowed_capabilities` (string array), `p_expires_at`, `p_expected_access_revision`; owner only; new envelope UUID |
| `team_revoke_delegation` | `p_team_id`, `p_envelope_id`, `p_expected_access_revision`; owner only; void |
| `team_save_roster` | `p_team_id`, `p_display_name`, `p_jersey_number`, `p_expected_access_revision`, optional `p_roster_id`, `p_expected_version`; `roster.manage`; roster UUID |
| `team_archive_roster` | `p_team_id`, `p_roster_id`, `p_expected_version`, `p_expected_access_revision`; `roster.manage`; void |

Every administration mutation requires the `p_expected_access_revision` captured
from `team_access` when the administration screen loaded. It has no default and
NULL cannot bypass the check. Under the team lock, a mismatch raises `40001` and
leaves membership, grants, roster and audit unchanged; reload before retrying. A
successful mutation increments `teams.access_revision` in the same transaction.
Bootstrap starts at 1. A new pending admission request increments it; an
idempotent admission retry leaves it unchanged. This revision concerns
administration; future statistical changes do not use it. Roster entry
`p_expected_version` remains an additional independent check.

`team_save_roster` without an entry ID creates a fresh real server UUID. Existing
entries require their expected version. Temporary IDs are never converted or
imported. Archive retains the entry and all immutable label revisions; archived
entries cannot be edited/reused. A future statistical reference should retain
both its roster UUID and the applicable roster version. No destructive roster
command exists.

Active members can read `teams`, `roster_entries` and `roster_entry_revisions`.
Memberships, capability grants and envelopes are readable by current authorized
administrators; audit events by the owner. Pending, removed, unauthenticated and
nonmember accounts have no team/roster data access. There are no published-data
tables in this slice; future published tables must apply the same active-member
read gate plus their version/publication rules. Active-member stats proposals
are a baseline access flag, not a publication permission or a submission RPC.

Capability names are `stats.review`, `stats.publish`, `datasets.reopen`,
`roster.manage`, `members.manage`, `plays.author`, `plays.review`, `plays.publish`,
`practice.upload`, `practice.review`, `practice.publish`, `film.upload`,
`film.review`, `film.publish`. Access failures use SQLSTATE `42501`, stale administration/roster
versions `40001`, and invalid command arguments `22023` (table constraints may
also return standard Postgres validation errors).

## Verification frontier

`tests/team_access.sql` exercises real SQL commands and RLS using synthetic Auth
users/sessions in a transaction that is rolled back. It is intended for Supabase's
local pgTAP runner. Its trusted fixture setup is test-only; it is not proof of real
email/phone verification or provider delivery. Before this migration exists, the
suite is expected to fail at the absent team table. No database execution has
been claimed as part of authoring this draft.

Required next evidence: CLI configuration validation, a clean local migration,
actual SQL behavior/RLS tests, then gateway requests under independently acquired
local Auth sessions (email, synthetic phone, pending/nonmember/revoked users).
Concurrent grant/revocation and stale commands need real database verification;
locks in source are not measurement. Hosted project configuration, real account
admission, actual SMS delivery, physical-device/network testing and deployment
remain separately unverified and require their own access/approval.
