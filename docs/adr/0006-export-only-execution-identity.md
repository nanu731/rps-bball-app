# ADR0006: Export-only execution identity preparation

Date:2026-10-17. Status: source/local preparation; activation gated.

## Problem and decision

The disabled worker's broad service credential was also its API key. Prepare a
NOLOGIN/NOINHERIT/NOBYPASSRLS role permitted to execute exactly claim, claimed
reserve, acknowledge and record-failure commands. No table access, destination
configuration, manual resume or ordinary app commands. Preserve existing trusted
service-role administration compatibility. Four explicit grants are insufficient:
the migration aborts on unexpected effective PUBLIC permissions or a role-name
collision. Roles are cluster-wide; synthetic verification uses a new cluster.

A trusted PostgREST authenticator may SET this role without inheriting/administering
it. The gateway must verify the signed credential and restrict its role/audience.
SQL additionally requires the worker role, authenticated audience, integer issued/
expiry times, at most15-minute lifetime and30-second future issuance tolerance.
These technical bounds are preparation defaults, not a delivery SLO. SQL claim
fixtures cannot prove signatures, issuer trust, revocation or hosted role mapping.

The runtime supplies separate publishable API key and worker bearer token in explicit
worker mode. Explicit legacy service-role mode remains compatible; missing/rejected
worker credentials never fall back. No signer, Auth worker account or renewal
service is added. Credential issuance/renewal/revocation and custody remain gates.

## Consequences and limits

The execution credential can process the project's accepted export outbox and
attest a readback receipt. It is not per-team/per-job isolation or proof against a
malicious trusted worker. Existing immutable reservations and claim fences remain.
Confirmed backend denial stops further commands; an uncertain provider write is
recovered through a later authorized claim and readback. Google denial is distinct:
a still-authorized backend can record that fixed failure before stopping the run.
No universal exactly-once promise, live delivery, schedule or provider activation.

Council considered a dedicated Auth account, new signer/gateway and retaining only
a broad key. Five perspectives plus peer review favored the smaller role/transport
boundary;3 advisers were reused, so this was not a strictly anonymous council.
