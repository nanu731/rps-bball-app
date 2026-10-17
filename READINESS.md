# Remaining TeamStats work

Reconciled2026-10-17 against PRD.md, the private111-item reliability audit and
latest TESTING.md evidence. This is the current remaining-work list; historical
TODOs already resolved by adopted contracts are not new requirements. Source,
documentation, simulated provider responses and deployment acceptance are distinct.
No release-readiness claim is made.

| Category | Remaining work and evidence required |
| --- | --- |
| Independently actionable engineering/product | Close demonstrated defects from remaining acceptance, not another redesign. Pinned-package notices and a finite official advisory review are prepared in DEPENDENCIES.md. Defensive client compatibility checks passed at their public seams. Account-deletion request intake is source/local tested; execution/handling policy and existing-server activation remain open. Verify release-specific compatibility and recovery boundaries. Export scheduling preparation now has local evidence; a trusted export-only identity and renewable-credential contract still need verification before delivery. No broker, Redis, enterprise monitoring or full offline sync is justified. |
| Provider/configuration | Migrations14/15 and account-request migration16 remain unactivated on existing application/hosted databases. Verify hosted Auth expiry, refresh/reuse/revocation, rate/sender and signing-key procedures. Keep the local failed immediate-family-lockout assertion separate from passed extra-grace rejection. Establish a verified$0 runtime/capacity/validator/ingress contract before media delivery, including patched Storage/Imgproxy and actual hosted-version evidence from DEPENDENCIES.md. Google needs runtime identity/OAuth, protected operational ranges/latest view, fresh billing/quotas proof and actual nonproduction automated-delivery acceptance. Email delivery/sender and any genuinely free phone delivery remain gates; SMS stays disabled. Verify hosted database/Auth recovery and Storage bytes separately. |
| Owner policy/content | Actual roster and branding/assets/official color; representative filled forms and authorized Hudl/media examples/rights. Approve deletion execution, ownership/shared-history handling and request/backup retention; choose a private handling route. Select private encrypted backup destination/access holder, retention and acceptable data loss/downtime. Choose incident reporting route, notification owner and response commitments. Define pilot participants/criteria, whether automated Sheets delivery is required for the first pilot, and distribution. Never convert temporary identities into real ones. |
| Device/accessibility and real inputs | Actual iPhone/iPad landscape geometry; iPad Reduce Motion manual horizontal pan/active-pan indicator and transition acceptance (accessibility-directed far-right reachability passed); actual VoiceOver interaction separately from Inspector evidence. Physical-device and actual26.0 checks remain deferred. Validate representative real-form OCR/review and authorized Hudl/media behavior; synthetic fixtures do not pass those gates. Preserve already accepted save/wrapping/shared-draft checks unless changed. |
| Release-only | Verify signed distribution artifacts, final privacy/support content and pilot acceptance; exercise compatibility/rollback/forward-fix verification without destructive data reversal. Obtain explicit owner release approval. Unsigned archives, runbooks and passing synthetic CI are preparation, not distribution or production acceptance. |

Scheduler activation and real Google delivery remain disabled. No schedule was
registered. Hosted monitoring, crash reporting and alerts remain unavailable;
choosing notification policy does not implement them. Full shared-data offline
synchronization remains deferred. No bootstrap, production action, real-record
export or original-app replacement is part of this preparation.

Detailed evidence: [TESTING.md](TESTING.md), [exports.md](supabase/exports.md),
[NETWORK.md](NETWORK.md), [OPERATIONS.md](OPERATIONS.md),
[RECOVERY.md](RECOVERY.md), [PRD.md](PRD.md).
