# TeamStats testing and acceptance

Updated 2026-10-14 for the native design/readiness continuation. This is the test entry point,
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
| Media/scouting | Actual isolated signed storage/validation/review/delivery, native player and two-process retained playback passed (later checkpoint below) | Hosted capacity/worker/signed access, rendered picker/viewer and full app/Auth offline reopening; real Hudl rights |
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
At that dated preparation-only checkpoint no report upload/navigation was added; client parsing is not trusted server PDF
validation or malicious-document sanitization. Actual file-provider/picker/UI and
storage/transfer/cost acceptance remain unverified. Original8 local JSON hashes
and both personal working/staged files survived the run unchanged; container
paths may relocate during native tests, so compare device/file identities too.

Independent source review: Standards found one missing tested-revision label,
now repaired; optional sharing of the two bounded file readers is deferred.
Spec found no blocking defect for source-only preparation. A synthetic macOS
PDFKit probe accepted a corrupt compressed stream with one page: parser acceptance
is not comprehensive content/readability validation. This probe is neither an
iOS26.4 check nor provider acceptance. That checkpoint did not implement trusted validation; the later checks below supersede that limitation.

## Integrated private files — 2026-10-12

Source through e7b119e plus native UI09bb6e2. Independent Standards/Spec slice
reviews were repaired and rereviewed. Actual isolated SQL69 checks and signed
Auth/Storage/worker67 checks passed; fixtures use distinct synthetic identities.
The trusted validator passed20 actual native fixtures and the gateway25 checks,
including portrait media, external MP4 reference rejection, malformed PDF rendering
and timeout/process cleanup. The Functions relay passed7 contract tests plus actual
signed PDF lifecycle/hash delivery. These are local checks, not hosted activation.

Native account26, retention5 and file-model7 fixture cases passed across affected
runs. One actual native SDK integration passed interrupted reservation recovery,
new immutable upload, full trusted H264/AAC validation, same-ID metadata revision,
authorized publication, complete hash-verified delivery and AVPlayer ready/time
advancement. Cached reuse avoided another delivery request in the fixture check.
Recreating the retention object alone does not establish app relaunch acceptance.
A separate two-test-host offline playback check passed: distinct process IDs,
same app-relative file/version/hash, player ready/time advancement, zero observed
HTTP in both playback windows. Xcode relocated the data container; this verifies
retained bytes across test processes, not a stable literal absolute path. Full app
startup/Auth/offline UI remains pending.

Native clip preparation also passed5 synthetic macOS fixtures and rejected a
remote input; iOS compilation passed. This does not substitute for actual iOS
picker/codec preparation or real marked-sheet OCR accuracy. All26 audited local
runtime listeners were loopback-only after state-preserving binding repairs.
All8 original local JSON files, temporary identities and personal Xcode bytes/index
entries passed the preservation guard. New synthetic files are test fixtures.

At that checkpoint UI control was blocked by the locked Mac; repeated identical attempts stopped.
New Team/file/player/PDF screens still require rendered iPhone/iPad light/dark,
rotation, large text, VoiceOver, keyboard Save, pending/failure/dirty navigation,
known revocation and full app termination/offline reopening checks. See the private
manual checklist. The previously verified owner activation/bootstrap is not rerun.
Hosted001/002/003 follow-up migrations, signed hosted access, media capacity/worker,
Google delivery, sender, real Hudl rights, branding,26.0/physical/signing/release
acceptance remain separate gates under the strict$0 budget.

Preservation note: the personal Xcode UI-state working file changed between guard
snapshots during this session; its origin was not established. The merge's immediate
before/after snapshots were identical and its staged entry stayed unchanged. The
latest bytes were retained without restoration; both baselines remain private.
The scheme-state and unrelated project bytes/index,8 original JSON contents and
temporary roster identities remained unchanged. Do not claim the UI-state working
bytes stayed equal to the session's original snapshot.

### Final executable integration checks — 2026-10-12

The iPhone17/iOS26.4 integrated build/test run passed155 selected cases:151
executed,4 explicit opt-in integration skips,0 failures. Review then identified
terminal validator codes that could falsely enter reconciliation/access-lock recovery.
The final narrow repair rebuilt the app and passed all8 affected native cases,
including22 public error-code outcomes; all8 relay cases passed. Known content
rejection and neutral validator failure offer explicit new drafts while preserving
history; capacity/unavailable/uncertain outcomes retain conservative recovery.
Both final Standards and Spec source rereviews report0 remaining concrete findings.

Actual read-only isolated delivery receipts corroborate one delivery operation per
published synthetic clip despite cached reuse.26 current owned local listeners
remain loopback-only. Original8 local JSON contents and temporary identities are
unchanged. Personal staged entries remain unchanged; the separately disclosed
UI-state working-byte change is preserved, not overwritten. No activation/bootstrap,
hosted file deployment, local draft upload, paid service or production release.
No new rendered UI acceptance is claimed while the Mac is locked. Full app/Auth
relaunch/offline UI, current hosted signed access/capacity and provider integrations,
real forms/assets and physical/26.0/signing remain exact external/device gates.

## Rendered acceptance continuation — source4da97b6,2026-10-12

Current signed isolated POLISH TEST build passed and installed in place on iPhone17
and iPadA16/iOS26.4. Both apps launched; original app/container and test JSON were
preserved. Representative screenshots remain private. No source repair was made:
failed automation transitions do not establish an application defect.

| Acceptance | Result and precise scope |
|---|---|
| Preservation | Passed: both personal working/staged snapshots, unrelated project change,8 original JSON files and temporary identities unchanged from this turn's initial snapshot; prior snapshots retained. |
| Local rendering | Passed: both empty local-games screens; local/shared guidance; maroon/system surfaces; representative light/dark, five text-size increases and settled landscape inspection. These are local forms/details, not whole-app acceptance. |
| iPad Save | Passed: clearly labeled synthetic game, software keyboard visible, Save dismisses and saved details show correct metadata. |
| iPhone form | Passed: semantic Add opens required-opponent/disabled-Save form; large-text native scroll reaches footer with toolbar visible. Typing and enabled Save not verified in this run. |
| Input automation | Failed/unresolved: entry/tab presses do not activate on iPad; Account-tab presses and typing do not take effect on iPhone. Fresh window binding/keyboard forwarding did not resolve it. Native menus/Add/scroll actions worked; no resets or app/container deletion. |
| Remaining device flows | Blocked: warnings/counters, connected Team/Manage team, completion/review/correction/dirty recovery, court/playback, clip/PDF upload/viewing, actual player controls/retention/full-app offline startup, known revocation, VoiceOver and Reduce Motion. Prior model/provider evidence remains separate. |
| Hosted prerequisites | Existing dashboard lists nine baseline migrations; three follow-up versions are unrecorded. Edge Functions shows first-deployment empty state. No distinct synthetic hosted credentials, trusted worker/Google/sender setup or fresh$0 capacity evidence exists in authorized configuration. No activation/bootstrap, grants or deployments changed. |

The proposed separate SQL snippet was rejected because it would persist dashboard
content without explicit approval. The existing migration-history page provided
a safer read-only alternative; no snippet or SQL execution was needed/performed.
Follow-up migration history is not proof of current signed-user permissions.
The local bounded capacity window is expired; no quotas/charges/history were changed.
This does not block local rendering. It must be refreshed only for the isolated
fixture before new file-transfer checks, never treated as hosted cost evidence.

Text-size increases were reversed and appearance restored after captures. Full
app/Auth offline startup remains unverified; two-test-host clip playback is earlier
separate evidence. Actual26.0, physical devices, real marked forms/Hudl rights,
branding/roster, signing/distribution and release remain unverified. Stop repeated
failed automation; the private manual checklist records exact actions/expectations.


## Recovered acceptance and hosted follow-ups — 2026-10-13

Current status PARTIAL. The dated2026-10-12 input failure above is historical;
isolated native XCUITest now performs real interactions without resetting devices
or deleting containers. `scripts/run_native_ui_tests.py` copies the existing project
into ignored private storage and installs only the separate UIAcceptance bundle.
Original project/index files are unchanged. Fixtures are opt-in ignored synthetic
configuration; ordinary app-host setup and rendered UI remain separate. Use explicit
journeys on an already booted simulator. Unconfigured-state checks require the
separate app to be unconfigured; no helper wipes a configured container to achieve it.
Timeout/nonzero results remain failures even when cleanup succeeds. Screenshots,
source hashes, logs and result bundles stay private.

| Evidence | Actual result and limitation |
|---|---|
| Hosted follow-ups | Applied reviewed Hudl/contact/private-file follow-ups and domain-conflict migration13;22 app tables retain RLS, private history ACL/unexposed schema retained, SMS off and hosted capacity disabled. |
| Signed hosted users |45 checks passed with five verified controlled synthetic accounts, including ordinary/outsider/pending denial, bounded grants/revocation, stale revisions, distinct review and corrections. Existing22-table aggregate counts preserved independently; no row-content proof. |
| Domain-conflict repair | Five native regressions failed before repair; six focused conflict/legacy cases passed after.547 affected pgTAP assertions passed in isolated rollback; gateway regression passed.26 function pins/34 changed raises reviewed; actual hosted stale commands now return409. |
| Actual Google formula | Private fixture passes multiple group projection, late older rows, correction isolation,20-digit version preservation and retry without duplicate rows.20 worker protocol tests passed. Automatic OAuth/runtime delivery remains unavailable. |
| Native local entry | iPhone/iPad26.4 new-game keyboard Save/details; paint blank/explicit0/+/-/invalid/clear/save/edit/relaunch; explicit Keep editing/discard retain unsaved/saved values. XXXL text, not maximum accessibility size. |
| Actual local connected UI | Local email/PKCE/GetUser verification and restore; iPhone server-confirmed Team selection, protected Manage team, routine roster, shared/local separation and authored movement. Adaptive play controls inspected after repair. |
| Retained media | Actual local validated/published20-second synthetic clip retained through app-host setup; saved-list/viewer navigation rendered. Full-app cold startup with exact actual backend stopped opens the retained viewer with unknown-rights disclosure; restart retains exact video bytes. This is not native play/pause/scrub acceptance. |
| Remaining automation gaps | Native video Play/timeline absent from the actual hierarchy after bounded attempts. iPhone paired bottom-field Save/relaunch passed; full scoring/table and iPad opponent-field keyboard focus remain open. Do not infer a product defect or repeat unchanged attempts. |
| External/device gates | Hosted worker/capacity, automatic Google export and team-email sender; real forms/Hudl rights, roster/branding; full changed-screen accessibility/Reduce Motion, actual 26.0, hardware, performance and distribution. |

Independent source Standards and Spec reviews report0 actionable findings for the
repair slices. Earlier151 executed/4 skipped broad tests retain their original scope;
unaffected suites were not repeated. The private manual checklist specifies the
remaining user actions and differentiates rendered, model, local and hosted evidence.


### Additional native results and audit limitation — 2026-10-14

Per-case passes: iPhone paired blank/zero/independent-record/bottom-field keyboard
Save/relaunch and sign-out concealment; iPad actual Auth setup; both families'
Scouting/Hudl/accepted-statistics destinations and published PDF open/Close. Actual
local synthetic two-page PDF upload/validation/submission/approval/hash readback
preserves the prior missing operation/history and earlier media digests. iPhone
scroll/zoom/Close passed; iPad scroll/zoom-out passed, zoom-in confirmation pending.
The new `ConnectedScoutingAcceptanceTests` is opt-in, uses actual saved published
bytes and records explicit skips when PDF text is not exposed; a skip is not zoom
acceptance. Screenshot comparison supplements gesture execution.

Game-list contrast audit failed before and after the narrow primary-text repair,
although the repaired text renders darker. Its handler exempts only partially
occluded static content, reveals it and re-audits; visible contrast and description
failures are retained. Do not call the whole accessibility audit green. iPad video
controls likewise remain absent from the actual hierarchy after one independent
attempt; no repeated unchanged attempts or custom player changes are justified.
Settings-based Reduce Motion tests must record/restore the actual initial value;
a killed test needs manual verification/restoration before another attempt.

### Controlled account-switch journey — 2026-10-14

Actual iPad UI sign-out and fresh local email/PKCE verification of a distinct viewer
passed. Its saved library was empty, the former actor's clip title was concealed,
and server-confirmed membership did not expose Manage team. Explicit Keep created
one new actor-scoped copy; the former actor's exact clip bytes were unchanged.
Viewer-only signed removal preserved the owner, older memberships/grants and all
older audit-row digests. The first rendered denial attempt stopped before the
rights request because a duplicate iPad tab control left Account selected; it is
not denial acceptance. The bounded retest selected the inner native control, confirmed selection and
passed actual request/denial/title concealment. Auth-session revocation is separate from this membership test.

Direct iPhone entry verified live lower-bound/exact mismatch, incomplete-state banner
removal, derived rebounds and explicit0. Desktop relock blocked the later Save;
no persistence claim is made from that buffer. Maximum-text/dark setting commands
alone did not visibly change its captured screen and are not layout acceptance.

Actual subsequent viewer sign-out and original synthetic-owner PKCE/GetUser restore
passed. The restored owner's retained-title case passed even though the same bundle's
maximum-text rotation case failed; outcomes are retained per case. Actual dark/max
rendering is confirmed by screenshot, but control reachability initially failed
because the helper scrolled the sidebar. The corrected detail-scroll adapter passed dark/max portrait reachability. Both
captures were still portrait; a subsequent actual-shape assertion failed820×1180.
Rotation remains unverified despite a successful orientation command. The test
records/restores the initial orientation and cannot silently credit rotation.

Final continuation evidence: maximum accessibility text/dark iPad play-control
reachability is a portrait-only pass. The stricter rotation check failed because
its window remained820×1180; no unchanged retry or app defect inference. Both
simulators' light/large settings were restored and read back. Standards/Spec reviews
resolved their findings; private screenshots/failures and current manual checklist
remain retained. Physical testing remains owner-deferred; full acceptance PARTIAL.

## Native design/readiness continuation — 2026-10-14

The full isolated model run executed 168 tests, 7 skipped, 0 failed; five backup
checks cover identities, optional/zero round-trip, private-file exclusion, corrupt
store failure and duplicate/invalid games. File-protection tests cover new saves
and unchanged legacy bytes; physical protection assertion skips on Simulator.
Final existing-project simulator build passed. No unchanged hosted bootstrap,
RLS/Retry or full model suite was repeated to manufacture new evidence.

Actual UI cases passed independently of other failures in mixed bundles: phone
scoring/two-player table/save/relaunch; pad shared game keyboard Save/completion;
phone drawing/recovery and actual Reduce Motion; both saved-record presentation;
pad guide/export native Cancel returning to guide. Explicit local export file
creation at a chosen destination remains unverified; Cancel is not a saved export.

Maximum-text phone reached15 fields and saved with software keyboard visible;
receipt plus cold storage readback preserved explicit0 and missing values. Final
maximum-text UI reopening/short-footer recapture was interrupted (exit-15; incomplete
xcresult), not passed. Actual landscape/VoiceOver/physical26.0 remain pending.
Date native contrast audit still fails despite a measured7.46:1 opaque crop; repaired
light Scoring header now measures18.82:1. This is not whole-app contrast certification.
Photo Cancel/Apply and repeatable native AVKit controls remain bounded automation
gaps; observed tablet playback/Pause/scrub is a subset, not a full repeatable pass.
Private screenshots, result logs, source fingerprints and precise owner checklist
are retained outside the public repository. Original records/identities unchanged.

Original simulator installation verified after source commit `1126d6a`: both original
apps were stopped before update, previous app bundles retained privately, and the
new binary installed in place without uninstall/reset or launch. Installed executable
hashes and TeamStatsSourceRevision identify `1126d6a` on both devices. Generated
provenance metadata was followed by local re-signing with preserved entitlements;
strict signature verification passed on both installed bundles. The OS relocated
the data-container paths; all Documents/Application Support content hashes,8 original
JSONs and temporary identities stayed unchanged. The unrelated local PBX configuration
was used unchanged. This proves installation/preservation, not new original-data UI
acceptance. Separate UI TEST results remain synthetic and provider-scoped.


## Approved native game ledger —2026-10-16: PARTIAL

Acceptance follow-up to f294c61. Installed isolated app: **TeamStats UI TEST**,
bundle `com.narayanlekhi.TeamStats.UIAcceptance`, version1.0(1), minimum26.0.
The final universal simulator binary supports both device families; installed and
launched on iPhone17 / iPad(A16), both26.4. This is not actual26.0 runtime evidence.

Rendered defects repaired: insufficient maximum-text iPad roster space, oversized
derived headings, and a phone Review photo label fragmented into character-sized
lines. Native page sizing, scaled caption headings and relocated swipe guidance
recover space. A native adaptive label uses the photo symbol when the full action
label cannot fit; its complete player-specific accessibility name and minimum
44-point target remain. No font cap, custom app gestures, data/validation change,
dependency or redesign. Standards0 open findings; Spec0. A missing post-tap saved
receipt assertion in the landscape test was corrected; that test is not accepted.

| Check | Actual result |
|---|---|
| Final build |Universal simulator build/install/launch passed. Both devices ran the same final repaired app binary. |
| Final iPhone, dark, maximum text |2 cases passed: keyboard-visible contradictory draft Save with actual receipt (119.913s); all5 player identities traversed through their jerseys and fully visible adaptive actions (324.031s). Before/lower captures inspected. Tall names require vertical scrolling. |
| Final iPad, light, maximum-text roster |Passed all5 identities and lower actions (130.530s). Captures show wrapped names/jerseys and fitting photo icons through player5. |
| Final iPad keyboard |Normal-font coordinate Save tap dismissed the floating number pad but produced no saved receipt; case failed (29.178s). Maximum-text case stopped at notice AX-hittability (59.924s), before Save. Screenshots show the notice/Save visibly in bounds; visibility is not successful activation. No further retries or app keyboard workaround. |
| Final column access |Not accepted. Phone bounded pans reached Free throws made; the final numeric field remained outside the viewport. Alternate replay hit its300s limit. Final iPad journey stopped at the initial Save check. All numeric/derived columns, far-right edit and reopen still need the manual check below. |
| Latest full scoring journey, before final adaptive-label repair |Phone passed partial/exact checks, appearance/removal, two-player disclosure, mode-shared unsaved edits, counter1→0, negative blocking, draft Save and relaunch (243.477s). Not relabeled as a final-build replay after the last repair. Final phone maximum-text Save independently confirms discrepant drafts remain saveable. |
| Shared entry |Earlier actual local-service iPad capture showed calm Check scoring with points4/threes7→at least21. Phone alternate stopped reaching Threes made. Shared mode switching and server Save remain unverified for this slice; no hosted pass inferred. |
| Rotation |Simulator bezel rotated but content stayed sideways portrait; native Settings reproduced it. No settled landscape or app-specific defect inferred. Portrait restored. |
| VoiceOver |Unavailable in the installed Simulator/accessibility API. Actual iOS screen-reader acceptance requires an authorized unlocked physical device, previously deferred. AX labels are not a VoiceOver pass. |
| Reduce Motion |Desktop and alternate native Settings interaction did not enable it; switch remained0. No On-state app pass. Unchanged attempts stopped. |
| Horizontal indicator |Axis-specific suppression retained. Still captures after panning and sampled retained pre-adaptive-repair video frames show no bar. Final-build absence during active panning remains manual; native video capture failed with SimRenderServer code2. |
| Earlier model/storage checks |8 executed,1 simulator file-protection skip,0 failures. Not repeated: storage, arithmetic and missingness logic did not change. |
| Preservation |174 original JSON-file hashes, stable temporary identities, protected Xcode working bytes/index entries unchanged. Original apps never reset/uninstalled. Current personal UI-state bytes and older snapshots retained; no guessed restoration. |

Private results, recordings, screenshots, source fingerprints and preservation
snapshots remain ignored under `.scratch/`. Final affected phone evidence is the
044916657743Z run; final iPad evidence uses that same universal binary. Final phone
dark / iPad light captures were inspected; other appearance/rotation combinations
are not final-build passes. Phone light appearance and iPad connected-hardware-
keyboard behavior were restored. No bootstrap repeat, original upload, backend
activation, dependency or paid action. Local/shared separation and current-authority checks are unchanged.

### Two-check diagnosis —2026-10-16 (baseline c1ada8d)

Both original failures are resolved. The scoped changes are in BoxScore.swift
(saved-status presentation only) and LocalAcceptanceTests.swift. No storage,
validation, identity, authority or notice-activation behavior changed.

- **iPad floating keypad:** `PopoverDismissRegion` consumes the first outside tap
  at Save. It dismisses the system popup, retaining0 and Unsaved changes; it does
  not invoke Save. Explicit Save afterward produces the receipt, enables Done
  and survives cold launch. The adapter now dismisses the popup deliberately
  before testing Save, never treating dismissal as success or blindly retrying
  a write. The destination-specific probe skips iPhone rather than requiring an
  iPad-only popup there.
- **Maximum-text Check scoring:** a tap-point assertion was inappropriate as the
  sole static-text readability check, especially behind a modal keypad. Acceptance
  now checks full accessible labels, overlapping visible bands below the navigation
  overlay and actual screenshots. Failed reset gestures previously began under
  that overlay; corrected gestures stop if they make no progress.
- **Additional demonstrated phone defect:** after Save, the long two-line receipt
  compressed the visible header to about35 points, clipping enlarged glyphs.
  The visible receipt is now “Saved locally”; its full “Draft saved on this device.”
  accessibility label remains. Before/after native replay failed/passed respectively.
  Inspected final bands show every complete enlarged glyph line, including the
  entire title, explanation, player and partial lower bound4→at least21. Nothing
  became tappable, urgent, modal or blocking.
- **Horizontal columns:** the adapter anchors to the active editor header rather
  than a background viewer/short label. Offscreen static heading hit testing threw
  an invalid-activation-point error; static traversal now uses geometry plus
  inspected captures. Numeric inputs still require actual hittability. Both devices
  reached/edited the last free-throw-miss field, saved0, cold-reopened0, and reached
  readable Total rebounds and Points check. The app's native scroll code is unchanged.

Final repaired-build evidence (actual26.4, minimum target26.0):

| Device | Focused journey | Result |
| --- | --- | --- |
| iPhone17 | Maximum text: visible keyboard and confirmed keyboard-closed full notice traversal, editing/Save, saved/reopened4/7 | PASS188.001s |
| iPhone17 | Final numeric0, Save/receipt, relaunch0 and derived columns | PASS152.418s |
| iPad(A16) | Maximum text: full notice after popup dismissal and after keyboard Done, editing/Save, saved/reopened4/7 | PASS95.514s |
| iPad(A16) | Final numeric0, Save/receipt, relaunch0 and derived columns | PASS99.610s |
| iPad(A16) | Floating-keypad first-tap dismissal preserves0, explicit Save, cold reopening0 | PASS37.109s |

Final build commands passed; five final focused journeys passed, no failures/skips.
Screenshots and private QA crop indexes were inspected; originals remain unchanged.
iPad popup dismissal hides numeric keys while retaining focus/toolbar: it is not
claimed as full traversal through an open modal keypad. Phone full traversal with
visible keys was verified. Current captures use light appearance; earlier dark,
rotation/shared/Reduce Motion evidence is not relabeled as final-build execution.

Installed: **TeamStats UI TEST1.0(1)**, isolated bundle
`com.narayanlekhi.TeamStats.UIAcceptance`, iPhone/iPad26.4. Both installed builds'
app-code fingerprints match; executable signing bytes may differ. Private source
fingerprints tie the repair to this commit. Result bundles are retained under
`.scratch/teamstats-native-two-checks-20261016/`.

Direct JSON readback confirms unique game/player keys after repeated Save/edit,
reopened4/7 and explicit0, and unchanged pre-existing isolated games/scores and
other existing draft stores. All174 original JSON hashes, temporary identities,
and protected Xcode working/index entries are preserved. The current personal
UI state differed by2 bytes from the retained older snapshot at task entry; both
versions were retained without guessed restoration, with no further task drift.
iPad hardware-keyboard connection restored. No reset, uninstall, original upload,
provider activation, dependency or paid action.

The final strict signature check diagnosed a stale Assets.car seal from the
preceding phone build after the incremental destination switch. The generated
artifact was retained, then re-signed locally with existing metadata. App code,
assets and other resources stayed identical; both isolated installations passed
strict signature verification and launch, with all saved JSON bytes unchanged.
This packaging repair does not relabel unrelated UI checks as passed.
Independent final reviews: Standards0 remaining findings; Spec0.

### Supported accessibility testing options

Installed Xcode26.4/Simulator26.4 menus have no VoiceOver toggle and installed
XCTest headers expose no VoiceOver controller. Accessibility Inspector is installed;
its target menu and navigation/speak controls were inspected. Apple documents
[Simulator reading-order inspection and spoken descriptions](https://developer.apple.com/documentation/accessibility/inspecting-the-accessibility-of-screens).
These and XCTest accessibility exposure are useful partial evidence, not actual
VoiceOver gestures, focus recovery or announcement acceptance. Apple's
[assistive-technology guide](https://developer.apple.com/documentation/accessibility/performing-accessibility-testing-for-your-app)
describes physical VoiceOver testing; newer toolchains may add Simulator support,
so hardware is not asserted as a universal prerequisite. No toolchain download or
system VoiceOver activation was attempted in this bounded task.

### Exact remaining manual checks

Use only **TeamStats UI TEST** and clearly labeled TEST ONLY games. Preserve the
original app/data; do not reset or uninstall anything to recover automation.

1. Rotate native Settings first and confirm content settles in landscape. Then
   rotate the test app on each device: inspect header, notice/disclosure, both
   modes, columns and keyboard Save; return to portrait. Sideways portrait is not
   a pass. Check the hidden horizontal indicator while actively panning; current
   captures/source establish the modifier and reachable columns, not every frame.
2. With actual isolated local services and the verified synthetic account, open
   the dedicated TEST ONLY shared scoring game → Player box scores. Enter
   points4/threes made7, other makes blank: expect at least21. Switch modes,
   confirm4/7 remain and require server Save confirmation. Do not complete/publish.
3. Turn Reduce Motion ON and visibly confirm it; repeat entry navigation,
   counters, scrolling and Save. Expect usable native controls. Restore the
   previous setting afterward.
4. Use a supported VoiceOver-capable Simulator/toolchain or separately authorized
   physical test build for actual screen-reader acceptance: player/stat/value
   labels, missing versus zero, counter bounds, reading order and disclosure.
   Editing must retain focus without repeated notice announcements; discrepancies
   stay saveable. Inspector speech alone does not pass this check.

Actual26.0 and physical-device testing remain deferred. No release-readiness claim.
