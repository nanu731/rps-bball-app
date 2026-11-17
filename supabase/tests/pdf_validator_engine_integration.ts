// Opt-in actual prepared MuPDF engine checks; synthetic documents only.
// Deno run --allow-read=<prepared-directory> this-file <prepared-directory>.
// This is not Edge hard-limit, hosted, licensing or real-form acceptance.
if (!Deno.args[0])
  throw Error("An explicitly prepared service directory is required");
const root = new URL("file://" + Deno.realPathSync(Deno.args[0]) + "/");
const { validatePDF } = await import(new URL("engine.ts", root).href);
const mupdf = await import(new URL("vendor/mupdf/dist/mupdf.js", root).href);
function assert(value: boolean, label: string) {
  if (!value) throw Error(label);
}
function fixture(options = "") {
  const doc = new mupdf.PDFDocument();
  try {
    const page = doc.addPage(
      [0, 0, 100, 100],
      0,
      {},
      "0 0 1 rg 0 0 10 10 re f",
    );
    try {
      doc.insertPage(-1, page);
    } finally {
      page.destroy();
    }
    const buffer = doc.saveToBuffer(options);
    try {
      return new Uint8Array(buffer.asUint8Array());
    } finally {
      buffer.destroy();
    }
  } finally {
    doc.destroy();
  }
}
const plain = fixture(),
  signal = new AbortController().signal;
const receipt = await validatePDF(plain, signal);
assert(
  receipt.valid &&
    receipt.byte_count === plain.length &&
    receipt.details.page_count === 1,
  "Readable synthetic PDF receipt",
);
for (const user of ["", "TEST_ONLY_READER"]) {
  const bytes = fixture(
    `encrypt=aes-256,owner-password=TEST_ONLY_OWNER,user-password=${user}`,
  );
  if (!user) {
    const doc = mupdf.Document.openDocument(bytes, "application/pdf").asPDF();
    try {
      assert(
        !doc.needsPassword(),
        "Fixture must demonstrate encryption without a required user password",
      );
    } finally {
      doc.destroy();
    }
  }
  const result = await validatePDF(bytes, signal);
  assert(
    !result.valid && result.failure_reason === "encrypted_pdf",
    "All encrypted PDFs must be rejected",
  );
}
const invalid = await validatePDF(
  new TextEncoder().encode("TEST ONLY not a PDF"),
  signal,
);
assert(!invalid.valid, "Invalid bytes cannot become a receipt");
const controller = new AbortController();
controller.abort();
assert(
  !(await validatePDF(plain, controller.signal)).valid,
  "Cancelled validation cannot become a receipt",
);
const recovered = await validatePDF(plain, signal);
assert(
  recovered.valid && recovered.sha256 === receipt.sha256,
  "Same engine recovers without changing bytes",
);
console.log(
  "PASS actual prepared engine: readable receipt, both encryption modes denied, invalid/cancelled denied and recovery",
);
