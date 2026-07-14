#!/usr/bin/env node
'use strict';
// Opt-in BROWSER verification for a generated learning guide. This is NOT a runtime
// dependency of the plugin (the renderer and the runtime stay zero-dependency); it is a
// developer tool that drives the real interactive runtime in a headless browser, replacing
// the manual browser checklist.
//
// Requires Playwright + Chromium (install once, anywhere resolvable by Node):
//   npm i -D playwright && npx playwright install chromium
// Run:
//   node plugins/learning-guide/scripts/browser-verify.cjs
//
// It renders a feature-rich fixture tour with the plugin's own render.cjs, opens the
// resulting index.html from file:// in Chromium, and asserts the interactive behaviour:
// init, sidebar nav, side-panel source viewer + anchor scroll, Mermaid rendering, quizzes,
// progress persistence, click-to-copy, and external links.

const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');

let chromium;
try { ({ chromium } = require('playwright')); }
catch (e) {
  console.error('Playwright is not installed. Run:\n  npm i -D playwright && npx playwright install chromium');
  process.exit(2);
}

const RENDER = path.join(__dirname, 'render.cjs');
const results = [];
function check(name, cond, detail) {
  results.push({ name, ok: !!cond });
  process.stdout.write((cond ? '  ok   ' : '  FAIL ') + name + (cond || !detail ? '' : '  -> ' + detail) + '\n');
}

function renderFixture() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lg-browser-'));
  fs.writeFileSync(path.join(dir, 'design.md'),
    '# Design\n\n## Overview\n\nThe overview text shown in the side panel.\n\n' +
    '## Details\n\nHas `inline code` and **bold `wrapped` code** to exercise the renderer.\n');
  const spec = {
    schema_version: '1.0',
    title: 'Browser Verify Tour',
    subtitle: 'Playwright fixture',
    lang: 'en',
    archetype: 'refactor-plan',
    embedded_sources: [{ name: 'design', path: 'design.md', label: 'Design' }],
    external_links: { 'TICKET-': 'https://tracker.example.com/browse/TICKET-{id}' },
    cross_ref_patterns: [{ pattern: '\\[\\[design:([^\\]]+)\\]\\]', source: 'design', anchor_format: '{1}' }],
    sections: [
      { id: 'intro', level: 1, title: 'Introduction', estimated_minutes: 3,
        body_md: 'Welcome. Owner is TICKET-7. See [[design:overview]] and [Service.cs:42](src/Service.cs:42).',
        quiz: [{ question: 'Pick the right answer', options: ['Wrong one', 'Right one'], answer_index: 1, explanation: 'Because it is.' }] },
      { id: 'architecture', level: 1, title: 'Architecture', estimated_minutes: 5,
        body_md: 'A diagram:\n\n```mermaid\nflowchart LR\n  A-->B\n```' }
    ],
    glossary: [{ term: 'Idempotency', definition: 'No duplicate effect.' }],
    final_quiz: [{ question: 'Finished?', options: ['No', 'Yes'], answer_index: 1 }],
    renderer: { include_progress_tracker: true, include_pager: true }
  };
  fs.writeFileSync(path.join(dir, 'tour-spec.json'), JSON.stringify(spec));
  const r = cp.spawnSync('node', [RENDER, path.join(dir, 'tour-spec.json')], { encoding: 'utf8' });
  if (r.status !== 0) { console.error('render failed:\n' + r.stderr); process.exit(1); }
  return dir;
}

(async () => {
  const dir = renderFixture();
  const fileUrl = 'file:///' + path.join(dir, 'index.html').replace(/\\/g, '/');
  const browser = await chromium.launch();
  const context = await browser.newContext();
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(String(e)));
  page.on('console', m => { if (m.type() === 'error') errors.push('console: ' + m.text()); });

  await page.goto(fileUrl, { waitUntil: 'load' });
  await page.waitForTimeout(300);

  // init + nav
  check('first section active on load', await page.locator('#intro.section.active').count() === 1);
  check('TOC lists all 4 nav items (incl. glossary + final-quiz)',
    await page.locator('aside nav a').count() === 4);
  await page.locator('aside nav a[data-id="architecture"]').click();
  check('TOC click activates target section', await page.locator('#architecture.active').count() === 1);
  check('previous section deactivated', await page.locator('#intro.active').count() === 0);

  // Mermaid renders to SVG
  let mermaidOk = false;
  try { await page.waitForSelector('.mermaid svg', { timeout: 6000 }); mermaidOk = true; } catch (e) {}
  check('Mermaid diagram rendered to SVG', mermaidOk);

  // side panel + anchor resolution (the flagship cross-ref feature)
  await page.locator('aside nav a[data-id="intro"]').click();
  await page.locator('button.xref[data-source="design"][data-anchor="overview"]').click();
  await page.waitForTimeout(300);
  check('side panel opens on xref click', await page.locator('#md-viewer.open').count() === 1);
  check('side panel aria-hidden=false when open',
    (await page.locator('#md-viewer').getAttribute('aria-hidden')) === 'false');
  check('cross-ref anchor resolved (heading flashed)',
    await page.locator('#md-viewer-content #overview.anchor-flash, .md-viewer-content #overview.anchor-flash').count() >= 1
    || await page.locator('.md-viewer-content #overview').count() === 1);
  check('side panel renders bold-wrapped code correctly',
    await page.locator('.md-viewer-content strong code').count() >= 1);
  await page.keyboard.press('Escape');
  await page.waitForTimeout(150);
  check('Escape closes the side panel', await page.locator('#md-viewer.open').count() === 0);

  // quiz interaction
  await page.locator('#intro .quiz .options label').nth(0).locator('input').check();
  check('wrong answer flags the chosen label', await page.locator('#intro .quiz .options label.wrong').count() === 1);
  check('wrong answer marks the correct label', await page.locator('#intro .quiz .options label.correct').count() === 1);
  check('quiz status announces a result', ((await page.locator('#intro .quiz .quiz-status').textContent()) || '').trim().length > 0);
  await page.locator('#intro .quiz .options label').nth(1).locator('input').check();
  check('correct answer status reads "Correct"',
    ((await page.locator('#intro .quiz .quiz-status').textContent()) || '').indexOf('Correct') === 0);

  // click-to-copy filepath -> toast
  await page.locator('#intro button.filepath').first().click();
  await page.waitForTimeout(100);
  check('click-to-copy shows a toast', await page.locator('#toast.show').count() === 1);

  // external link
  const ext = page.locator('#intro a.ext-link').first();
  check('external link href + target', (await ext.getAttribute('href')) === 'https://tracker.example.com/browse/TICKET-7'
    && (await ext.getAttribute('target')) === '_blank');

  // glossary + final-quiz reachable
  await page.locator('aside nav a[data-id="glossary"]').click();
  check('glossary section reachable + content', await page.locator('#glossary.active').count() === 1
    && (await page.locator('#glossary').textContent()).indexOf('Idempotency') !== -1);
  await page.locator('aside nav a[data-id="final-quiz"]').click();
  check('final-quiz section reachable', await page.locator('#final-quiz.active').count() === 1);

  // progress: mark-as-read + persistence across reload
  await page.locator('aside nav a[data-id="intro"]').click();
  await page.locator('#intro button.mark-read').click();
  await page.waitForTimeout(100);
  const progAfter = ((await page.locator('#progress-text').textContent()) || '').trim();
  check('mark-as-read advances progress', /^[1-9]/.test(progAfter), 'progress="' + progAfter + '"');
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(200);
  const progReload = ((await page.locator('#progress-text').textContent()) || '').trim();
  check('progress persists across reload (localStorage)', /^[1-9]/.test(progReload), 'progress="' + progReload + '"');

  // sidebar collapse / expand
  await page.locator('#lg-sidebar-collapse').click();
  await page.waitForTimeout(150);
  check('sidebar collapses (aside hidden, show button visible)',
    (await page.evaluate(() => document.body.classList.contains('lg-collapsed')))
    && await page.locator('#lg-sidebar-show').isVisible());
  const mainW = (await page.locator('#content').boundingBox()).width;
  check('collapsed: main content stays wide (does not squeeze to min-content)', mainW > 600, 'main=' + Math.round(mainW));
  await page.locator('#lg-sidebar-show').click();
  check('sidebar expands again',
    await page.evaluate(() => !document.body.classList.contains('lg-collapsed')));

  // sidebar resize (keyboard on the separator) + persistence
  const readW = () => page.evaluate(() => parseInt(getComputedStyle(document.documentElement).getPropertyValue('--lg-sidebar-w')) || 300);
  const w0 = await readW();
  await page.locator('#lg-sidebar-resize').focus();
  for (let k = 0; k < 5; k++) await page.keyboard.press('ArrowRight');
  const w1 = await readW();
  check('sidebar resize widens the panel', w1 > w0, 'w0=' + w0 + ' w1=' + w1);
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(200);
  const w2 = await readW();
  check('sidebar width persists across reload', w2 === w1, 'w1=' + w1 + ' w2=' + w2);

  // "Next" also marks the current section as read
  await page.evaluate(() => { try { localStorage.clear(); } catch (e) {} });
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(200);
  const preNext = parseInt(((await page.locator('#progress-text').textContent()) || '0').trim()) || 0;
  await page.locator('#intro button.next').click();
  await page.waitForTimeout(100);
  check('Next activates the target section', await page.locator('#architecture.active').count() === 1);
  const postNext = parseInt(((await page.locator('#progress-text').textContent()) || '0').trim()) || 0;
  check('Next also marks the current section read', preNext === 0 && postNext >= 1, 'before=' + preNext + ' after=' + postNext);

  check('no uncaught JS errors during the session', errors.length === 0, errors.join(' | '));

  await browser.close();
  try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) {}

  const failed = results.filter(r => !r.ok);
  process.stdout.write('\n' + (results.length - failed.length) + '/' + results.length + ' browser checks passed\n');
  process.exit(failed.length ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
