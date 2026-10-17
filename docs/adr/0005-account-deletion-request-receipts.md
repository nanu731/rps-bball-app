# ADR0005: Account-deletion request receipts without execution

Status: adopted for source/local preparation2026-10-17. Existing/hosted activation
and deletion execution are not authorized by this decision.

The owner asks to distinguish technical request/confirmation from unresolved
retention, ownership-transfer and legal policy. Recording an authenticated request
is useful without guessing those policies, provided the app does not imply that
any deletion is scheduled, processed or completed.

Use one immutable server receipt per account, with server-generated UUID and time.
Commands accept no account/team/contact/status parameters and derive identity from
a verified live Auth session. Team admission, capability and owner labels do not
limit eligibility. The receipt lives in the private RLS-enabled schema; no direct
client table access or administrator inbox is introduced. Repeated/concurrent
create-or-return commands preserve the original receipt. Account-level uniqueness
makes a separate persisted client operation identifier unnecessary.

The app asks for explicit confirmation and acknowledges only a validated server
receipt belonging to the initiating account/session. Lost or cancelled replies
remain unconfirmed; explicit readback reconciles the same receipt before another
submission. No automatic write replay. Account changes/sign-out fence late replies
and hide receipt state. Missing server capability is unavailable, not success.

The account remains active. No Auth deletion, record removal, owner transfer,
notification, worker or deletion-state transition exists. Retention and eventual
access policy for the receipt itself also need owner approval. This preparation
is not legal compliance or a verified operational deletion process. Actual execution,
shared-history attribution, ownership handling, backup retention and a private
handling/reporting route remain release prerequisites.

Alternatives: claiming deletion or scheduling would exceed authority; adding a
client identifier or processing queue adds no required capability; waiting for
all execution policy would leave the independent technical intake unprepared.
Five role-based Council perspectives and five peer reviews supported the narrow
receipt boundary; reused reviewers were label-anonymized, not strictly anonymous.
