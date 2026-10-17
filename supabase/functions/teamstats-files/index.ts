// Development relay only. The worker independently rechecks live Auth and team
// authority; no service-role credential or Storage URL crosses this boundary.
const maximumBytes = 10 * 1024 * 1024;
const identifier = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}";
const upload = new RegExp(`^/uploads/${identifier}(/reconcile)?$`);
const delivery = new RegExp(`^/files/${identifier}$`);
const publicErrors = new Set([
  "rate_limited", "admission_unavailable",
  "access_denied", "verified_session_required", "route_not_found", "invalid_identity",
  "upload_interrupted_reconcile", "upload_size_mismatch_reconcile", "upload_not_stored_start_new_operation",
  "durable_bytes_unconfirmed_reconcile", "upload_size_limit", "bounded_content_length_required",
  "delivery_operation_required", "delivery_integrity_failed", "provider_operation_unconfirmed",
  "validation_unavailable", "validation_resource_limit", "validator_busy", "validator_receipt_mismatch",
  "operation_unconfirmed_reconcile", "capacity_unavailable", "private_file_capacity_unknown",
  "unsupported_type", "encrypted_pdf", "malformed_file", "resource_limit", "unsupported_codec",
  "duration_limit", "dimension_limit", "size_limit", "active_content", "unreadable_content",
  "invalid_request", "unreadable", "invalid_pdf", "active_pdf", "validator_unavailable",
  "invalid_video", "dimensions_limit", "file_validation_failed",
]);

function error(status: number, code: string, retryAfter?: string): Response {
  const headers = new Headers({ "Cache-Control": "no-store" });
  if (retryAfter && /^[0-9]{1,4}$/.test(retryAfter) && Number(retryAfter) >= 1 && Number(retryAfter) <= 3600) {
    headers.set("Retry-After", retryAfter);
  }
  return Response.json({ error: code }, { status, headers });
}

async function boundedBody(stream: ReadableStream<Uint8Array> | null, maximum: number, signal: AbortSignal): Promise<Uint8Array> {
  if (!stream) return new Uint8Array();
  const reader = stream.getReader();
  const abort = () => { void reader.cancel().catch(() => {}); };
  signal.addEventListener("abort", abort, { once: true });
  const parts: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      signal.throwIfAborted();
      const next = await reader.read();
      signal.throwIfAborted();
      if (next.done) break;
      length += next.value.byteLength;
      if (length > maximum) throw new Error("bounded_body");
      parts.push(next.value);
    }
    const result = new Uint8Array(length);
    let offset = 0;
    for (const part of parts) { result.set(part, offset); offset += part.byteLength; }
    return result;
  } finally {
    signal.removeEventListener("abort", abort);
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

export async function handle(request: Request, configuredWorker: string | undefined, transport: typeof fetch = fetch): Promise<Response> {
  // No hosted fallback. Unknown validator hosting/capacity must remain unavailable.
  if (configuredWorker !== "http://127.0.0.1:55448") return error(503, "file_delivery_not_configured");
  const url = new URL(request.url);
  const path = url.pathname.replace(/^(?:\/functions\/v1)?\/teamstats-files(?=\/)/, "");
  const isUpload = request.method === "POST" && upload.test(path) && url.search === "";
  const operation = url.searchParams.getAll("operation");
  const isDelivery = request.method === "GET" && delivery.test(path) &&
    [...url.searchParams.keys()].length === 1 && operation.length === 1 &&
    new RegExp(`^${identifier}$`).test(operation[0]);
  if (!isUpload && !isDelivery) return error(404, "route_not_found");
  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ") || authorization.length <= 7 || authorization.length > 16384) {
    return error(401, "verified_session_required");
  }
  const controller = new AbortController();
  const cancel = () => controller.abort();
  request.signal.addEventListener("abort", cancel, { once: true });
  const deadline = setTimeout(() => controller.abort(), 90000);
  try {
    if (request.signal.aborted) controller.abort();
    controller.signal.throwIfAborted();
    let body: Uint8Array | undefined;
    if (isUpload) {
      const declared = request.headers.get("Content-Length");
      if (declared !== null && (!/^[0-9]{1,9}$/.test(declared) || Number(declared) > maximumBytes)) {
        return error(413, "upload_size_limit");
      }
      body = await boundedBody(request.body, path.endsWith("/reconcile") ? 0 : maximumBytes, controller.signal);
      if (declared !== null && Number(declared) !== body.byteLength) return error(400, "upload_length_disagrees");
    }
    const headers = new Headers({ Authorization: authorization });
    if (body !== undefined) {
      headers.set("Content-Length", String(body.byteLength));
      headers.set("Content-Type", request.headers.get("Content-Type") ?? "application/octet-stream");
    }
    const reply = await transport(configuredWorker + path + url.search, {
      method: request.method, body, headers, redirect: "error", signal: controller.signal,
    });
    const count = reply.headers.get("Content-Length");
    const limit = isDelivery && reply.ok ? maximumBytes : 16384;
    if (count !== null && (!/^[0-9]{1,9}$/.test(count) || Number(count) > limit)) {
      await reply.body?.cancel();
      return error(502, "file_response_unconfirmed");
    }
    const bytes = await boundedBody(reply.body, limit, controller.signal);
    if (count !== null && Number(count) !== bytes.byteLength) return error(502, "file_response_unconfirmed");
    if (!reply.ok) {
      let code = "operation_unconfirmed_reconcile";
      try {
        const failure = JSON.parse(new TextDecoder().decode(bytes));
        if (failure !== null && typeof failure === "object" && Object.keys(failure).length === 1 &&
            typeof failure.error === "string" && publicErrors.has(failure.error)) code = failure.error;
      } catch { /* Unexpected provider bodies stay private. */ }
      return error(reply.status, code, reply.status === 429 ? reply.headers.get("Retry-After") ?? undefined : undefined);
    }
    const responseHeaders = new Headers({ "Cache-Control": "no-store", "Content-Length": String(bytes.byteLength) });
    for (const name of ["Content-Type", "X-TeamStats-SHA256"]) {
      const value = reply.headers.get(name);
      if (value !== null) responseHeaders.set(name, value);
    }
    return new Response(bytes, { status: reply.status, headers: responseHeaders });
  } catch {
    return error(503, "operation_unconfirmed_reconcile");
  } finally {
    clearTimeout(deadline);
    request.signal.removeEventListener("abort", cancel);
  }
}

if (import.meta.main) {
  Deno.serve((request: Request) => handle(request, Deno.env.get("TEAMSTATS_LOCAL_FILE_GATEWAY")));
}
