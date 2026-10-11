# Local team access slice

This directory contains a Postgres migration and synthetic behavior tests for
team membership, capabilities, bounded owner delegation and roster history.
The slice has passed actual local Supabase Auth/Postgres and signed gateway tests;
hosted operation and complete native-app integration remain unverified.
No hosted configuration, real owner identity, student data or automatic local
record upload is included. This slice does not implement shared statistical
submissions, completion, publication, exports, plays or media storage.

The strict budget is $0. The configuration is for a disposable local runtime:
email is captured by the local inbox, real SMS providers and delivery hooks are
disabled, and one reserved fictional phone number has a configured local test code. In the
verified native runtime, Auth reports phone disabled and rejects this request with
`phone_provider_disabled`; the map alone has not established phone verification.
No SMS-delivery evidence is claimed. Default local email may contain a magic link;
typed email OTP template parity remains unverified. The pinned native runtime
rejects custom email-template `content_path`, so this draft does not enable it.
The setting names follow the [official v2.120.0 template](https://github.com/supabase/cli/blob/v2.120.0/apps/cli-go/pkg/config/templates/config.toml),
including `local_smtp`; the pinned CLI accepted this configuration locally. Do not apply this configuration to a hosted
project or enable paid providers. The owner-approved CLI and its four pinned native service bundles are isolated
local tooling; no hosted project or additional dependency is configured here.

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

## Local verification and remaining limits

On 2026-10-11 the owner-approved CLI 2.120.0 started actual native services:
Postgres 17.11.0.004-r1, PostgREST v16.4-r0, Auth v2.197.0-r0 and Mailpit v1.31.3-r0.
The clean startup applied this migration, and the required `auth.users` and
`auth.sessions` columns were verified. Bundled `pg_prove` executed
`tests/team_access.sql`: **81/81 passed**, including RLS, bounded grants, owner
protection, stale/NULL administration revisions, roster history and session denial.
SQL fixture users/sessions remain synthetic and transactional; these tests do not
establish provider verification or delivery.

The real gateway harness obtained two independent signed Auth sessions through
actual locally captured default email verification links, and another through an
explicit trusted local TEST ONLY generated link. It passed 40 checks covering
pending/nonmember reads, admission, roster persistence, protected direct writes,
stale membership commands, removal and actual Auth logout followed by denial with
the old still-unexpired signed JWT. A separate synthetic-owner experiment passed
26 checks covering stale capability revocation, owner logout, denied administration
and actual reauthentication retaining the same owner UUID. These check counts
include setup/snapshot checks; they are not distinct product-feature counts.

The reusable `tests/team_access_gateway.py` runs the real Auth/REST/SQL seams with
Python 3.11+ standard-library modules, the already-approved CLI and bundled `psql`.
It requires `--cli` and `--runtime-home`, accepts `--workdir`, and can write explicitly
requested `--evidence` or TEST ONLY `--client-config` files. Outputs are sanitized;
keys/tokens stay in memory. Optional files are created with mode 0600 and never
overwritten; destinations must remain private/ignored. The harness rejects external
endpoints and enabled SMTP/SMS providers/hooks, uses a fresh synthetic namespace,
and preserves existing records. It does not install dependencies or configure
hosted services. Do not run it against real student data or a hosted project.

Observed transport details: access denials returned `42501` with HTTP 403;
anonymous RPC denial used HTTP 401. PostgREST v16.4 mapped stale `40001` to HTTP 500.
Clients must recognize the SQLSTATE and reload before retrying, without assuming
HTTP 409. Default captured emails provided links, not typed codes. An optional
admin-generated code is a local TEST ONLY native-client fixture; generating it
alone does not prove typed-code verification, the application's email-request-to-inbox
flow or external delivery.
Phone verification remains blocked while all real senders stay disabled.

Native Postgres initially failed when its cache path contained spaces. Its pinned
launcher resolves symlinks physically and passes a bare key-helper pathname to
pgsodium's shell execution. Copying the verified cache to a fresh short physical
runtime home resolved startup, preserving the original cache/state. This is a
local tooling workaround, not a TeamStats application fix. All observed service
listeners were loopback-only and telemetry was disabled.

Remaining evidence: concurrent grant/revocation measurements, full native UI and
session integration, production/hosted configuration, real email/phone delivery,
physical-device/network checks, statistical publication/exports and deployment.
None of those is established by these local tests; release approval remains separate.


An opt-in native `LocalServerIntegrationTests` check passed against the actual
loopback stack. It used a trusted synthetic generated email OTP, restored its
session from Keychain in a new SDK client, and created/edited/archived one clearly
labeled roster fixture while verifying retained unrelated identities and history.
This proves the SDK/server seam, not external delivery or the Account UI. Its
`TEAMSTATS_LOCAL_TEST_FIXTURE` environment JSON must contain only loopback/public
configuration and synthetic identities; never supply privileged keys or real data.
Default runs skip it. See `statistics.md` for the statistical lifecycle contract
and actual isolated SQL results; Sheet delivery remains unimplemented.


The local config allows the exact native email callback. Its actual captured
default-email link → Auth redirect → native PKCE exchange test passed, including
restoring the pending device challenge after recreating Account. Email codes
remain supported for senders that provide them; new Free projects cannot alter
default templates as of June3,2026. No external sender, SMS or paid service was
enabled. Capture of a redirect does not establish actual OS link-opening UI.
