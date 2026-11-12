import { test, expect } from "@playwright/test";
import { mkdirSync } from "node:fs";
const evidence = process.env.TEAMSTATS_EVIDENCE;
test("large text, keyboard focus, reduced viewport and every roster column remain reachable", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 540 });
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  await page
    .getByRole("button", { name: "Try sample demo", exact: true })
    .click();
  await page.getByRole("button", { name: /TEST ONLY opponent/ }).click();
  await page
    .getByRole("button", { name: "After-game stats", exact: true })
    .click();
  await page.addStyleTag({ content: ":root {font-size:24px}" });
  await page.getByLabel("Points", { exact: true }).fill("4");
  await page.getByLabel("Threes made", { exact: true }).fill("7");
  await expect(page.getByText("Check scoring", { exact: true })).toBeVisible();
  const focused = page.getByLabel("Threes made", { exact: true });
  await focused.focus();
  await expect
    .poll(() =>
      focused
        .evaluate((e) => ({
          bottom: e.getBoundingClientRect().bottom,
          dock: document.querySelector(".save-dock")!.getBoundingClientRect()
            .top,
        }))
        .then((r) => r.bottom <= r.dock),
    )
    .toBe(true);
  const save = page.getByRole("button", {
    name: "Save in this browser",
    exact: true,
  });
  await expect(save).toBeInViewport();
  await save.click();
  await expect(
    page.getByText("Sample data saved in this browser only.", {
      exact: true,
    }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Roster table", exact: true }).click();
  const input = page.getByLabel("TEST ONLY Player B Free throws missed", {
    exact: true,
  });
  await input.focus();
  await expect(input).toBeInViewport();
  const fit = await input.evaluate((e) => {
    const style = getComputedStyle(e);
    const c = document.createElement("canvas").getContext("2d")!;
    c.font = style.font;
    return {
      text:
        c.measureText("Not entered").width +
        parseFloat(style.paddingLeft) +
        parseFloat(style.paddingRight),
      available: e.clientWidth,
    };
  });
  expect(fit.text).toBeLessThanOrEqual(fit.available);
  await input.fill("0");
  await save.click();
  await expect(save).toBeDisabled();
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(
    390,
  );
  const snapshot = await page.locator("main").ariaSnapshot();
  expect(snapshot).toContain("Check scoring");
  expect(snapshot).toContain("Save in this browser");
  if (evidence) {
    mkdirSync(evidence, { recursive: true });
    await page.screenshot({
      path: evidence + "/phone-large-text-focused-viewport.png",
      fullPage: false,
    });
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.screenshot({
      path: evidence + "/phone-large-text-short-viewport.png",
      fullPage: true,
    });
  }
});
