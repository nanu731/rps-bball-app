import { test, expect } from "@playwright/test";
import { writeFileSync } from "node:fs";
test("diagnose document overflow around roster table", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  await page.getByRole("button", { name: "My drafts", exact: true }).click();
  await page
    .getByRole("button", { name: "Try sample demo", exact: true })
    .click();
  await page.getByRole("button", { name: /TEST ONLY opponent/ }).click();
  await page
    .getByRole("button", { name: "After-game stats", exact: true })
    .click();
  await page.getByRole("button", { name: "Roster table", exact: true }).click();
  const evidence = await page.evaluate(() => ({
    html: document.documentElement.scrollWidth,
    body: document.body.scrollWidth,
    inner: innerWidth,
    overflow: [...document.querySelectorAll("*")]
      .filter(
        (e) =>
          e.getBoundingClientRect().right > innerWidth + 2 &&
          !e.closest(".table-scroll"),
      )
      .map((e) => ({
        tag: e.tagName,
        classes: e.className,
        rect: {
          x: e.getBoundingClientRect().x,
          right: e.getBoundingClientRect().right,
          width: e.getBoundingClientRect().width,
        },
        overflow: getComputedStyle(e).overflowX,
        display: getComputedStyle(e).display,
        minWidth: getComputedStyle(e).minWidth,
      })),
  }));
  writeFileSync(
    "../.scratch/teamstats-web/layout-probe.local.json",
    JSON.stringify(evidence, null, 2),
  );
  expect(evidence.html).toBeLessThanOrEqual(evidence.inner);
});
