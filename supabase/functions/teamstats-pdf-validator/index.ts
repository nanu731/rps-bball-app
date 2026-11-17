// SPDX-License-Identifier: AGPL-3.0-or-later
// This isolated service does not read Auth users, application records or Storage.
let active = false;
const response = (status: number, body: unknown, headers = {}) =>
  Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store", ...headers },
  });
async function sameSecret(actual: string, expected: string) {
  const digest = (value: string) =>
    crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  const [a, b] = await Promise.all([digest(actual), digest(expected)]);
  return (
    new Uint8Array(a).reduce(
      (difference, value, i) => difference | (value ^ new Uint8Array(b)[i]),
      0,
    ) === 0
  );
}
export async function handle(
  request: Request,
  settings: { enabled?: string; key?: string; source?: string },
) {
  const path = new URL(request.url).pathname;
  const source =
    settings.source &&
    /^https:\/\/github\.com\/nanu731\/rps-bball-app\/tree\/[a-f0-9]{40}\/supabase\/functions\/teamstats-pdf-validator$/.test(
      settings.source,
    )
      ? settings.source
      : null;
  if (request.method === "GET" && path.endsWith("/source"))
    return response(200, {
      license: "AGPL-3.0-or-later",
      corresponding_source: source,
      upstream:
        "https://github.com/ArtifexSoftware/mupdf/tree/da5f5eb890d7b3fb76903160b5f7f48ba1301492",
      build_tool:
        source
          ?.replace("/tree/", "/blob/")
          .replace(
            "/functions/teamstats-pdf-validator",
            "/prepare_pdf_validator.py",
          ) ?? null,
      version: "1.28.6",
      status: source
        ? "Source review required before deployment"
        : "Not configured for deployment",
    });
  if (request.method === "GET" && path.endsWith("/health"))
    return response(503, {
      liveness: "alive",
      readiness: "disabled_until_reviewed_activation",
    });
  if (request.method !== "POST" || !path.endsWith("/validate"))
    return response(404, { error: "route_not_found" });
  if (
    settings.enabled !== "reviewed_nonproduction" ||
    !settings.key ||
    settings.key.length < 32 ||
    !source
  )
    return response(503, { error: "validation_unavailable" });
  const authorization = request.headers.get("Authorization") ?? "";
  if (
    authorization.length > 16384 ||
    !(await sameSecret(authorization, "Bearer " + settings.key))
  )
    return response(403, { error: "access_denied" });
  if (active)
    return response(503, { error: "validator_busy" }, { "Retry-After": "1" });
  const declared = request.headers.get("Content-Length");
  if (
    declared !== null &&
    (!/^\d{1,8}$/.test(declared) || Number(declared) > 5 * 1024 * 1024)
  )
    return response(413, { error: "size_limit" });
  active = true;
  const controller = new AbortController(),
    cancel = () => controller.abort(),
    timer = setTimeout(cancel, 15000);
  request.signal.addEventListener("abort", cancel, { once: true });
  const reader = request.body?.getReader();
  try {
    if (request.signal.aborted) controller.abort();
    const abort = () => {
      void reader?.cancel().catch(() => {});
    };
    controller.signal.addEventListener("abort", abort, { once: true });
    const parts: Uint8Array[] = [];
    let size = 0;
    try {
      while (reader) {
        controller.signal.throwIfAborted();
        const next = await reader.read();
        controller.signal.throwIfAborted();
        if (next.done) break;
        size += next.value.length;
        if (size > 5 * 1024 * 1024)
          return response(413, { error: "size_limit" });
        parts.push(next.value);
      }
    } finally {
      controller.signal.removeEventListener("abort", abort);
    }
    if (declared !== null && size !== Number(declared))
      return response(422, { error: "invalid_request" });
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const part of parts) {
      bytes.set(part, offset);
      offset += part.length;
    }
    const { validatePDF } = await import("./engine.ts");
    const result = await validatePDF(bytes, controller.signal);
    return response(result.valid ? 200 : 422, result);
  } catch {
    return response(503, { error: "validation_unavailable" });
  } finally {
    clearTimeout(timer);
    request.signal.removeEventListener("abort", cancel);
    await reader?.cancel().catch(() => {});
    reader?.releaseLock();
    active = false;
  }
}
if (import.meta.main)
  Deno.serve((request) =>
    handle(request, {
      enabled: Deno.env.get("TEAMSTATS_PDF_ENABLED"),
      key: Deno.env.get("TEAMSTATS_PDF_VALIDATION_KEY"),
      source: Deno.env.get("TEAMSTATS_PDF_SOURCE_URL"),
    }),
  );
