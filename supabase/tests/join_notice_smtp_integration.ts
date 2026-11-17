// Opt-in actual TLS SMTP seam; only synthetic loopback fixtures are accepted.
import { deliver } from "../functions/teamstats-access-notice/smtp.ts";
const file = Deno.env.get("TEAMSTATS_MAIL_TLS_FIXTURE");
if (!file) throw Error("Explicit private loopback fixture required");
const f = JSON.parse(await Deno.readTextFile(file));
if (
  f.syntheticOnly !== true ||
  f.settings.host !== "127.0.0.1" ||
  !f.settings.local ||
  f.mail.from !== "test-only-sender@example.invalid" ||
  f.mail.to !== "test-only-owner@example.invalid" ||
  !f.mail.text.includes("TEST ONLY")
)
  throw Error("Synthetic TLS fixture required");
const observed = await deliver(
  f.mail,
  f.settings,
  AbortSignal.timeout(f.timeout_ms ?? 5000),
);
if (observed !== f.expected) throw Error("SMTP outcome mismatch: " + observed);
console.log("PASS actual synthetic TLS SMTP outcome " + observed);
