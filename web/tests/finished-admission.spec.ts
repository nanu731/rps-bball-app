import { test, expect, type Page } from "@playwright/test";
import { readFileSync, existsSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
const file = process.env.TEAMSTATS_ADMISSION_FIXTURE;
const f =
  file && existsSync(file) ? JSON.parse(readFileSync(file, "utf8")) : null;
test.skip(!f, "Requires a fresh private synthetic Auth/TLS SMTP fixture.");
test("uncertain owner email requires explicit recovery; authenticated review link never grants access", async ({
  page,
  browser,
}) => {
  test.setTimeout(60000);
  if (
    !f.syntheticOnly ||
    f.apiRoot !== "http://127.0.0.1:55945" ||
    !f.applicant.email.endsWith("@example.invalid")
  )
    throw Error("Isolated fixture required");
  const root = dirname(file!),
    mode = root + "/mode.local",
    mailbox = root + "/mailbox.local.jsonl";
  writeFileSync(mode, "uncertain");
  const configure = async (target: Page) =>
    target.addInitScript(
      (config) =>
        localStorage.setItem(
          "teamstats-web-public-config",
          JSON.stringify(config),
        ),
      { url: f.apiRoot, key: f.publishableKey },
    );
  const login = async (target: Page, email: string, password: string) => {
    await target
      .getByRole("button", { name: "Sign in", exact: true })
      .first()
      .click();
    await target.getByLabel("Email", { exact: true }).fill(email);
    await target.getByLabel("Password", { exact: true }).fill(password);
    await target
      .locator("form")
      .getByRole("button", { name: "Sign in", exact: true })
      .click();
  };
  const status = () =>
    page.evaluate(
      async (config) => {
        const s = JSON.parse(
          localStorage.getItem("teamstats-web-auth:" + config.url)!,
        );
        const reply = await fetch(
          config.url + "/rest/v1/rpc/web_signup_status",
          {
            method: "POST",
            headers: {
              apikey: config.key,
              Authorization: "Bearer " + s.access_token,
              "Content-Type": "application/json",
            },
            body: "{}",
          },
        );
        if (!reply.ok) throw Error("Synthetic status unavailable");
        return reply.json();
      },
      { url: f.apiRoot, key: f.publishableKey },
    );
  await configure(page);
  await page.goto("/");
  await login(page, f.applicant.email, f.applicant.password);
  await expect(
    page.getByRole("heading", { name: "Awaiting owner approval", exact: true }),
  ).toBeVisible();
  await expect
    .poll(async () => (await status()).request.notification)
    .toBe("manual_review");
  const request = (await status()).request;
  expect((await status()).has_access).toBe(false);
  await expect(
    page.getByRole("button", { name: "Retry owner notification", exact: true }),
  ).toHaveCount(0);
  const messages = () =>
    readFileSync(mailbox, "utf8")
      .trim()
      .split("\n")
      .map((x) => JSON.parse(x))
      .filter((x) => x.data.includes(request.id));
  expect(messages().length).toBe(1);
  const text = messages()[0]
    .data.replace(/=\r?\n/g, "")
    .replace(/=([A-Fa-f0-9]{2})/g, (_: string, n: string) =>
      String.fromCharCode(parseInt(n, 16)),
    );
  const reviewURL = text.match(/Sign in to review: (http[^\s]+)/)?.[1];
  expect(reviewURL).toBeTruthy();
  const target = new URL(reviewURL!);
  expect(target.origin).toBe("http://127.0.0.1:4173");
  expect(target.searchParams.get("reviewTeam")).toBe(f.team);
  expect(target.hash).toBe("#access-requests");
  await page.reload();
  await expect(
    page.getByRole("heading", { name: "Awaiting owner approval", exact: true }),
  ).toBeVisible();
  expect((await status()).request.id).toBe(request.id);
  expect(messages().length).toBe(1);
  const ownerContext = await browser.newContext({
    viewport: { width: 1024, height: 900 },
  });
  const owner = await ownerContext.newPage();
  await configure(owner);
  await owner.goto(reviewURL!);
  await login(owner, f.owner.email, f.owner.password);
  const section = owner.getByRole("region", { name: "Owner access requests" });
  await expect(section).toBeVisible();
  const row = section
    .locator("article")
    .filter({ hasText: f.applicant.last_name });
  await expect(row).toHaveCount(1);
  await expect(
    row.getByRole("button", { name: "Allow notification retry", exact: true }),
  ).toBeDisabled();
  await row
    .getByRole("checkbox", { name: /A prior email may have arrived/ })
    .check();
  writeFileSync(mode, "sent");
  await row
    .getByRole("button", { name: "Allow notification retry", exact: true })
    .click();
  await expect(row).toContainText("Notification accepted by the mail server");
  expect(messages().length).toBe(2);
  expect((await status()).has_access).toBe(false);
  const evidence = process.env.TEAMSTATS_EVIDENCE;
  if (evidence) {
    mkdirSync(evidence, { recursive: true });
    await owner.screenshot({
      path: evidence + "/owner-notification.png",
      fullPage: true,
    });
  }
  await owner.setViewportSize({ width: 390, height: 844 });
  await owner.emulateMedia({ colorScheme: "dark", reducedMotion: "reduce" });
  await owner.evaluate(
    () => (document.documentElement.style.fontSize = "200%"),
  );
  expect(await owner.evaluate(() => document.documentElement.scrollWidth)).toBe(
    390,
  );
  await row.getByRole("combobox").scrollIntoViewIfNeeded();
  await row.getByRole("combobox").focus();
  await expect(row.getByRole("combobox")).toBeFocused();
  if (evidence)
    await row.screenshot({ path: evidence + "/owner-request-390-large.png" });
  await row.getByRole("combobox").selectOption("player");
  await row
    .getByRole("checkbox", { name: /I verified this applicant/ })
    .check();
  await row
    .getByRole("button", { name: "Approve selected role", exact: true })
    .click();
  await expect(row).toContainText("Confirmed role: player");
  await page
    .getByRole("button", { name: "Check approval status", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "Published results", exact: true }),
  ).toBeVisible();
  expect((await status()).request.id).toBe(request.id);
  expect((await status()).request.confirmed_role).toBe("player");
  expect((await status()).has_access).toBe(true);
  await expect(
    page.getByRole("button", { name: "Manage team", exact: true }),
  ).toHaveCount(0);
  expect(messages().length).toBe(2);
  await ownerContext.close();
});
