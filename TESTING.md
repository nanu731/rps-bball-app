# TeamStats testing and acceptance

Reviewed 2026-10-12 at source snapshot `737ca4a`. This is the test entry point,
not a new claim that suites were rerun or a release was approved. Read
[ARCHITECTURE.md](ARCHITECTURE.md) for the source map and
[SECURITY.md](SECURITY.md) for boundaries that require denied-access tests.

## Evidence labels

Track implementation separately from verification environment:

| Label | Minimum evidence |
|---|---|
| Implemented | Identified source/migration exists; no runtime pass implied |
| Locally verified: fixture | Successful synthetic/model/HTTP-fixture execution; no real provider proof |
| Locally verified: actual loopback | Successful real isolated Auth/SQL/SDK execution against loopback services |
| Hosted verified | Actual authorized nonproduction endpoint exercise with recorded allow/deny results |
| Device/UI verified | Observed interaction in the identified app/device/runtime, not just compilation |
| Pending verification | Named check/environment not exercised successfully |
| Disabled / Planned | Inactive integration / requirement not implemented |

Every new result records date, revision, environment, test scope, outcome and
limitations. Relevant source/config changes can invalidate older evidence.
Model fixtures, actual local Auth/SQL/SDK integration, hosted API and physical UI
are different layers. Sign-in or trusted preflight does not prove team authority.

## Native test entry points

Open the existing Xcode project, select the shared **TeamStats** scheme and an
available simulator, then Product → Test. The test target is **TeamStatsTests**.
For agents, the equivalent command from the repository root is:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project TeamStats/TeamStats.xcodeproj -scheme TeamStats \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /private/tmp/teamstats-doc-test-derived
```

Select an installed destination rather than assuming iPhone 17 exists elsewhere.
This command template is not an executed test result. Xcode must be installed;
Command Line Tools alone cannot run it. Do not globally change developer settings
or install dependencies to conceal an environment failure. Existing approved SDK
resolution, simulator services and writable build caches must be available.

| Suite source | Public behavior under test |
|---|---|
| [LocalDraftTests](TeamStats/TeamStatsTests/LocalDraftTests.swift) | Local identities/storage/validation and missing versus zero |
| [AccountTests](TeamStats/TeamStatsTests/AccountTests.swift) | Configuration, session/callback/error state |
| [AdministrationTests](TeamStats/TeamStatsTests/AdministrationTests.swift) | Membership/grants/roster command state and failures |
| [ConnectedStatisticsTests](TeamStats/TeamStatsTests/ConnectedStatisticsTests.swift) | Shared commands, drafts/completion/recovery and response state |
| [GameStatisticsTests](TeamStats/TeamStatsTests/GameStatisticsTests.swift) | Reconciliation, metrics, missing/invalid/overflow cases |
| [PlaybookTests](TeamStats/TeamStatsTests/PlaybookTests.swift) | Geometry, revisions and recovery |
| [MediaResourcesTests](TeamStats/TeamStatsTests/MediaResourcesTests.swift) | Link metadata/review/recovery, not file transfer or playback |
| [PhotoDraftImportTests](TeamStats/TeamStatsTests/PhotoDraftImportTests.swift) | Bounded photo input, explicit mapping/confirmation and validation |
| [LocalServerIntegrationTests](TeamStats/TeamStatsTests/LocalServerIntegrationTests.swift) | Opt-in real loopback Auth/SDK workflows |

The opt-in suite skips without `TEAMSTATS_LOCAL_TEST_FIXTURE`. Only a privately
prepared synthetic loopback fixture is permitted. Do not put real users, privileged
keys or hosted endpoints in a test scheme/committed environment. A skipped check
is not a pass; a generated code is not real external delivery evidence.

## Backend and worker tests

Use a disposable local Supabase database with the ordered migrations applied.
[SQL suites](supabase/tests/) exercise team access, statistical/play/media versions,
recovery and export fences. They use synthetic Auth fixtures and rollback transactions.
Use the approved local pgTAP-capable runner; inspect TAP failures as well as SQL
exit status. Never run fixture SQL against hosted/student data or reset an existing
database as a test shortcut. See [backend verification](supabase/README.md) and
the [statistics](supabase/statistics.md), [export](supabase/exports.md),
[play](supabase/plays.md) and [media](supabase/media_resources.md) evidence sections.

[team_access_gateway.py](supabase/tests/team_access_gateway.py) exercises real
loopback Auth/REST/SQL, not invented JWT claims. It needs Python 3.11+, the already
approved CLI/runtime, local mail capture and disabled external providers. Its
`--cli` and `--runtime-home` paths are machine-specific private configuration.
Keep its loopback guard; do not adapt it casually for hosted use. Preserve unrelated
records and never log returned tokens/keys.

### Reproducible isolated native backend recipe

Command flags were checked against approved CLI 2.120.0 help and gateway source
on 2026-10-12; this documentation change did not execute a fresh stack or suite.
Prerequisites: macOS arm64, Python 3.11+, the approved CLI and previously verified
native service cache. Set private path parameters `TEAMSTATS_CLI` (executable)
and `TEAMSTATS_APPROVED_CACHE` (cache directory). Do not substitute an unapproved
tool, auto-download missing bundles, enable external providers or spend money.

Prepare a new workdir/project ID and physical runtime under `/private/tmp`, with
no spaces in the runtime path. Copy only repository `supabase/config.toml`,
`migrations/`, `tests/` and the verified service cache. Give the copied config a
unique `project_id`. Check copied SMTP/SMS/hooks remain disabled, local mail
capture remains enabled, and its API/database/shadow/mail ports are unoccupied.
If another stack uses those ports, stop here rather than stopping/reconfiguring it.
These are setup preconditions, not permission to reset an existing instance.

From the repository root, this prepares that copy without overwriting existing work:

```sh
set -eu
: "${TEAMSTATS_APPROVED_CACHE:?Verified service-cache path required}"
test -d "$TEAMSTATS_APPROVED_CACHE"
export TEAMSTATS_TEST_WORKDIR=$(mktemp -d /private/tmp/teamstats-test-project.XXXXXX)
export TEAMSTATS_TEST_RUNTIME=$(mktemp -d /private/tmp/teamstats-test-runtime.XXXXXX)
mkdir "$TEAMSTATS_TEST_WORKDIR/supabase" "$TEAMSTATS_TEST_RUNTIME/cache"
cp supabase/config.toml "$TEAMSTATS_TEST_WORKDIR/supabase/config.toml"
cp -R supabase/migrations supabase/tests "$TEAMSTATS_TEST_WORKDIR/supabase/"
cp -R "$TEAMSTATS_APPROVED_CACHE/." "$TEAMSTATS_TEST_RUNTIME/cache/"
python3 - <<'PY'
from pathlib import Path
import os, re, socket, tomllib
root = Path(os.environ['TEAMSTATS_TEST_WORKDIR'])
p = root / 'supabase/config.toml'
text = re.sub(r'(?m)^project_id = .*$', 'project_id = "' + root.name + '"', p.read_text())
p.write_text(text)
c = tomllib.loads(text)
assert c['project_id'] == root.name
assert not c['auth']['email']['smtp']['enabled']
assert all(not v['enabled'] for v in c['auth']['sms'].values() if isinstance(v, dict))
assert all(not v['enabled'] for v in c['auth']['hook'].values())
assert c['local_smtp']['enabled']
for port in [c['api']['port'], c['db']['port'], c['db']['shadow_port'], c['local_smtp']['port']]:
    with socket.socket() as s:
        s.bind(('127.0.0.1', port))
print('Copied synthetic configuration checked; ports free at preflight.')
PY
```

Port preflight cannot prevent a concurrent service startup; runtime identity and
listener checks after startup are still required. Do not continue on a failed check.
After preparing and checking that disposable copy, set `TEAMSTATS_TEST_WORKDIR`
and `TEAMSTATS_TEST_RUNTIME` to its private paths. Use the following command
structure (no actual machine-specific paths/credentials belong in this document):

```sh
set -eu
: "${TEAMSTATS_CLI:?Approved CLI path required}"
: "${TEAMSTATS_TEST_WORKDIR:?New disposable project path required}"
: "${TEAMSTATS_TEST_RUNTIME:?New disposable runtime path required}"
export SUPABASE_HOME="$TEAMSTATS_TEST_RUNTIME"
export SUPABASE_EXPERIMENTAL_STACK=1 SUPABASE_TELEMETRY_DISABLED=1
"$TEAMSTATS_CLI" --workdir "$TEAMSTATS_TEST_WORKDIR" start
"$TEAMSTATS_CLI" --workdir "$TEAMSTATS_TEST_WORKDIR" db push --local --dry-run --skip-vault
"$TEAMSTATS_CLI" --workdir "$TEAMSTATS_TEST_WORKDIR" db push --local --skip-vault
```

Verify the started project/runtime belongs to this run and its listeners are
loopback-only before fixture writes. Startup applies ordered migrations; local
dry-run/push checks for unapplied files without seed/Vault changes. Order is
001 access → 002 statistics → 003 exports → 004 plays → 005 media → 006 play
recovery → 007 media resume → 008 media lineage → 009 statistics recovery.
Stop on schema/history/health failure; no reset, history repair or hosted flags.

For the previously exercised pgTAP runner, set `TEAMSTATS_PG_PROVE` to the approved
bundle's `bin/pg_prove`. Configure `PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE` and
`PGPASSWORD` privately from this runtime's connection settings. Keep passwords
out of arguments/logs. Confirm loopback host and copied config's database port;
never paste or display full CLI status output, which can include keys.

```sh
: "${TEAMSTATS_PG_PROVE:?Approved bundled runner path required}"
: "${PGPORT:?Verified disposable database port required}"
: "${PGUSER:?Private local database user required}"
: "${PGDATABASE:?Private local database name required}"
: "${PGPASSWORD:?Private local database password required}"
case "${PGHOST:-}" in
  localhost|127.0.0.1|::1) ;;
  *) echo 'Stop: verified loopback database required' >&2; exit 1 ;;
esac
python3 - <<'PY'
import os, pathlib, tomllib
c = tomllib.loads((pathlib.Path(os.environ['TEAMSTATS_TEST_WORKDIR']) / 'supabase/config.toml').read_text())
assert int(os.environ['PGPORT']) == c['db']['port'], 'Stop: database port differs from disposable config'
PY
"$TEAMSTATS_PG_PROVE" "$TEAMSTATS_TEST_WORKDIR"/supabase/tests/*.sql
python3 supabase/tests/team_access_gateway.py \
  --cli "$TEAMSTATS_CLI" --runtime-home "$TEAMSTATS_TEST_RUNTIME" \
  --workdir "$TEAMSTATS_TEST_WORKDIR"
```

Require exit zero, no TAP `not ok`/failed plans, successful suite summaries and
gateway PASS checks. Plain `psql` exit zero is insufficient for TAP assertions.
SQL fixtures roll back; gateway-created synthetic records can persist within the
disposable runtime. The gateway itself checks local endpoints/disabled providers.
No email-provider, Google or device evidence follows from these local checks.

For native opt-in checks, add the gateway's `--client-config` with a new ignored
private destination. It writes synthetic loopback configuration and refuses
overwrites. Supply that JSON privately as `TEAMSTATS_LOCAL_TEST_FIXTURE` to the
native test target; never commit its contents/scheme environment. Confirm those
checks ran rather than skipped. Keep revision/date/environment/scope with evidence.

Stop only the newly started project without removing its data:

```sh
"$TEAMSTATS_CLI" --workdir "$TEAMSTATS_TEST_WORKDIR" stop
```

Do not use `--all` or `--no-backup`. Preserve directories/evidence until deletion
is approved. This is an explicit recipe, not evidence it was rerun for this edit;
unavailable prerequisites are blockers, not reasons to modify hosted/original data.

### Synthetic export-worker checks

The synthetic export-worker suite uses Python's standard library:

```sh
python3 -m unittest discover -s supabase/tests -p test_sheets_export.py
```

It uses local HTTP fixtures. Passing does not establish Google worker access,
Sheets delivery, quotas or permissions. Keep real Google delivery disabled until
separately authorized/configured within the $0 budget.

## Current evidence and open gates

2026-10-12 local media tooling: owner-approved CLI2.120.0 prepared Storage1.79.36-r0,
Edge Runtime1.77.4-r0 and Imgproxy3.26.0-r0 in a separate synthetic native stack.
All three archive and manifest SHA256 values were independently matched to the
official pinned catalog. Installed license notices and the official SPDX2.3 assets
are retained privately; this is not an exhaustive dependency/legal certification.
Additional official upstream/distributor Poppler26.05.0 checksums and GPL notices
were verified for the already bundled renderer; it is not shipped in the iOS app.

CLI endpoint metadata alone did not establish safe binding. Eager activation
revealed internal Functions/PostgREST/Storage listeners on all interfaces. Separate
physical launcher copies apply documented `--ip=127.0.0.1`,
`PGRST_SERVER_HOST`/`PGRST_ADMIN_SERVER_HOST` and `SERVER_HOST`/`HOST` settings.
Upstream archives, original launchers and actual binaries remain unchanged.
Lazy activation also timed out while Imgproxy's direct health was healthy;
state-preserving stop/start with `--eager` resolved it. All seven services then
reported healthy; three media health probes and all15 actual current listeners
passed loopback checks. These are isolated-tooling results, not private-object,
hosted or native-player acceptance. Recheck sockets after every service activation.

Source snapshot `737ca4a` includes the local checkpoint and polish work recorded
in [WORKFLOW.md](WORKFLOW.md) and subsystem documentation. No acceptance suite
was rerun to author these documents.

| Area | Recorded evidence | Still required |
|---|---|---|
| Native/local backend | Fixture suites and actual local Auth/SDK/SQL workflows recorded | Relevant regressions after source changes |
| Account hosted setup | Owner-confirmed sign-in/UUID comparison; trusted identity/session preflight | Distinct-user signed hosted permission tests |
| Hosted activation | Owner-observed execution; independent16 hosted SQL checks,3 permission denials/2 unverified-role zero-row reads; Data API excludes history | Signed owner/nonmember, admission, delegation/revocation and workflow tests; SQL role probes are not signed API evidence |
| New UI/polish | Simulator builds and model regressions recorded | Both-device dirty navigation, delayed/failed Save, denied-content recovery, accessibility |
| Photos | Synthetic Vision and proposal checks recorded | Representative marked forms and picker/Apply/Cancel interaction |
| Google export | SQL/worker fixtures recorded; actual delivery disabled | Trusted sender/worker access and versioned Google readback |
| Media/scouting | Link metadata locally exercised; scouting input preparation8 native tests and iPad26.4 build passed | Report picker/upload/lifecycle/private retrieval and actual provider validation/capacity/rights; videos still need actual bytes/playback |
| Release | Simulator builds and an unsigned archive recorded | Actual lowest supported OS, physical devices, signing, service setup and explicit release approval |

This checkpoint is a dated snapshot. Verify current runtime/schema before new
work; do not replace a pending entry merely because the provider project is open.

## Device acceptance checklist

Use TEST ONLY games, synthetic roster/users and authorized nonproduction targets.
On iPhone/iPad, include portrait/landscape, larger Dynamic Type, VoiceOver and
light/dark appearance. Check keyboard-visible final fields and Save/Back, warning
readability, empty versus loading/error, first permitted action, immediate pending
feedback, duplicate taps, failures and Retry.

Exercise partial forms, Keep editing/explicit discard, background/resume and
approved retained-draft attachment. Confirm authority is not optimistic. Test
revocation and transient reload failure without exposing denied snapshots.
Force termination differs from ordinary backgrounding; do not promise restoration
without observing it. Record slow-network/low-power/physical-device behavior
separately. Existing historical manual checks do not verify newly changed screens.

## Maintenance and safe reporting

Update this entry point when suites, prerequisites or acceptance gates change.
Keep precise private setup/evidence in approved private storage; public reports
contain sanitized revision/environment/scope/outcome only. Commit explicit paths,
preserve personal Xcode staged/working files, and avoid repeating passed checks
unless changes or unresolved concerns warrant it. Documentation completion never
authorizes spending, hosted activation, production migration or release.

## Hosted activation readback — 2026-10-12

The owner reports executing the exact reviewed secured transaction and observing
all four activation results true. That execution evidence is owner-observed.
Independent trusted read-only hosted SQL at source `55b9249` then passed16 checks:
exact nine migration versions/names; metadata RLS with no policies; no PUBLIC or
anon/authenticated history access; RLS on all20 app tables; denied direct client
writes/anonymous reads; expected authenticated read grants; private export
payload fields; client roles without RLS bypass; fixed-search-path definers;
verified owner identity, active membership and exactly one bootstrap audit.
Data API settings independently show only public/graphql_public exposed; history
is excluded. Save remained disabled and no settings changed.

A separate read-only rollback probe produced3 actual permission denials (history
reads by anon/authenticated and anonymous team read). An authenticated role with
empty verified claims saw0 team and membership rows. These are trusted SQL role
probes, not distinct-user signed API tests. No activation/bootstrap was rerun,
accounts/grants changed, local records uploaded or external delivery enabled.
Signed hosted owner/nonmember/admission/delegation/revocation acceptance remains
pending; creating credentials/security-sensitive grants requires human action-time
confirmation. Other ready local work continues under the strict$0 boundary.

At source revision `93cac9a` (2026-10-12), scouting input preparation uses real synthetic native PDF documents in
`ScoutingReportDocumentTests` (8 passed on iPhone17/26.4, final iPad build passed).
No report upload/navigation was added; client parsing is not trusted server PDF
validation or malicious-document sanitization. Actual file-provider/picker/UI and
storage/transfer/cost acceptance remain unverified. Original8 local JSON hashes
and both personal working/staged files survived the run unchanged; container
paths may relocate during native tests, so compare device/file identities too.

Independent source review: Standards found one missing tested-revision label,
now repaired; optional sharing of the two bounded file readers is deferred.
Spec found no blocking defect for source-only preparation. A synthetic macOS
PDFKit probe accepted a corrupt compressed stream with one page: parser acceptance
is not comprehensive content/readability validation. This probe is neither an
iOS26.4 check nor provider acceptance. Trusted validation remains unimplemented.
