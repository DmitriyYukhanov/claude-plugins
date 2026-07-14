#!/usr/bin/env node
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');
const md = require('./markdown.cjs');

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const SAMPLES = path.join(PLUGIN_ROOT, 'assets', 'samples');
const EXPECTED = path.join(SAMPLES, 'expected');
const RENDER = path.join(__dirname, 'render.cjs');

function fail(msg) { process.stderr.write('FAIL: ' + msg + '\n'); process.exit(1); }
function ok(msg) { process.stdout.write('  ✓ ' + msg + '\n'); }

function args() {
  let tmpDir = null;
  for (let i = 2; i < process.argv.length; i++) {
    if (process.argv[i] === '--tmp-dir') tmpDir = process.argv[++i];
  }
  return { tmpDir: tmpDir || fs.mkdtempSync(path.join(os.tmpdir(), 'lg-verify-')) };
}

function run(spec, outDir) {
  const r = cp.spawnSync('node', [RENDER, spec, '--output-dir', outDir], { encoding: 'utf8' });
  if (r.status !== 0) fail(`render exited ${r.status}: ${r.stderr}`);
  return { stdout: r.stdout, stderr: r.stderr };
}

function assertFiles(outDir, files) {
  for (const f of files) {
    const p = path.join(outDir, f);
    if (!fs.existsSync(p)) fail(`expected file missing: ${p}`);
    if (fs.statSync(p).size === 0) fail(`expected file is empty: ${p}`);
  }
}

function verifyPlanningSession(tmp) {
  const dir = path.join(tmp, 'planning-session');
  fs.mkdirSync(dir, { recursive: true });
  fs.copyFileSync(path.join(EXPECTED, 'planning-session.tour-spec.json'), path.join(dir, 'tour-spec.json'));
  run(path.join(dir, 'tour-spec.json'), dir);
  assertFiles(dir, ['index.html', 'README.md']);
  const html = fs.readFileSync(path.join(dir, 'index.html'), 'utf8');
  if (!html.includes('Demo Planning Session')) fail('title not in HTML');
  if (!html.includes('TICKET-101')) fail('external link token not rendered');
  if (!html.includes('class="ext-link"')) fail('external link styling missing');
  ok('planning-session: render + linkify');
}

function verifyRefactorPlan(tmp) {
  const dir = path.join(tmp, 'refactor-plan');
  fs.mkdirSync(dir, { recursive: true });
  fs.copyFileSync(path.join(EXPECTED, 'refactor-plan.tour-spec.json'), path.join(dir, 'tour-spec.json'));
  run(path.join(dir, 'tour-spec.json'), dir);
  assertFiles(dir, ['index.html', 'README.md']);
  const html = fs.readFileSync(path.join(dir, 'index.html'), 'utf8');
  if (!html.includes('class="callout warn"')) fail('callout not rendered');
  ok('refactor-plan: render + callout');
}

function verifyCodebase(tmp) {
  const dir = path.join(tmp, 'codebase');
  fs.mkdirSync(dir, { recursive: true });
  fs.copyFileSync(path.join(EXPECTED, 'codebase.tour-spec.json'), path.join(dir, 'tour-spec.json'));
  fs.copyFileSync(path.join(EXPECTED, 'codebase.tour-companion.md'), path.join(dir, 'tour-companion.md'));
  run(path.join(dir, 'tour-spec.json'), dir);
  assertFiles(dir, ['index.html', 'README.md']);
  const html = fs.readFileSync(path.join(dir, 'index.html'), 'utf8');
  if (!html.includes('script type="text/markdown" data-name="companion"')) fail('companion not embedded');
  // R1: every cross-ref anchor must resolve to a heading id the side panel emits.
  const m = html.match(/class="xref"[^>]*data-anchor="([^"]+)"/);
  if (!m) fail('expected a cross-ref with a data-anchor in the codebase sample');
  const anchor = m[1];
  const companionSrc = fs.readFileSync(path.join(dir, 'tour-companion.md'), 'utf8');
  const headingSlugs = (companionSrc.match(/^#{1,6}\s+.*$/gm) || [])
    .map(h => md.slugify(h.replace(/^#{1,6}\s+/, '')));
  if (headingSlugs.indexOf(anchor) === -1)
    fail(`cross-ref anchor "${anchor}" resolves to no companion heading id (R1); have: ${headingSlugs.join(', ')}`);
  ok('codebase: render + companion embedded + anchor resolves');
}

function verifyScriptEscape(tmp) {
  const dir = path.join(tmp, 'esc');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'design.md'), '# x\n\nClosing tag in source: </script> stays neutralised.\n');
  fs.writeFileSync(path.join(dir, 'tour-spec.json'), JSON.stringify({
    schema_version: '1.0',
    title: 'Escape', lang: 'en', archetype: 'generic',
    embedded_sources: [{ name: 'design', path: 'design.md', label: 'Design' }],
    sections: [{ id: 'i', level: 1, title: 'I', body_md: 'x' }]
  }));
  run(path.join(dir, 'tour-spec.json'), dir);
  const html = fs.readFileSync(path.join(dir, 'index.html'), 'utf8');
  if (html.includes('Closing tag in source: </script>')) fail('embedded </script> NOT escaped');
  if (!html.includes('Closing tag in source: <\\/script>')) fail('escape replacement missing');
  ok('embedded </script> escape regression');
}

function verifyXssAllowlist(tmp) {
  const dir = path.join(tmp, 'xss');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'tour-spec.json'), JSON.stringify({
    schema_version: '1.0',
    title: 'XSS', lang: 'en', archetype: 'generic',
    external_links: { 'EVIL-': 'javascript:alert(1)/{id}' },
    sections: [{ id: 'i', level: 1, title: 'I', body_md: 'Click EVIL-9 here.' }]
  }));
  // schema enforces the scheme allowlist, so this spec should be REJECTED.
  const r = cp.spawnSync('node', [RENDER, path.join(dir, 'tour-spec.json'), '--output-dir', dir], { encoding: 'utf8' });
  if (r.status === 0) fail('a javascript: external_links template should be rejected by the schema');
  ok('external-link scheme allowlist (R3): javascript: template rejected');
}

function verifyScriptDataEscape(tmp) {
  const dir = path.join(tmp, 'sde');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'design.md'), 'Open comment then tag: <!-- and a <script> with no close.\n');
  fs.writeFileSync(path.join(dir, 'tour-spec.json'), JSON.stringify({
    schema_version: '1.0', title: 'SDE', lang: 'en', archetype: 'generic',
    embedded_sources: [{ name: 'design', path: 'design.md', label: 'D' }],
    sections: [{ id: 'i', level: 1, title: 'I', body_md: 'x' }]
  }));
  run(path.join(dir, 'tour-spec.json'), dir);
  const html = fs.readFileSync(path.join(dir, 'index.html'), 'utf8');
  if (!html.includes('<\\!--')) fail('embedded <!-- not neutralised (script-data escape)');
  if (!html.includes('<\\script')) fail('embedded <script not neutralised (script-data escape)');
  if (!html.includes('id="lg-i18n"')) fail('runtime/meta swallowed by embedded source');
  ok('script-data double-escape neutralised (CF5)');
}

function verifyCRLF(tmp) {
  const dirA = path.join(tmp, 'crlf-a'); fs.mkdirSync(dirA, { recursive: true });
  const dirB = path.join(tmp, 'crlf-b'); fs.mkdirSync(dirB, { recursive: true });
  const spec = {
    schema_version: '1.0',
    title: 'NL', lang: 'en', archetype: 'generic',
    sections: [{ id: 'i', level: 1, title: 'I', body_md: 'a\nb\nc' }]
  };
  fs.writeFileSync(path.join(dirA, 'tour-spec.json'), JSON.stringify(spec));
  spec.sections[0].body_md = 'a\r\nb\r\nc';
  fs.writeFileSync(path.join(dirB, 'tour-spec.json'), JSON.stringify(spec));
  run(path.join(dirA, 'tour-spec.json'), dirA);
  run(path.join(dirB, 'tour-spec.json'), dirB);
  const a = fs.readFileSync(path.join(dirA, 'index.html'), 'utf8');
  const b = fs.readFileSync(path.join(dirB, 'index.html'), 'utf8');
  if (a !== b) fail('CRLF and LF inputs produced different HTML');
  ok('CRLF normalization');
}

function main() {
  const { tmpDir } = args();
  process.stdout.write(`Verifying in ${tmpDir}\n`);
  verifyPlanningSession(tmpDir);
  verifyRefactorPlan(tmpDir);
  verifyCodebase(tmpDir);
  verifyScriptEscape(tmpDir);
  verifyScriptDataEscape(tmpDir);
  verifyXssAllowlist(tmpDir);
  verifyCRLF(tmpDir);
  process.stdout.write('\nAll verifications passed.\n');
}

main();
