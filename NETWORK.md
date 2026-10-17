# Network, session and admission contracts

Bounded local preparation, reviewed against the pinned Supabase Swift2.55.3 source.
No provider activation, universal exactly-once guarantee or release approval.
Original local drafts/temporary identities remain separate and are never uploaded.

## Operation inventory

| Operation | Deadline / response bounds | Retry, cancellation and uncertain outcome |
| --- | --- | --- |
| Auth OTP, verification, PKCE exchange, refresh and logout | AccountHTTP:30-second monotonic fetch budget,15-second request inactivity,1MiB response per attempt; redirects refused | One transport send. Retryable HTTP failures/transport errors become a typed nonretryable error before the SDK interceptor. A missing reply is unconfirmed, not proof no code/session change occurred. Explicit sign-in/recovery remains available. |
| Auth identity GET `/auth/v1/user` | Same30-second total budget including body/backoff; up to3 responses, each≤1MiB | Only automatic application retry category:408/429/500/502/503/504/520–524/530 and selected transient transport failures. Full jitter on1/2-second exponential delays; valid Retry-After is a minimum. HTTP-date uses server Date when available. No retry if wait exceeds remaining budget;401/403 stop immediately. |
| Account verification | May refresh then fetch identity: up to two bounded Auth fetches | Official SDK coordinates simultaneous refresh by credential. Cancellation stops later requests/state publication. A waiter cancelled during the SDK's shared unstructured refresh may await its bounded flight; immediate waiter return is not proved. |
| Team discovery, administration, roster/contact/access | Actual SDK HTTP: production session15-second inactivity/30-second resource timeout. Paged reads100rows×≤50pages, identity reads limit1 | All database execute calls explicitly disable SDK automatic retry. Manual Reload; current server permissions required. Grants/admission/roster commands never replay blindly. Row bounds are not a hard JSON byte cap. |
| Shared game/statistics/history/recovery, plays and media metadata | Same SDK per-request limits and bounded pagination | Single-attempt RPCs, expected revisions and retained lineage. Lost replies require reload/readback and explicit validated recovery, not repeated publication/completion. A multi-page load has no single aggregate deadline; cancellation propagates to page requests, with shared-refresh qualification above. |
| Private upload/reconcile/delivery | Native production session90-second resource timeout;10MiB success stream maximum,64KiB receipt maximum,8KiB error prefix; redirects refused | No automatic retry, including GET delivery because it claims allowance. Stream task is cancelled on exit. Stable operation/version IDs; unknown upload requires explicit reconciliation. No guessed successful receipt. |
| File relay |90-second abort across input, fetch and output;≤10MiB input/success,16KiB error | Incoming cancellation reaches its controller. No replay; safe429 Retry-After forwarded. It buffers upload before worker admission, so this is not pre-ingress rate protection. |
| Trusted file worker | Accepted socket has90-second absolute I/O budget,30-second idle bound before header parsing; provider HTTP has30-second absolute socket I/O budget; parser CPU45s/wall60s plus existing memory/concurrency bounds | No provider write replay. Socket/relay expiry does not interrupt all worker computation or undo a committed operation. Later readback/reconcile remains required. |
| Export backend and Google adapter (disabled) |15-second default/30-second maximum request budget; Google payload≤1.9MB/response≤2.1MB, backend response≤5MB; Google≤20requests, run_once≤3jobs | Standard-library HTTP/TLS response deadlines stop slow continuous bodies. Redirects refused. No new automatic retry/backoff/scheduler. Immutable job binding/readback handles lost write replies. Provider429 remains a persisted/manual failure; no automatic Google activation. |
| Retained clip playback and OCR | Device-local retained complete bytes / on-device recognition | No network retry or background upload. External Hudl/Safari navigation is owned by that provider; no app transport guarantee is inferred. |

Per-request bounds do not claim a whole multi-page screen or whole export-run
latency guarantee. HTTPS connection establishment uses the standard platform
connect/TLS timeouts; DNS resolution has no separate application deadline. An
exhausted connection budget is checked before sending subsequent requests. Hosted
worker lifecycle/DNS enforcement remains an activation prerequisite, not a proved
whole-run guarantee.
The Python deadline helper never disables certificate/hostname verification.

## Session semantics

Access-token expiry, refresh-token rotation and JWT signing-key rotation are
separate. The official Auth client owns credential rotation/coalescing and durable
session storage. Supabase receives a current-token closure, not a captured token;
production private-file requests use that same Auth source. No second client may
refresh app credentials through `SupabaseClient.auth`.

Generation and actor checks fence old clients and late token results after account
changes. Confirmed refresh/session denial clears current context/offline authority;
transient failure preserves editing context and saved input. Cancellation cannot
publish late authentication. Known denial cleanup is scoped to its originating
generation so it cannot sign out a newer account. The pinned Supabase adapter
suppresses token-provider errors and may send an anonymous fallback request;
server RLS/commands must deny it. Tests establish denial/no actor data, not zero
outgoing requests. This client behavior is not a substitute for server enforcement.

[Supabase sessions](https://supabase.com/docs/guides/auth/sessions) document refresh
reuse exceptions. The actual isolated Authv2.197.0 runtime had rotation=true and a
10-second reuse interval. A grandparent refresh was rejected after that interval,
but an immediate subsequent child refresh returned200. The strict family-lockout
check remains failed. A separate new-account run waited an additional11 seconds
after rejection and then confirmed the child was rejected. This establishes a local
reuse-window boundary, not immediate lockout or hosted evidence. Signing-key rotation
was not performed. Expired access-token behavior has native synthetic evidence;
actual Auth expiry was not tested because no signing secret was exported.

## Durable file admission

Migration202610160001 adds a private, RLS-enabled counter and authenticated
`file_request_admission()` command. Server-derived `team_private.actor()` checks
verified identity, retained live session and token/session expiry; callers cannot
supply an actor or scope. One current row per actor combines upload, reconcile and
delivery attempts, with a provisional development limit of30 per60-second window.
The locked upsert saturates at31 rather than growing unbounded or overflowing.
Direct client/service-role counter access and anonymous command execution are revoked.
Fixed windows can permit bursts near their boundary; this is not a sliding limiter.

The gateway commits admission through its own RPC before worker body reads, parser
work, claims or Storage mutations. Malformed/unavailable admission fails closed;
denial returns429 with1–60second Retry-After. Never automatically replay admission:
a lost reply may retain a charge while no transfer began. Worker restarts/connections
cannot refund an active window. Normal window expiry reopens admission; no cleanup
or manual counter reset was added.

This coordinates only workers using the same authoritative database. It does not
rate-limit Auth, direct Data API commands, invalid-token ingress or relay buffering.
File size/concurrency/capacity admission does not itself establish request limiting
or protect provider billing. [Auth endpoint limits](https://supabase.com/docs/guides/auth/rate-limits)
and [Data API enforcement](https://supabase.com/docs/guides/api/securing-your-api)
are separate provider configuration/acceptance checks.

## Activation and remaining gates

The new migration is source/local-test only. No existing local Auth database or
hosted project was migrated or bootstrapped. Hosted file delivery, Google and SMS
remain disabled. Before any hosted file activation: review/apply the migration
through the trusted process; verify signed admission/denial and persisted charges;
ensure every worker uses it and the same database; review window limits, invalid-token/
relay ingress and direct-RPC protections; establish a verified$0 capacity/deployment
contract. An app limiter cannot prove zero provider overages.

Hosted Auth rate settings, delivery/sender limits, refresh/reuse/revocation and
signing-key procedures still require separate authorized verification. Diagnose the
local immediate-lockout result and its reuse-window boundary before relying on
that guarantee; do not silently change provider configuration to pass a test.

Recovery destination/access holder, retention, acceptable loss/downtime and reporting
route remain owner TODOs in RECOVERY.md. Hosted disaster recovery, actual landscape,
iPad Reduce Motion traversal/transitions, actual VoiceOver, physical devices and
actual26.0 remain open in TESTING.md. Performance, broader monitoring and automatic
export scheduling are outside this pass.

## Diagnostic observation —2026-10-16

Content-free Auth/shared/file outcomes and passive worker availability are defined
in [OPERATIONS.md](OPERATIONS.md). Confirmed denial, cancellation and uncertain
writes remain distinct. Output does not trigger retries, prove commitment or
change deadlines/current authority. No provider probe, activation or scheduler
is introduced; all activation and Auth reuse findings above remain open.

## Export retry boundary —2026-10-17

The export worker's durable scheduling policy is in [exports.md](supabase/exports.md).
This is a specific duplicate-safe immutable-reservation/readback protocol, not a
blanket transport retry policy. Token-fenced database replies do not cancel issued
Google requests. Shared run admission/request deadlines remain distinct from a
verified hard process/DNS bound. Disabled preflight consumes no claims; persisted
provider cooldown prevents restarting around Retry-After. No schedule/Google
activation or existing unapplied migration deployment occurred.

## Client compatibility checks2026-10-17

Five connected models now treat documented PostgREST JWT rejection codes301/302/303
as confirmed denial, reusing their concealment and authorized-reload behavior. SQL
42501 remains denied; PGRST300 (missing signing configuration) remains a server
failure. No error-message matching, automatic mutation retry or global credential
reset was introduced. See the [PostgREST error contract](https://docs.postgrest.org/en/v13/references/errors.html#group-3-jwt).

Synthetic SDK responses verify required-field/type/enum failures reject a complete
statistics snapshot, missing mandatory RPC/table does not become empty success,
and optional export failures preserve statistics. Additive fields remain compatible;
explicit Retry recovers. Media publication pointers must identify a version of the
same parent resource. These are client compatibility checks, not evidence of actual
hosted token expiry, signing-key rotation or migration activation. The earlier
immediate Auth reuse-lockout failure and additional-grace rejection remain unchanged.

Account-deletion intake uses the existing authenticated SDK transport bounds, one
read/submit attempt, no automatic write replay and explicit receipt readback after
uncertainty. Immutable account uniqueness is a server duplicate-safe contract, not
a universal exactly-once claim. Missing RPC is explicitly unavailable. Current
client-generation/account context fences late receipts; no local receipt cache or
authority is created. Source-only migration16 remains an activation prerequisite.


## Export credential boundary2026-10-17

Worker-mode PostgREST requests use a distinct publishable apikey and trusted
short-lived bearer. Configuration is explicit; no missing/denied narrow credential
falls back to service_role. Confirmed backend401/403/42501 stops the invocation
without a subsequent failure RPC. Uncertain applied provider writes retain their
reservation and recover through fenced claim expiry/backoff plus authorized
readback. Provider401/403 can be recorded through a still-authorized backend, then
halt the batch. Local synthetic SQL/HTTP evidence is separate from signed hosted
JWT mapping, refresh/renewal, signing-key rotation and real Google authorization.
The existing immediate Auth-reuse lockout failure and extra-grace rejection pass
are unchanged. No existing provider/service/transport or automatic retry activation.
