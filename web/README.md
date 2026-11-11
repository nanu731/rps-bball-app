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
- **Executed checkpoint evidence**: 12 domain/server unit checks and eight
  Chrome browser checks passed, including phone/tablet layouts, synthetic local
  durability and an actual signed isolated Auth/PostgREST pending-create recovery.
  Broader signed multi-role practice/capture/manual journeys and final independent
  UI acceptance remain in progress. Auth stand-in SQL tests are separate from
  signed-user evidence. No hosted or real-device acceptance is inferred.

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
