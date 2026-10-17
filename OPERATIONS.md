# Operational diagnostics

## Purpose and boundaries

Content-free operation evidence helps distinguish denial, unavailable services,
cancellation and uncertain replies. It is separate from basketball statistics,
security audit history, product analytics and crash reporting. No automatic support
upload, persistent cross-user identifier, diagnostic export or support interface is
added. Application records and security-audit retention are unchanged.

Existing useful signals include typed UI errors, pending/reconciliation states,
server-confirmed command/readback receipts and export-job states. Those remain the
source for user recovery; diagnostics are lossy supporting evidence, never an
acknowledgment that a write committed or that access is authorized.

## Native evidence

`OperationDiagnostics` sends closed JSON envelopes to Apple's unified logging,
subsystem `org.teamstats.diagnostics`, category `operations`. Categories cover Auth
transport/session failures, shared snapshot loads/draft saves, file transport and
file-operation failures. Transport timing is not end-to-end sign-in timing; file
model failures have no duration. One shared load may include several requests.

Only category, outcome, sanitized failure, optional rounded durationMS and capped
attempts are accepted. No arbitrary diagnostic message/context parameter exists.
No credentials, headers/tokens, email/phone, user/student/game/team identifiers,
names/numbers, statistical values, OCR text, filenames/paths, media bytes,
invitation codes, URLs/query strings or raw provider errors enter envelopes.
No correlation ID is needed for this scope. OS metadata such as process/time is
platform-owned and outside the application envelope.

A locked volatile buffer holds at most64 events. Entries expire after15minutes on
next recording/inspection; there is no timer or app-owned log file. At most32
output emissions/minute and one queued/running emitter bound overhead. Busy sinks
suppress output rather than delaying saves; sink failures are swallowed and counted.
Counters saturate at9999. Rounded durations cap at one hour and attempts at three.
Account boundaries clear the buffer and fence old spans/pending emissions. An
already executing sink and previously emitted OS logs cannot be recalled. Reset
does not reset the emission budget. OS retention/deletion is controlled by the
platform, not the15-minute volatile-buffer policy.

Trusted operators can inspect this subsystem in macOS Console for the connected
Simulator/device; filter before inspecting. No developer log access grants app or
backend authority. Inspect only needed envelopes, keep captures private, and avoid
sharing an entire OS log archive. In-memory snapshots are an internal test/debug
seam, not a new user-facing privilege. Core operations neither wait for output nor
transmit evidence. Diagnostic loss/suppression and process termination are expected.

## Worker evidence and availability

The standard-library worker recorder uses the same closed five-field shape
(`duration_ms` in Python). File processing/export runs record safe terminal
outcomes. Unknown write replies/cancellation remain unconfirmed, not successful;
confirmed denials/refusals retain their sanitized category. Existing authenticated
commands, job states and uncertain-result recovery still determine next actions.
Failed CLI arguments/startup and unexpected HTTP-handler errors use fixed text or
envelopes instead of raw exception/argument dumps. These boundaries do not sanitize
arbitrary output from external tools or uninstrumented code.

The process-local deque is64 events/15minutes, lazily expired, with32emissions/minute,
one active sink and one queued output. A daemon emits stderr through a direct descriptor write, avoiding Python buffered
stderr locks during interpreter shutdown. A blocked descriptor can still lose
evidence at exit; sink failure/queue
saturation cannot break processing. CLI exit waits at most50ms for output; a killed
process can lose evidence. Capturing stderr requires operator-selected private
retention; no file rotation, external collector or retention policy is activated.

The existing loopback file gateway adds exact GET `/health/live` (200, process
alive) and `/health/ready` (503, passive status). The hosted relay does not expose
these routes. Both worker CLIs support `--status`; it reads local prerequisites,
performs no provider request, and exits3 because work readiness is not established.
Responses contain fixed status labels only, no configuration values or counts:

- `disabled`: the operation's enable flag is off.
- `configuration_unavailable`: required private prerequisites are missing/invalid.
- `downstream_unavailable`: a buffered unavailable failure occurred in the last60s;
  another invalid request does not erase it. This is a recent observation, not an
  active outage probe; bounded buffer eviction/restart/expiry can lose it.
- `not_verified`: configuration presence/liveness establishes neither current
  credentials, authorized work, capacity nor a verified$0 deployment contract.

Authorization remains `per_operation`. There is deliberately no “ready” result:
no passive signal can prove all activation gates. HTTP503 is appropriate even when
the process is alive. No health endpoint starts workers, admits work, tests tokens,
loads bytes, activates delivery or grants access. Export status is process-local,
not a hosted endpoint or scheduler. Startup errors may prevent a CLI report at all.

## Incident procedure

1. Identify affected environment, operation and whether the outcome is confirmed,
   denied or uncertain. Separate local drafts from shared/server-authoritative data.
2. Preserve minimal safe envelopes, app version/source revision and approximate
   time privately. Do not collect credentials, content or a full device archive.
3. Contain impact: stop dependent work/keep services disabled; preserve unsaved
   drafts, current permissions and records. Do not replay an uncertain mutation.
4. Recover using existing readback/reconciliation/Retry and RECOVERY.md. Get owner
   approval for destructive/provider actions. A Git revert does not restore data.
5. Verify current authorization, exact saved identity/receipt and relevant failure
   regression in isolation before resuming. Never turn missing evidence into success.
6. Record cause, scope, recovery evidence and remaining gaps without private content.

`TODO_INCIDENT_REPORTING_ROUTE`, `TODO_INCIDENT_NOTIFICATION_OWNER` and
`TODO_INCIDENT_RESPONSE_COMMITMENTS` require owner decisions. Backup destination,
access holder, retention and recovery objectives remain TODOs in RECOVERY.md.

## Unavailable capabilities

No verified crash collection/symbolication, crash-free rate, alerts/on-call delivery,
hosted uptime monitoring, reliability target or SLO is established. No commercial
monitoring, provider activation or automatic export scheduling is included. Native
OS logging availability is not proof of crash reporting or diagnostic delivery.
Hosted file/Google/SMS services remain disabled; migration14 is not activated.

NETWORK.md retains both local Auth reuse findings: immediate child rejection after
reused-grandparent denial failed; rejection after an additional grace interval
passed. Hosted Auth/refresh/signing-key behavior remains an activation gate.
TESTING.md keeps actual landscape, iPad Reduce Motion traversal/transitions, actual
VoiceOver, physical-device and actual26.0 checks open. Hosted disaster recovery is
unverified; synthetic evidence does not establish production monitoring or readiness.

## Export scheduling preparation —2026-10-17

[exports.md](supabase/exports.md) now defines durable eligibility, bounded retries,
provider cooldown, fenced claims and explicit trusted manual recovery. The
scheduled-once entry is disabled by default and registers no recurring job.
Preflight budget/credentials precede claims. Provider throttles stop the invocation
and persist across processes; no diagnostic signal activates a worker. Owner-only
export status is distinct from private processing diagnostics and statistical
acceptance. No raw provider delay/header/body is logged; only bounded timing or
fixed categories enter diagnostics. [READINESS.md](READINESS.md) consolidates the
remaining PRD/audit gates. Real Google delivery and scheduler activation stay off.


## Export-only credential preparation2026-10-17

Use explicit worker mode with separate publishable API key and bounded worker bearer
for the prepared role; legacy service-role mode must be explicitly selected and
retains broad authority. Credentials are injected privately for each invocation;
no signer or automatic refresh service is installed. Passive status checks presence
only, never authenticates or claims readiness. Confirmed backend denial is a fixed
`denied` diagnostic with uncertain outcome, not delivery success. It stops further
commands. Preserve the reservation; verify a fresh authorized invocation reconciles
readback after existing lease/backoff. Provider denial is distinct and may require
trusted manual review/resume. Never blindly resubmit a potentially applied write.
Migrations14–17 and actual scheduling/delivery remain unactivated. Before activation,
verify hosted mapping, signature/issuer/audience, least-privilege issuance/renewal/
revocation, custody, Google destination rights and the current strict$0 arrangement.
