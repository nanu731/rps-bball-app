# Separate PDF validation service — preparation only

This directory's new service program is licensed **AGPL-3.0-or-later**, including
`index.ts`, `engine.ts` and its `supabase/prepare_pdf_validator.py` build tool; see LICENSE. It uses Artifex MuPDF1.28.6 under the same
license. This does not assert that another connected component is exempt from
AGPL obligations, relicense existing TeamStats code, or establish legal compliance.
The owner approved preparation and licensing review; activation is not approved.
The commercial-license option is excluded by the $0 budget.

`supabase/prepare_pdf_validator.py` verifies the exact official npm SHA-512, copies
only named runtime/type/license files to a new destination and preserves the
upstream notices. It runs no install scripts. Supply the retained official archive
for an offline build, or let it fetch only the pinned npm URL. Generated vendor
bytes must not enter the frontend bundle or private fixtures/public diagnostics.

The engine inspects reachable PDF dictionaries, including indirect objects and
streams, rejects the same active keys as the native validator, bounds depth100 /
100,000 visited nodes / decoded streams64MiB / pages500 / input5MiB, and rasterizes
every page to512px. Repairs/warnings and errors fail closed. Its1500ms in-engine
elapsed bound supplements the platform's required256MiB /2-second CPU hard limits;
a synchronous native/WASM call cannot be interrupted by a JavaScript timer. Complex
valid documents can be refused. A process-limit failure is not a valid receipt.
This is document validation, not malware scanning or real-form acceptance.

The service reads no application database, Auth users or Storage objects. An
appropriately protected worker must still verify the live signed user's authority,
reserve capacity, bind immutable bytes, reconcile Storage readback, and commit a
trusted receipt. A client-supplied validator result never authorizes those writes.
No existing gateway is switched to this service by preparing it.

Before ANY deployment/activation, review:

1. AGPL obligations, complete corresponding-source/build instructions (including
   native MuPDF and relevant third-party source), notices and the remote-user
   source offer. Upstream: <https://github.com/ArtifexSoftware/mupdf> and
   <https://mupdf.readthedocs.io/en/latest/license.html>. A public wrapper alone is
   not a compliance conclusion. Verify the exact source revision/build provenance
   corresponding to the pinned npm WASM, not a guessed release tag.
2. An immutable, actually published source URL for this exact service revision.
   `TEAMSTATS_PDF_SOURCE_URL` must be its40-character commit URL. `/source` exposes
   the offer; source configuration must be checked, not treated as automatic proof.
3. Verified Free capacity, function bundle/static-WASM packaging and platform
   limits. No provider, overage, billing or deployment is enabled by this source.
4. Private interservice authorization and the platform JWT gateway contract.
   `TEAMSTATS_PDF_VALIDATION_KEY` is a server-only secret, never a frontend value;
   a provider-valid service JWT may be required by the outer gateway. No disabling
   of provider JWT checks is authorized here. Requests need the exact bearer key.
5. Explicit `TEAMSTATS_PDF_ENABLED=reviewed_nonproduction`, after separate approval.
   Default/absent configuration returns503 without importing the parser. `/health`
   deliberately does not claim readiness before that activation gate is implemented
   and verified. One in-process lease prevents concurrent parses in that worker;
   it is not a distributed request-rate limit or a spending cap.

Local synthetic parser/runtime evidence and actual hosted availability remain
separate. Hosted PDF delivery remains disabled. No credentials, original files,
student data or actual provider replies belong in source/tests/logs.

## Verified artifact-to-source reference

The official npm1.28.6 metadata records gitHead
`da5f5eb890d7b3fb76903160b5f7f48ba1301492`. Its
[upstream source](https://github.com/ArtifexSoftware/mupdf/tree/da5f5eb890d7b3fb76903160b5f7f48ba1301492),
[package manifest](https://github.com/ArtifexSoftware/mupdf/blob/da5f5eb890d7b3fb76903160b5f7f48ba1301492/platform/wasm/package.json),
[build script](https://github.com/ArtifexSoftware/mupdf/blob/da5f5eb890d7b3fb76903160b5f7f48ba1301492/platform/wasm/tools/build.sh)
and `.gitmodules` were independently read. The package version/license match; the
build pins Emscripten4.0.8 and links MuPDF plus its third-party library. A source
offer must cover the pinned recursive submodule sources/licenses and build scripts,
not only JavaScript wrappers. We have not rebuilt the C engine byte-for-byte.

Prepared local eszip including static WASM measured10,574,388bytes. This is a local
bundle measurement, not successful hosted deployment/capacity evidence. The Mac
Edge runtime explicitly reports its CPU timer unavailable (Linux required); do not
claim hard2-second CPU enforcement from those tests. Linux CPU/memory behavior and
actual target capacity remain activation gates. The engine's elapsed checks can
refuse a complex valid500-page document; a final synthetic request after a resource
refusal must still be tested in the actual deployment runtime.

Remote-user source-offer visibility from the eventual upload flow and connected-
component licensing remain review items. No prepared configuration is a verified
source offer until its exact published revision and all source references work.

Encryption is rejected even when it opens without a user password: the engine
checks the trailer encryption dictionary, not only `needsPassword()`. The empty-
user-password regression initially produced a valid receipt and now returns
`encrypted_pdf`, matching the existing native validator. The opt-in
`supabase/tests/pdf_validator_engine_integration.ts` exercises the actual prepared
engine with synthetic plaintext and both encryption modes, invalid/cancelled input
and same-engine recovery; it does not establish Edge hard-limit enforcement.
