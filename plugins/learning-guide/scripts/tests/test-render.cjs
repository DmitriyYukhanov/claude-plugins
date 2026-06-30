const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');

const RENDER = path.join(__dirname, '..', 'render.cjs');

function tmpdir(label) {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'lg-' + label + '-'));
}

function runRender(args) {
  const r = cp.spawnSync('node', [RENDER].concat(args), { encoding: 'utf8' });
  return { code: r.status, stdout: r.stdout || '', stderr: r.stderr || '' };
}

function minimalSpec(extra) {
  return Object.assign({
    schema_version: '1.0',
    title: 'Test Tour',
    lang: 'en',
    archetype: 'generic',
    sections: [
      { id: 'intro', level: 1, title: 'Intro', body_md: 'Welcome.' },
      { id: 'next',  level: 1, title: 'Next',  body_md: 'See [Service](src/x.cs:42).' }
    ],
    renderer: { include_progress_tracker: true, include_pager: true, open_command: 'open.cmd' }
  }, extra || {});
}

function writeSpec(dir, spec) {
  const p = path.join(dir, 'tour-spec.json');
  fs.writeFileSync(p, JSON.stringify(spec));
  return p;
}

module.exports = [
  { name: 'fails when spec path missing', fn: () => {
    const r = runRender([]);
    assert.notStrictEqual(r.code, 0);
    assert.match(r.stderr, /usage|spec/i);
  }},
  { name: 'fails on missing file', fn: () => {
    const dir = tmpdir('miss');
    const r = runRender([path.join(dir, 'nope.json')]);
    assert.notStrictEqual(r.code, 0);
    assert.match(r.stderr, /not found|does not exist/i);
  }},
  { name: 'fails on invalid JSON', fn: () => {
    const dir = tmpdir('badjson');
    const p = path.join(dir, 'tour-spec.json');
    fs.writeFileSync(p, '{invalid}');
    const r = runRender([p]);
    assert.notStrictEqual(r.code, 0);
    assert.match(r.stderr, /JSON/);
  }},
  { name: 'fails on schema violation with path', fn: () => {
    const dir = tmpdir('badschema');
    const p = path.join(dir, 'tour-spec.json');
    fs.writeFileSync(p, JSON.stringify({ schema_version: '1.0' }));
    const r = runRender([p]);
    assert.notStrictEqual(r.code, 0);
    assert.match(r.stderr, /title|archetype|sections|lang/);
  }},
  { name: 'minimal valid spec writes index.html', fn: () => {
    const dir = tmpdir('ok');
    const p = writeSpec(dir, minimalSpec());
    const r = runRender([p]);
    if (r.code !== 0) throw new Error(r.stderr);
    const html = fs.readFileSync(path.join(dir, 'index.html'), 'utf8');
    assert.match(html, /<title>Test Tour<\/title>/);
    assert.match(html, /<section[^>]*id="intro"/);
    assert.match(html, /<section[^>]*id="next"/);
    assert.match(html, /class="filepath"/);
  }},
  // R13: pager controls are <button> (keyboard-operable), not anchors.
  { name: 'pager controls are buttons (R13)', fn: () => {
    const dir = tmpdir('pager');
    const p = writeSpec(dir, minimalSpec());
    const r = runRender([p]);
    if (r.code !== 0) throw new Error(r.stderr);
    const html = fs.readFileSync(path.join(dir, 'index.html'), 'utf8');
    assert.match(html, /<button[^>]+class="next"[^>]+data-target=/);
    assert.doesNotMatch(html, /<a[^>]+class="next"/);
  }},
  { name: 'mermaid auto-detect on by content', fn: () => {
    const dir = tmpdir('mer');
    const spec = minimalSpec();
    spec.sections.push({ id: 'diag', level: 1, title: 'Diagram', body_md: '```mermaid\nflowchart LR\nA-->B\n```' });
    const p = writeSpec(dir, spec);
    const r = runRender([p]);
    if (r.code !== 0) throw new Error(r.stderr);
    const html = fs.readFileSync(path.join(dir, 'index.html'), 'utf8');
    assert.match(html, /class="mermaid"/);
    assert.match(html, /mermaid\.initialize/);
  }},
  { name: 'mermaid skipped when no diagrams', fn: () => {
    const dir = tmpdir('nomer');
    const p = writeSpec(dir, minimalSpec());
    const r = runRender([p]);
    if (r.code !== 0) throw new Error(r.stderr);
    const html = fs.readFileSync(path.join(dir, 'index.html'), 'utf8');
    assert.doesNotMatch(html, /mermaid\.initialize/);
  }},
  // R6: a mermaid fence shown INSIDE a code example must not trigger mermaid inlining.
  { name: 'mermaid not inlined for fenced code example (R6)', fn: () => {
    const dir = tmpdir('merex');
    const spec = minimalSpec();
    spec.sections.push({ id: 'ex', level: 1, title: 'Example',
      body_md: '````\n```mermaid\nflowchart LR\nA-->B\n```\n````' });
    const p = writeSpec(dir, spec);
    const r = runRender([p]);
    if (r.code !== 0) throw new Error(r.stderr);
    const html = fs.readFileSync(path.join(dir, 'index.html'), 'utf8');
    assert.doesNotMatch(html, /<div class="mermaid">/);
    assert.doesNotMatch(html, /mermaid\.initialize/);
  }},
  // R7: the vendored mermaid bundle is excluded from the payload-size warning.
  { name: 'mermaid bundle excluded from payload warning (R7)', fn: () => {
    const dir = tmpdir('merpay');
    const spec = minimalSpec({ renderer: { max_inline_payload_kb: 2048, include_progress_tracker: true, include_pager: true, open_command: 'open.cmd' } });
    spec.sections.push({ id: 'diag', level: 1, title: 'Diagram', body_md: '```mermaid\nflowchart LR\nA-->B\n```' });
    const p = writeSpec(dir, spec);
    const r = runRender([p]);
    if (r.code !== 0) throw new Error(r.stderr);
    assert.doesNotMatch(r.stderr, /payload|max_inline_payload_kb/i);
  }},
  // R4: final_quiz is a reachable, navigable section (TOC link + tour meta).
  { name: 'final_quiz is navigable (R4)', fn: () => {
    const dir = tmpdir('fq');
    const spec = minimalSpec({ final_quiz: [{ question: 'Q?', options: ['a', 'b'], answer_index: 0 }] });
    const p = writeSpec(dir, spec);
    const r = runRender([p]);
    if (r.code !== 0) throw new Error(r.stderr);
    const html = fs.readFileSync(path.join(dir, 'index.html'), 'utf8');
    assert.match(html, /data-id="final-quiz"/);
    assert.match(html, /<section[^>]*id="final-quiz"/);
    const meta = html.match(/id="lg-tour-meta"[^>]*>([^<]*)</)[1];
    assert.ok(JSON.parse(meta).sections.indexOf('final-quiz') !== -1, meta);
  }},
  // R5: glossary is rendered and navigable.
  { name: 'glossary renders and is navigable (R5)', fn: () => {
    const dir = tmpdir('glo');
    const spec = minimalSpec({ glossary: [{ term: 'Idempotency', definition: 'No duplicate effect.' }] });
    const p = writeSpec(dir, spec);
    const r = runRender([p]);
    if (r.code !== 0) throw new Error(r.stderr);
    const html = fs.readFileSync(path.join(dir, 'index.html'), 'utf8');
    assert.match(html, /<section[^>]*id="glossary"/);
    assert.match(html, /data-id="glossary"/);
    assert.match(html, /Idempotency/);
  }},
  // R12: the side panel is an accessible dialog.
  { name: 'side panel is role=dialog (R12)', fn: () => {
    const dir = tmpdir('dlg');
    fs.writeFileSync(path.join(dir, 'design.md'), '# Hi\n\nbody\n');
    const spec = minimalSpec({ embedded_sources: [{ name: 'design', path: 'design.md', label: 'Design' }] });
    const p = writeSpec(dir, spec);
    const r = runRender([p]);
    if (r.code !== 0) throw new Error(r.stderr);
    const html = fs.readFileSync(path.join(dir, 'index.html'), 'utf8');
    assert.match(html, /id="md-viewer"[^>]*role="dialog"/);
  }},
  { name: 'embedded source inlined and </script> escaped', fn: () => {
    const dir = tmpdir('emb');
    fs.writeFileSync(path.join(dir, 'design.md'), '# Hi\n\nA tag: </script> here.\n');
    const spec = minimalSpec({ embedded_sources: [{ name: 'design', path: 'design.md', label: 'Design' }] });
    const p = writeSpec(dir, spec);
    const r = runRender([p]);
    if (r.code !== 0) throw new Error(r.stderr);
    const html = fs.readFileSync(path.join(dir, 'index.html'), 'utf8');
    assert.match(html, /script type="text\/markdown" data-name="design"/);
    assert.doesNotMatch(html, /A tag: <\/script> here/);
    assert.match(html, /A tag: <\\\/script> here/);
  }},
  { name: 'open.cmd and render.cmd generated', fn: () => {
    const dir = tmpdir('cmd');
    const p = writeSpec(dir, minimalSpec());
    const r = runRender([p]);
    if (r.code !== 0) throw new Error(r.stderr);
    const oc = fs.readFileSync(path.join(dir, 'open.cmd'), 'utf8');
    assert.match(oc, /start "" "%~dp0index\.html"/);
    const rc = fs.readFileSync(path.join(dir, 'render.cmd'), 'utf8');
    assert.match(rc, /node /);
    assert.match(rc, /render\.cjs/);
  }},
  // R17: open_command "none" skips the launcher and the stdout hint.
  { name: 'open_command none skips open.cmd (R17)', fn: () => {
    const dir = tmpdir('noopen');
    const p = writeSpec(dir, minimalSpec({ renderer: { open_command: 'none', include_progress_tracker: true, include_pager: true } }));
    const r = runRender([p]);
    if (r.code !== 0) throw new Error(r.stderr);
    assert.ok(!fs.existsSync(path.join(dir, 'open.cmd')), 'open.cmd should not exist');
    assert.doesNotMatch(r.stdout, /double-click open\.cmd/);
  }},
  { name: 'rejects absolute embedded path', fn: () => {
    const dir = tmpdir('abs');
    const abs = path.resolve(dir, 'design.md');
    fs.writeFileSync(abs, 'x');
    const p = writeSpec(dir, minimalSpec({ embedded_sources: [{ name: 'design', path: abs, label: 'Design' }] }));
    const r = runRender([p]);
    assert.notStrictEqual(r.code, 0);
    assert.match(r.stderr, /absolute|outside/i);
  }},
  { name: 'rejects path traversal outside spec dir', fn: () => {
    const parent = tmpdir('trav');
    const dir = path.join(parent, 'tour'); fs.mkdirSync(dir);
    fs.writeFileSync(path.join(parent, 'design.md'), 'x');
    const p = writeSpec(dir, minimalSpec({ embedded_sources: [{ name: 'design', path: '../design.md', label: 'Design' }] }));
    const r = runRender([p]);
    assert.notStrictEqual(r.code, 0);
    assert.match(r.stderr, /outside/i);
  }},
  // R15: a symlink whose target escapes the root is refused (skips where symlinks aren't permitted).
  { name: 'rejects symlinked source escaping root (R15)', fn: () => {
    const parent = tmpdir('sym');
    const dir = path.join(parent, 'tour'); fs.mkdirSync(dir);
    const secret = path.join(parent, 'secret.md');
    fs.writeFileSync(secret, 'TOP SECRET');
    const link = path.join(dir, 'notes.md');
    try { fs.symlinkSync(secret, link); }
    catch (e) { return; } // symlinks not permitted on this host — skip
    const p = writeSpec(dir, minimalSpec({ embedded_sources: [{ name: 'notes', path: 'notes.md', label: 'Notes' }] }));
    const r = runRender([p]);
    assert.notStrictEqual(r.code, 0);
    assert.match(r.stderr, /symlink|outside/i);
  }},
  { name: 'policy.json widens project_root', fn: () => {
    const parent = tmpdir('policy');
    const dir = path.join(parent, 'tour'); fs.mkdirSync(dir);
    const policyDir = path.join(dir, '.learning-guide'); fs.mkdirSync(policyDir);
    fs.writeFileSync(path.join(policyDir, 'policy.json'), JSON.stringify({ project_root: '..' }));
    fs.writeFileSync(path.join(parent, 'design.md'), '# x\n');
    const p = writeSpec(dir, minimalSpec({ embedded_sources: [{ name: 'design', path: '../design.md', label: 'Design' }] }));
    const r = runRender([p]);
    if (r.code !== 0) throw new Error(r.stderr);
  }},
  { name: 'README.md generated on first run, preserved on second', fn: () => {
    const dir = tmpdir('rdm');
    const p = writeSpec(dir, minimalSpec());
    let r = runRender([p]);
    if (r.code !== 0) throw new Error(r.stderr);
    const rdm = path.join(dir, 'README.md');
    fs.writeFileSync(rdm, 'USER EDIT');
    r = runRender([p]);
    if (r.code !== 0) throw new Error(r.stderr);
    assert.strictEqual(fs.readFileSync(rdm, 'utf8'), 'USER EDIT');
  }},
  { name: 'soft warning on payload over max_inline_payload_kb', fn: () => {
    const dir = tmpdir('big');
    const big = '# x\n\n' + 'a'.repeat(200000);
    fs.writeFileSync(path.join(dir, 'design.md'), big);
    const spec = minimalSpec({
      embedded_sources: [{ name: 'design', path: 'design.md', label: 'Design' }],
      renderer: { max_inline_payload_kb: 1, include_progress_tracker: true, include_pager: true, open_command: 'open.cmd' }
    });
    const p = writeSpec(dir, spec);
    const r = runRender([p]);
    if (r.code !== 0) throw new Error(r.stderr);
    assert.match(r.stderr, /payload|max_inline_payload_kb/i);
  }},
  // CF2: render.cmd output-dir must be quote-safe (no trailing-backslash escape).
  { name: 'render.cmd output-dir is quote-safe (CF2)', fn: () => {
    const dir = tmpdir('rcmd');
    const p = writeSpec(dir, minimalSpec());
    const r = runRender([p]);
    if (r.code !== 0) throw new Error(r.stderr);
    const rc = fs.readFileSync(path.join(dir, 'render.cmd'), 'utf8');
    assert.match(rc, /--output-dir "%~dp0\."/);
  }},
  // CF4: answer_index beyond options length is rejected.
  { name: 'answer_index out of range is rejected (CF4)', fn: () => {
    const dir = tmpdir('ans');
    const spec = minimalSpec({ final_quiz: [{ question: 'Q', options: ['a', 'b'], answer_index: 5 }] });
    const p = writeSpec(dir, spec);
    const r = runRender([p]);
    assert.notStrictEqual(r.code, 0);
    assert.match(r.stderr, /answer_index/);
  }},
  // CF6: an author section id colliding with a reserved injected id is rejected.
  { name: 'section id colliding with glossary is rejected (CF6)', fn: () => {
    const dir = tmpdir('resv');
    const spec = minimalSpec({ glossary: [{ term: 'T', definition: 'D' }] });
    spec.sections.push({ id: 'glossary', level: 1, title: 'My Glossary', body_md: 'x' });
    const p = writeSpec(dir, spec);
    const r = runRender([p]);
    assert.notStrictEqual(r.code, 0);
    assert.match(r.stderr, /reserved/);
  }},
  // CF10: mark-read follows the progress tracker, not the pager.
  { name: 'mark-read present when pager off but progress on (CF10)', fn: () => {
    const dir = tmpdir('nopager');
    const spec = minimalSpec({ renderer: { include_pager: false, include_progress_tracker: true } });
    const p = writeSpec(dir, spec);
    const r = runRender([p]);
    if (r.code !== 0) throw new Error(r.stderr);
    const html = fs.readFileSync(path.join(dir, 'index.html'), 'utf8');
    assert.match(html, /class="mark-read"/);
    assert.doesNotMatch(html, /class="next"/);
  }},
  // CF11: an embedded source path pointing at a directory dies cleanly (no EISDIR crash).
  { name: 'embedded source pointing at a directory is rejected (CF11)', fn: () => {
    const dir = tmpdir('isdir');
    fs.mkdirSync(path.join(dir, 'docs'));
    const spec = minimalSpec({ embedded_sources: [{ name: 'docs', path: 'docs', label: 'Docs' }] });
    const p = writeSpec(dir, spec);
    const r = runRender([p]);
    assert.notStrictEqual(r.code, 0);
    assert.match(r.stderr, /not a regular file/);
  }},
  // CF12: a non-object spec (literal null) dies cleanly instead of throwing a TypeError.
  { name: 'non-object spec dies cleanly (CF12)', fn: () => {
    const dir = tmpdir('nullspec');
    const p = path.join(dir, 'tour-spec.json');
    fs.writeFileSync(p, 'null');
    const r = runRender([p]);
    assert.notStrictEqual(r.code, 0);
    assert.match(r.stderr, /must be a JSON object/);
  }}
];
