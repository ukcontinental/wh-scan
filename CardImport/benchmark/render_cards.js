#!/usr/bin/env node
// Renders HTML business-card files to PNG with Playwright Chromium.
// Usage: node render_cards.js jobs.json [results.json]
// results.json receives {out: fitScale} where fitScale<1 means window.__fit shrank text to avoid overflow.
// jobs.json = [{"html": "/abs/card.html", "out": "/abs/card.png", "width": 1050, "height": 600}, ...]
// All jobs are rendered in ONE browser session (one context, deviceScaleFactor 2).
'use strict';
const fs = require('fs');
const path = require('path');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');

(async () => {
  const jobsFile = process.argv[2];
  if (!jobsFile) { console.error('usage: node render_cards.js jobs.json'); process.exit(2); }
  const jobs = JSON.parse(fs.readFileSync(jobsFile, 'utf8'));
  const browser = await chromium.launch({ args: ['--font-render-hinting=none', '--disable-lcd-text'] });
  const context = await browser.newContext({ deviceScaleFactor: 2, viewport: { width: 1050, height: 600 } });
  const page = await context.newPage();
  let n = 0;
  const results = {};
  for (const job of jobs) {
    await page.setViewportSize({ width: job.width, height: job.height });
    const html = fs.readFileSync(job.html, 'utf8');
    await page.setContent(html, { waitUntil: 'load' });
    await page.evaluate(() => document.fonts.ready);
    results[job.out] = await page.evaluate(() => (window.__fit ? window.__fit() : 1));
    fs.mkdirSync(path.dirname(job.out), { recursive: true });
    await page.screenshot({ path: job.out, clip: { x: 0, y: 0, width: job.width, height: job.height }, animations: 'disabled' });
    n++;
  }
  await browser.close();
  if (process.argv[3]) fs.writeFileSync(process.argv[3], JSON.stringify(results, null, 1));
  console.log(`rendered ${n} cards`);
})().catch(e => { console.error(e); process.exit(1); });
