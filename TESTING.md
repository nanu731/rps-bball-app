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
| Locally verified | Recorded successful fixture or actual loopback execution; specify which |
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

The synthetic export-worker suite uses Python's standard library:

```sh
python3 -m unittest discover -s supabase/tests -p test_sheets_export.py
```

It uses local HTTP fixtures. Passing does not establish Google worker access,
Sheets delivery, quotas or permissions. Keep real Google delivery disabled until
separately authorized/configured within the $0 budget.

## Current evidence and open gates

Source snapshot `737ca4a` includes the local checkpoint and polish work recorded
in [WORKFLOW.md](WORKFLOW.md) and subsystem documentation. No acceptance suite
was rerun to author these documents.

| Area | Recorded evidence | Still required |
|---|---|---|
| Native/local backend | Fixture suites and actual local Auth/SDK/SQL workflows recorded | Relevant regressions after source changes |
| Account hosted setup | Owner-confirmed sign-in/UUID comparison; trusted identity/session preflight recorded in implementation handoff | Hosted migration/grant/bootstrap execution and signed permission tests |
| Hosted activation | Guarded transaction prepared; not recorded as executed | Inspect migration-history grants/exposure; confirm execution and read back owner membership/audit |
| New UI/polish | Simulator builds and model regressions recorded | Both-device dirty navigation, delayed/failed Save, denied-content recovery, accessibility |
| Photos | Synthetic Vision and proposal checks recorded | Representative marked forms and picker/Apply/Cancel interaction |
| Google export | SQL/worker fixtures recorded; actual delivery disabled | Trusted sender/worker access and versioned Google readback |
| Media/scouting | Link metadata locally exercised; scouting planned | Private file upload/playback, provider rights, limits and report implementation |
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
