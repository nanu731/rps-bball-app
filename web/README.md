# TeamStats web pilot

Responsive React/TypeScript workspace using the existing maroon sports-ledger
visual direction. The native project remains preserved legacy work.

## Run locally

Node 22.12 or later. Exact dependencies are pinned in the lockfile.

```sh
npm ci --prefix web --ignore-scripts
npm --prefix web run dev
npm --prefix web test
npm --prefix web run build
npm --prefix web run test:browser
```

Browser tests use an already installed Chrome through Playwright. No provider,
Google, SMS, schedule or production deployment is enabled by these commands.
Public Supabase URL/publishable-key configuration can be supplied through the
connection screen or `.env.local`; privileged keys are rejected. Never commit
private configuration or real records.

## Boundaries and current evidence

- **Browser-local**: practice plans and print/PDF, configurable nine shooting
  spots, FT conditioning, versioned collection templates, player/team court
  capture, corrections/Undo, running reference clock, and independent manual
  box scores, paired possessions and player paint touches. Local and explicitly
  labeled synthetic-demo ledgers are separate. Neither uploads automatically.
- **Existing shared contracts**: verified Auth, active membership and current
  server authority, protected owner administration, manual dataset draft/save,
  independent completion, submission, review, accepted viewing and correction.
- **Prepared new shared contract**: migration `202611110001_web_sessions.sql`
  and ADR0009 define practice/capture snapshots, explicit recorder/clock authority,
  immutable publication history and duplicate-safe operation receipts. The web
  bridge fails closed if unavailable. This migration is **not activated hosted**.
- **Executed checkpoint evidence**: 13 domain/server checks and focused Chrome
  journeys exercise local/demo durability, actual signed isolated Auth/PostgREST
  practice/capture review, the four independent manual datasets, accepted viewing,
  denied visibility, correction lineage, clock assignment, interrupted replies and
  remount recovery. A fresh isolated PostgreSQL cluster replayed all 21 source
  migrations and passed 64 SQL checks using Auth platform stand-ins. Signed-user
  browser evidence is separate. Final rendered acceptance is being reconciled;
  no hosted or real-device acceptance is inferred.

Blank counts remain missing; explicit zero stays zero. Scoring contradictions are
calm, nonblocking draft guidance. Recorded shots do not establish complete game
coverage or replace manually entered statistics. New collection definitions require
coach input; placeholders are not approved basketball rules.

Local browser saves require Web Locks and revision checks. Browser storage can be
lost; explicit recovery download/import is not a hosted backup or full offline
synchronization. Shared uncertain writes retain their original operation for
receipt lookup/reconciliation, rather than silently resubmitting a new mutation.

`shared-local.spec.ts` skips without an ignored private synthetic loopback fixture.
It must never be pointed at real student records or a hosted project. Physical
hardware, actual screen-reader interaction, other browsers, coaching protocol,
real roster/brand assets, hosted migration compatibility/activation and release
acceptance remain distinct gates.

## Activation remains separate

Do not apply the prepared migration automatically. Recheck the intended hosted
baseline, exposure/RLS, current permissions, native-client handling of new capability
names and migration dependencies before any authorized activation. Local replay of
21 source migrations does not prove a hosted upgrade from its older baseline.

No email/SMS sender, Google/media service, recurring task or deployment is activated.
Coach rules, real roster/branding, pilot participants/roles, browser/device rehearsal,
backup/access/retention/recovery and privacy/deletion policy remain owner decisions.
Actual mobile software keyboards, screen readers and Safari require separate
acceptance; a reduced Chrome viewport and accessibility tree are useful proxies.
