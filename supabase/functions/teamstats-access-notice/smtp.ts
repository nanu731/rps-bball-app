// Official server-only artifact, locked to its approved SHA512 in deno.lock.
import nodemailer from "npm:nodemailer@10.6.0";
import type { Mail, MailSettings, Delivery } from "./index.ts";
export async function deliver(
  mail: Mail,
  settings: MailSettings,
  signal: AbortSignal,
): Promise<Delivery> {
  const transport = nodemailer.createTransport({
    host: settings.host,
    port: settings.port,
    secure: true,
    auth: { user: settings.user, pass: settings.password },
    tls: {
      rejectUnauthorized: true,
      ...(settings.local && settings.ca ? { ca: settings.ca } : {}),
    },
    connectionTimeout: 5000,
    greetingTimeout: 5000,
    socketTimeout: 10000,
    dnsTimeout: 5000,
    logger: false,
    debug: false,
    disableFileAccess: true,
    disableUrlAccess: true,
    maxRecipients: 1,
  });
  try {
    const result = await transport.sendMail({ ...mail, signal });
    return result.accepted?.length === 1 && result.rejected?.length === 0
      ? "sent"
      : "uncertain";
  } catch (error) {
    const e = error as {
      code?: string;
      responseCode?: number;
      command?: string;
    };
    if (e.code === "EAUTH" || e.code === "ECONFIG" || e.responseCode === 535)
      return "configuration";
    if (e.responseCode && e.responseCode >= 400 && e.responseCode < 500)
      return "transient";
    if (e.responseCode && e.responseCode >= 500 && e.responseCode < 600)
      return "permanent";
    // Nodemailer can label a post-DATA disconnect CONN; only explicit refusals are replay-safe.
    return "uncertain";
  } finally {
    transport.close();
  }
}
