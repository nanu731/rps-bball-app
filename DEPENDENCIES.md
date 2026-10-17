# Dependency readiness

Reviewed2026-10-17. This inventory is evidence of specific pins and advisory
checks, not a complete vulnerability assessment or permission to activate services.

## Native packages

The committed `Package.resolved` and exact Xcode package requirement remain the
source of truth. All seven cached checkout HEADs matched their pins and had no
tracked modifications during this review. No package was upgraded.

| Package | Pin | License |
| --- | --- | --- |
| supabase-swift |2.55.3|MIT|
| swift-asn1 |1.7.3|Apache-2.0|
| swift-clocks |1.1.1|MIT|
| swift-concurrency-extras |1.4.1|MIT|
| swift-crypto |4.5.2|Apache-2.0|
| swift-http-types |1.8.0|Apache-2.0|
| xctest-dynamic-overlay |1.13.1|MIT|

`TeamStats/ThirdPartyNotices.txt` retains the pinned packages' verbatim root
licenses and NOTICE files as an app resource. Recheck its inclusion in each signed
distribution artifact and review platform-specific linked components before release.
Server/development tools have separate licenses; they are not app dependencies.

The pins exceed the patched versions in the reviewed upstream advisories:
[Crypto RSA](https://github.com/apple/swift-crypto/security/advisories/GHSA-8q93-f6xh-4f6f),
[Crypto X-Wing](https://github.com/apple/swift-crypto/security/advisories/GHSA-9m44-rr2w-ppp7),
[ASN.1](https://github.com/apple/swift-asn1/security/advisories/GHSA-w8xv-rwgf-4fwh).
[Supabase2.55.4](https://github.com/supabase/supabase-swift/releases/tag/v2.55.4)
contains an admin-invitation correction; this client does not invoke that privileged
operation. A newer release alone does not justify changing a verified pin.

## Isolated runtime findings and activation gates

The official [CLI2.120.0 catalog](https://github.com/supabase/cli/blob/v2.120.0/packages/stack/src/Artifacts.ts)
selects Postgres17.11.0.004-r1, PostgREST16.4, Auth2.197.0, Mailpit1.31.3,
Storage1.79.36, Edge Runtime1.77.4 and Imgproxy3.26.0. This is a local catalog,
not evidence of any hosted project's versions.

Storage1.79.36 is affected by the upstream
[signed-resumable overwrite advisory](https://github.com/supabase/storage/security/advisories/GHSA-8rrf-w776-x75g)
(patched1.80.2) and
[Iceberg S3 authorization advisory](https://github.com/supabase/storage/security/advisories/GHSA-67rp-h2mf-ph72)
(patched1.80.1). RLS alone does not stop the signed-resumable bypass. Keep this
runtime restricted to isolated loopback synthetic fixtures. Before external delivery,
verify a patched official runtime and rerun affected authorization/upload tests.
Do not expose this cached version or infer that hosted Storage is patched.

Imgproxy3.26.0 falls within upstream advisory ranges for
[0.0.0.0 SSRF](https://github.com/imgproxy/imgproxy/security/advisories/GHSA-j2hp-6m75-v4j4),
[CGNAT SSRF](https://github.com/imgproxy/imgproxy/security/advisories/GHSA-8w7m-q6hg-mfqm)
and [SVG sanitization](https://github.com/imgproxy/imgproxy/security/advisories/GHSA-96f3-j94p-x9jv).
Reachability depends on enabled source URLs/formats; no exploit test was performed.
Some current advisory prose and patched-version metadata disagree. Verify the
selected replacement's source/fix rather than assuming a version label settles it.
No existing service was upgraded, exposed or activated by this review.

The accepted complete media archives match their recorded official SHA-256
receipts. An incomplete original Edge Runtime download remains retained as failed
download evidence; only its successfully verified retry was accepted. Their SPDX manifests list aggregate archives, not complete transitive
component inventories. Preserve their associated notices (including LGPL media
components) and separately review distribution obligations if packaging those tools.
Private Poppler development tooling has its own GPL/composite notices. Python/Node,
Xcode/macOS and deployment runtime inventories must be rechecked for the actual
release environment; this review does not establish complete transitive coverage.

## Minimal free maintenance procedure

Review official upstream advisories monthly, whenever pins/runtime versions change,
and before activation/release. Record package/revision, affected range, reachable
feature, disposition, evidence date and owner of any unresolved gate. Verify official
origin, checksum/pin, license and disk space before replacing tools; run affected
regressions. Do not automatically upgrade or claim “no vulnerabilities” from this
finite review. Public CI uses pinned read-only actions and no private credentials;
its passing checks do not perform an advisory scan or hosted version attestation.
