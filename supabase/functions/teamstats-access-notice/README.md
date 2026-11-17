# Access-request email - disabled preparation

Server-only Nodemailer10.6.0, MIT-0, no runtime dependencies. The official npm
artifact's SHA-512 was independently checked; `deno.lock` pins that same integrity.
Upstream: https://github.com/nodemailer/nodemailer and
https://registry.npmjs.org/nodemailer/-/nodemailer-10.6.0.tgz.
No mail dependency or private configuration enters the frontend.

Migration202611170005 adds a disabled notification switch and service-only
claim/finish RPCs to the existing one-request/one-outbox-row admission contract.
The function verifies the ORIGINAL signed token through Auth, then binds its
actor/session/expiry to current database authority. Only the applicant or current
owner can trigger that saved request. Neither role, recipient nor content comes
from the HTTP body. Sending/retrying never grants membership. The review link
only navigates to current authenticated owner controls; GET never approves.

One60-second claim fences overlapping workers. Five explicit SMTP transient
refusals exhaust a retry cycle; persisted exponential backoff with jitter starts
at15-45 seconds. The next attempt requires an explicit user action after the
deadline; there is no schedule or busy polling. Configuration/permanent errors,
cancelled or uncertain sends, and expired leases require owner review. An owner
may explicitly start another cycle; possible prior delivery requires acknowledgment.
Audit retains that action. No universal exactly-once email claim is made.

A lost DATA reply can be reported by Nodemailer with command `CONN`; it is NOT
proof that nothing was sent. Only explicit SMTP4xx refusals are automatically
eligible for retry. Other network/cancellation outcomes are uncertain. A `sent`
receipt means accepted by the SMTP server, not confirmed inbox delivery. Stable
Message-ID does not establish recipient deduplication. Late replies cannot complete
a replacement claim. An unknown database finish is reconciled, never blindly resent.
Each run is one job, with bounded request/response bodies, a20-second work deadline
and a separate5-second finish allowance. Private job state holds sanitized failure
categories; the function emits no application logs. SMTP wire logging is disabled.

## Required private configuration before any activation

- Verify the intended signup team/owner, then configure the private database
  signup target and `notification_enabled`. Defaults remain unset/false.
- Verify the actual Free hosting envelope and zero-charge SMTP arrangement. Set
  `TEAMSTATS_JOIN_MAIL_ENABLED=reviewed_nonproduction` and
  `TEAMSTATS_JOIN_MAIL_BUDGET=reviewed_zero_cost` only after separate approval.
- Private `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`,
  `TEAMSTATS_SMTP_USER`, `TEAMSTATS_SMTP_PASSWORD`, `TEAMSTATS_OWNER_EMAIL`.
  Auth's existing SMTP password is not automatically this worker's configuration.
- Exact `TEAMSTATS_WEB_ORIGIN=https://teamstats-nonproduction.pages.dev`.
  Gmail uses implicit TLS465, verified certificates, short socket/connect deadlines,
  no attachments, external URL/file access or transport pooling. One recipient.
- Preserve the provider JWT gateway; test the real hosted function's authorization,
  runtime, quotas, secrets and callback/navigation contract before deployment.
  Configuration flags are operator attestations, not independent budget proof.

`TEAMSTATS_LOCAL_MAIL_TEST=synthetic_loopback` permits only loopback backend/web/
SMTP, with an explicit local port and private test CA. It must remain absent hosted.
No hosted service, sender credential, real delivery, membership or billing was
activated by preparation. Auth signup/ingress abuse protection remains a separate
provider gate; five sends per saved request are not an ingress-rate-limit claim.

## Scoped evidence

Injected worker tests cover disabled/denied/unavailable states, original-token
provenance, hidden destinations, bounded input, lost replies, cancellation and a
throwing diagnostic sink. Actual local TLS SMTP covered accepted,451 temporary
refusal, accepted bytes with a lost reply, and cancellation. Actual official local
Edge + signed Auth/PostgREST + TLS capture proved one email and no duplicate on
repeated calls. Compiled Chrome exercised uncertain delivery, explicit owner
recovery, the captured email's authenticated link and role confirmation.
Synthetic TLS capture is not Gmail delivery; local Edge is not hosted capacity.
