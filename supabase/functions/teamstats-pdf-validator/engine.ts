// SPDX-License-Identifier: AGPL-3.0-or-later
// Separate validation-service program; see LICENSE and README.md.
// The preparation tool installs only the exact checksum-verified upstream artifact.
(
  globalThis as typeof globalThis & {
    $libmupdf_wasm_Module: { wasmBinary: Uint8Array };
  }
).$libmupdf_wasm_Module = {
  wasmBinary: await Deno.readFile(
    new URL("./vendor/mupdf/dist/mupdf-wasm.wasm", import.meta.url),
  ),
};
const mupdf = await import("./vendor/mupdf/dist/mupdf.js");
const forbidden = new Set([
  "A",
  "AA",
  "OpenAction",
  "JS",
  "JavaScript",
  "EmbeddedFiles",
  "EF",
  "XFA",
  "AcroForm",
  "RichMedia",
  "Movie",
  "Sound",
]);
export async function validatePDF(
  bytes: Uint8Array<ArrayBuffer>,
  signal: AbortSignal,
) {
  const deadline = performance.now() + 1500;
  let document: import("./vendor/mupdf/dist/mupdf.js").Document | undefined;
  let nodes = 0,
    warning = false;
  const check = () => {
    if (signal.aborted || performance.now() > deadline)
      throw Error("resource_limit");
  };
  mupdf.setLog({
    warning: () => {
      warning = true;
    },
    error: () => {
      warning = true;
    },
  });
  try {
    check();
    if (bytes.length < 5 || bytes.length > 5 * 1024 * 1024)
      throw Error("size_limit");
    if (new TextDecoder().decode(bytes.subarray(0, 5)) !== "%PDF-")
      throw Error("invalid_pdf");
    document = mupdf.Document.openDocument(bytes, "application/pdf");
    const pdf = document.asPDF();
    if (!pdf || pdf.needsPassword()) throw Error("encrypted_pdf");
    if (pdf.wasRepaired()) throw Error("invalid_pdf");
    const pages = pdf.countPages();
    if (pages < 1 || pages > 500) throw Error("resource_limit");
    const seen = new Set<number>();
    function walk(
      object: import("./vendor/mupdf/dist/mupdf.js").PDFObject,
      depth = 0,
    ) {
      check();
      if (++nodes > 100000 || depth > 100) throw Error("resource_limit");
      let resolved:
        import("./vendor/mupdf/dist/mupdf.js").PDFObject | undefined;
      try {
        if (object.isIndirect()) {
          const id = object.asIndirect();
          if (seen.has(id)) return;
          seen.add(id);
          resolved = object.resolve();
        }
        const value = resolved ?? object;
        if (object.isStream()) {
          const stream = object.readStream();
          try {
            if (stream.length > 64 * 1024 * 1024) throw Error("resource_limit");
          } finally {
            stream.destroy();
          }
        }
        if (value.isDictionary() || value.isArray())
          value.forEach(
            (
              child: import("./vendor/mupdf/dist/mupdf.js").PDFObject,
              key: string | number,
            ) => {
              try {
                if (typeof key === "string" && forbidden.has(key))
                  throw Error("active_pdf");
                walk(child, depth + 1);
              } finally {
                child.destroy();
              }
            },
          );
      } finally {
        resolved?.destroy();
      }
    }
    const trailer = pdf.getTrailer();
    try {
      const encryption = trailer.get("Encrypt");
      try {
        if (!encryption.isNull()) throw Error("encrypted_pdf");
      } finally {
        encryption.destroy();
      }
      walk(trailer);
    } finally {
      trailer.destroy();
    }
    for (let i = 0; i < pages; i++) {
      check();
      const page = pdf.loadPage(i);
      try {
        const box = page.getBounds(),
          width = box[2] - box[0],
          height = box[3] - box[1];
        if (
          !Number.isFinite(width) ||
          !Number.isFinite(height) ||
          width <= 0 ||
          height <= 0
        )
          throw Error("invalid_pdf");
        const scale = 512 / Math.max(width, height);
        const pixmap = page.toPixmap(
          mupdf.Matrix.scale(scale, scale),
          mupdf.ColorSpace.DeviceRGB,
          false,
          true,
        );
        try {
          if (!pixmap.asPNG().length) throw Error("invalid_pdf");
        } finally {
          pixmap.destroy();
        }
      } finally {
        page.destroy();
      }
    }
    check();
    if (warning) throw Error("invalid_pdf");
    const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
    check();
    return {
      valid: true,
      byte_count: bytes.length,
      sha256: Array.from(hash, (n) => n.toString(16).padStart(2, "0")).join(""),
      media_type: "application/pdf",
      details: { page_count: pages },
    };
  } catch (error) {
    const code = error instanceof Error ? error.message : "invalid_pdf";
    return {
      valid: false,
      failure_reason: [
        "size_limit",
        "resource_limit",
        "active_pdf",
        "encrypted_pdf",
      ].includes(code)
        ? code
        : "invalid_pdf",
    };
  } finally {
    document?.destroy();
  }
}
