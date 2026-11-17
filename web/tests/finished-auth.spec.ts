import { test, expect } from "@playwright/test";
import { readFileSync, existsSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { randomUUID } from "node:crypto";
const file = process.env.TEAMSTATS_FINISHED_FIXTURE;
const f =
  file && existsSync(file) ? JSON.parse(readFileSync(file, "utf8")) : null;
test.skip(
  !f,
  "Requires the private finished-experience synthetic loopback fixture.",
);
test("actual verified signup, owner-confirmed role admission, recovery and account-switch isolation", async ({
  page,
  context,
  browser,
}) => {
  test.setTimeout(120000);
  if (!f.syntheticOnly || f.apiRoot !== "http://127.0.0.1:55873")
    throw Error("Isolated fixture required");
  const email =
    "test-only-password-" + randomUUID().slice(0, 8) + "@example.invalid";
  const password = f.actors.player.password + "A",
    replacement = f.actors.player.password + "B";
  await context.addInitScript(
    (config) =>
      localStorage.setItem(
        "teamstats-web-public-config",
        JSON.stringify(config),
      ),
    { url: f.apiRoot, key: f.publishableKey },
  );
  const mailLink = async (subject: string) => {
    let link = "";
    await expect
      .poll(() => {
        const mailbox = dirname(file!) + "/mailbox.local.jsonl";
        const messages = existsSync(mailbox)
          ? readFileSync(mailbox, "utf8")
              .trim()
              .split("\n")
              .map((x) => JSON.parse(x))
          : [];
        const mail = messages
          .reverse()
          .find(
            (m) => m.recipients.includes(email) && m.data.includes(subject),
          );
        const decoded = mail?.data
          .replace(/=\r?\n/g, "")
          .replace(/=([A-Fa-f0-9]{2})/g, (_: string, code: string) =>
            String.fromCharCode(parseInt(code, 16)),
          );
        link =
          decoded?.match(/href="([^"]+)"/)?.[1]?.replaceAll("&amp;", "&") ?? "";
        return !!link;
      })
      .toBe(true);
    const target = new URL(link);
    if (target.origin !== f.apiRoot || target.pathname !== "/auth/v1/verify")
      throw Error("Unexpected test confirmation destination");
    await page.evaluate((target) => location.assign(target), link);
  };
  const signIn = async (
    target: typeof page,
    address: string,
    value: string,
  ) => {
    await target
      .getByRole("button", { name: "Sign in", exact: true })
      .first()
      .click();
    await target.getByLabel("Email", { exact: true }).fill(address);
    await target.getByLabel("Password", { exact: true }).fill(value);
    await target
      .locator("form")
      .getByRole("button", { name: "Sign in", exact: true })
      .click();
  };
  const verifiedAccount = async (target = page) => {
    const summary = target.locator(".account-details > summary");
    await expect(summary).toContainText("verified");
    if (
      !(await target.getByText("Account verified", { exact: true }).isVisible())
    )
      await summary.click();
    await expect(
      target.getByText("Account verified", { exact: true }),
    ).toBeVisible();
  };
  await page.goto("/");
  await page
    .getByRole("button", { name: "Create account", exact: true })
    .click();
  const surname = "Applicant " + randomUUID().slice(0, 8);
  await page.getByLabel("First name", { exact: true }).fill("TEST ONLY");
  await page.getByLabel("Last name", { exact: true }).fill(surname);
  await page
    .getByRole("combobox", { name: "Requested role", exact: true })
    .selectOption("manager");
  await page.getByLabel("Email", { exact: true }).fill(email);
  await page.getByLabel("Password", { exact: true }).fill(password);
  await page
    .getByLabel("Confirm password", { exact: true })
    .fill(password + "x");
  await page
    .locator("form")
    .getByRole("button", { name: "Create account", exact: true })
    .click();
  await expect(page.getByRole("alert")).toContainText("do not match");
  await page.getByLabel("Confirm password", { exact: true }).fill(password);
  await page
    .locator("form")
    .getByRole("button", { name: "Create account", exact: true })
    .click();
  await expect(page.getByRole("status")).toContainText("Check your email");
  await signIn(page, email, password);
  await expect(page.getByRole("alert")).toContainText(
    "Verify your email first",
  );
  const protectedReads: string[] = [];
  const recordProtected = (r: import("@playwright/test").Request) => {
    const u = new URL(r.url());
    if (
      u.pathname.startsWith("/rest/v1/") &&
      ![
        "/rest/v1/rpc/web_signup_status",
        "/rest/v1/rpc/web_request_access",
      ].includes(u.pathname)
    )
      protectedReads.push(u.pathname);
  };
  page.on("request", recordProtected);
  await mailLink("Confirm");
  await verifiedAccount();
  await expect(
    page.getByRole("heading", { name: "Awaiting owner approval", exact: true }),
  ).toBeVisible();
  const ownRequest = () =>
    page.evaluate(
      async ({ apiRoot, key }) => {
        const session = JSON.parse(
          localStorage.getItem("teamstats-web-auth:" + apiRoot)!,
        );
        const reply = await fetch(apiRoot + "/rest/v1/rpc/web_signup_status", {
          method: "POST",
          headers: {
            apikey: key,
            Authorization: "Bearer " + session.access_token,
            "Content-Type": "application/json",
          },
          body: "{}",
        });
        if (!reply.ok) throw Error("Synthetic applicant status unavailable");
        return reply.json();
      },
      { apiRoot: f.apiRoot, key: f.publishableKey },
    );
  const firstRequest = await ownRequest();
  expect(firstRequest.request.requested_role).toBe("manager");
  expect(firstRequest.has_access).toBe(false);
  await page.reload();
  await expect(
    page.getByRole("heading", { name: "Awaiting owner approval", exact: true }),
  ).toBeVisible();
  expect((await ownRequest()).request.id).toBe(firstRequest.request.id);
  const evidence = process.env.TEAMSTATS_EVIDENCE;
  for (const width of [390, 1024, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await page.emulateMedia({
      colorScheme: width === 1024 ? "dark" : "light",
      reducedMotion: "reduce",
    });
    await page.evaluate(
      () => (document.documentElement.style.fontSize = "125%"),
    );
    const preview = page.getByRole("region", {
      name: "Data-free TeamStats preview",
    });
    await expect(
      preview.getByText("Preview — no team data", { exact: true }),
    ).toBeVisible();
    await preview
      .getByRole("button", { name: "Practice preview", exact: true })
      .click();
    await expect(
      preview.getByText("Practice-plan template", { exact: true }),
    ).toBeVisible();
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth),
    ).toBe(width);
    await page
      .getByRole("button", { name: "Check approval status", exact: true })
      .focus();
    await expect(
      page.getByRole("button", { name: "Check approval status", exact: true }),
    ).toBeFocused();
    if (evidence) {
      mkdirSync(evidence, { recursive: true });
      await page.screenshot({
        path: evidence + `/pending-${width}.png`,
        fullPage: true,
      });
    }
  }
  expect(protectedReads).toEqual([]);
  page.off("request", recordProtected);
  const denied = await page.evaluate(
    async ({ apiRoot, key, team }) => {
      const session = JSON.parse(
        localStorage.getItem("teamstats-web-auth:" + apiRoot)!,
      );
      return (
        await fetch(apiRoot + "/rest/v1/rpc/stats_open_draft", {
          method: "POST",
          headers: {
            apikey: key,
            Authorization: "Bearer " + session.access_token,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            p_team_id: team,
            p_game_id: crypto.randomUUID(),
            p_dataset_type: "box_scores",
          }),
        })
      ).status;
    },
    { apiRoot: f.apiRoot, key: f.publishableKey, team: f.team },
  );
  expect(denied).toBe(403);
  // Distinct actual signed owner, not administrator SQL, confirms a different role.
  const ownerContext = await browser.newContext({
    viewport: { width: 1024, height: 900 },
  });
  await ownerContext.addInitScript(
    (config) =>
      localStorage.setItem(
        "teamstats-web-public-config",
        JSON.stringify(config),
      ),
    { url: f.apiRoot, key: f.publishableKey },
  );
  const owner = await ownerContext.newPage();
  await owner.goto("/");
  await signIn(
    owner,
    f.actors.owner.session.user.email,
    f.actors.owner.password,
  );
  const account = owner
    .locator("summary")
    .filter({ hasText: "Account and team" });
  await expect(account).toContainText("verified");
  if (
    !(await owner
      .getByRole("combobox", { name: "Team", exact: true })
      .isVisible())
  )
    await account.click();
  await owner
    .getByRole("combobox", { name: "Team", exact: true })
    .selectOption(f.team);
  await owner.locator("summary").filter({ hasText: "Team access" }).click();
  await owner.getByRole("button", { name: "Manage team", exact: true }).click();
  const applicant = owner
    .locator("#access-requests article")
    .filter({ hasText: surname });
  await expect(applicant).toHaveCount(1);
  await expect(
    applicant.getByRole("button", {
      name: "Approve selected role",
      exact: true,
    }),
  ).toBeDisabled();
  await applicant.getByRole("combobox").selectOption("player");
  await applicant.getByRole("checkbox").check();
  if (evidence)
    await owner.screenshot({
      path: evidence + "/owner-review.png",
      fullPage: true,
    });
  await applicant
    .getByRole("button", { name: "Approve selected role", exact: true })
    .click();
  await expect(applicant).toContainText("Confirmed role: player");
  await page
    .getByRole("button", { name: "Check approval status", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "Published results", exact: true }),
  ).toBeVisible();
  const approved = await ownRequest();
  expect(approved.request.id).toBe(firstRequest.request.id);
  expect(approved.request.confirmed_role).toBe("player");
  expect(approved.has_access).toBe(true);
  expect(
    await page
      .getByRole("button", { name: "Manage team", exact: true })
      .count(),
  ).toBe(0);
  await ownerContext.close();
  await page.evaluate(() => (document.documentElement.style.fontSize = "100%"));
  await page.reload();
  await verifiedAccount();
  await page
    .getByRole("button", { name: "Sign out of this browser", exact: true })
    .click();
  await expect(
    page.getByRole("heading", { name: "Sign in to TeamStats", exact: true }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "Reset password", exact: true })
    .click();
  await page.getByLabel("Email", { exact: true }).fill(email);
  const firstResetAt = Date.now();
  await page
    .getByRole("button", { name: "Request reset email", exact: true })
    .click();
  await expect(page.getByRole("status")).toContainText("reset link");
  await mailLink("Reset");
  await expect(
    page.getByRole("heading", { name: "Choose a new password", exact: true }),
  ).toBeVisible();
  await page.getByLabel("New password", { exact: true }).fill(replacement);
  await page.getByLabel("Confirm password", { exact: true }).fill(replacement);
  let writes = 0;
  page.on("request", (r) => {
    if (r.method() === "PUT" && r.url().endsWith("/auth/v1/user")) writes++;
  });
  const second = await context.newPage();
  await second.goto("/");
  await verifiedAccount(second);
  await second
    .getByRole("button", { name: "Sign out of this browser", exact: true })
    .click();
  await signIn(
    second,
    f.actors.player.session.user.email,
    f.actors.player.password,
  );
  await expect(second.locator(".account-details > summary")).toContainText(
    "verified",
  );
  await expect(
    page.getByRole("button", { name: "Save new password", exact: true }),
  ).toHaveCount(0);
  expect(writes).toBe(0);
  await second.locator(".account-details > summary").click();
  await second
    .getByRole("button", { name: "Sign out of this browser", exact: true })
    .click();
  await second.close();
  await expect(
    page.getByRole("heading", { name: "Sign in to TeamStats", exact: true }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "Reset password", exact: true })
    .click();
  await page.getByLabel("Email", { exact: true }).fill(email);
  // Respect the explicitly configured one-second local SMTP frequency.
  await expect.poll(() => Date.now() - firstResetAt).toBeGreaterThan(1500);
  const oldMail = readFileSync(
    dirname(file!) + "/mailbox.local.jsonl",
    "utf8",
  ).length;
  const resetReply = page.waitForResponse((r) =>
    r.url().includes("/auth/v1/recover"),
  );
  await page
    .getByRole("button", { name: "Request reset email", exact: true })
    .click();
  expect((await resetReply).status()).toBe(200);
  await expect(page.getByRole("status")).toContainText("reset link");
  await expect
    .poll(
      () =>
        readFileSync(dirname(file!) + "/mailbox.local.jsonl", "utf8").length,
    )
    .toBeGreaterThan(oldMail);
  await mailLink("Reset");
  await page.getByLabel("New password", { exact: true }).fill(replacement);
  await page.getByLabel("Confirm password", { exact: true }).fill(replacement);
  await page
    .getByRole("button", { name: "Save new password", exact: true })
    .click();
  await verifiedAccount();
  await expect(page.getByRole("status")).toContainText("Password updated");
  expect(writes).toBe(1);
  await page
    .getByRole("button", { name: "Sign out of this browser", exact: true })
    .click();
  await signIn(page, email, password);
  await expect(page.getByRole("alert")).toContainText("Sign-in failed");
  await signIn(page, email, replacement);
  await verifiedAccount();
  expect(
    await page.evaluate(
      (secret) =>
        Object.values(localStorage).some((value) => value.includes(secret)),
      replacement,
    ),
  ).toBe(false);
  writeFileSync(
    dirname(file!) + "/password-journey.local.json",
    JSON.stringify({ syntheticOnly: true, email, password: replacement }),
    { mode: 0o600 },
  );
  await page
    .getByRole("button", { name: "Sign out of this browser", exact: true })
    .click();
  if (evidence) {
    mkdirSync(evidence, { recursive: true });
    for (const width of [390, 1024, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      await page.emulateMedia({
        colorScheme: width === 1024 ? "dark" : "light",
        reducedMotion: "reduce",
      });
      expect(
        await page.evaluate(() => document.documentElement.scrollWidth),
      ).toBe(width);
      await page.screenshot({
        path: evidence + `/signin-${width}.png`,
        fullPage: true,
      });
    }
  }
});
