const assert = require('assert');
const path = require('path');
const { renderBody, normalizeLineEndings, slugify, escapeForScriptTag } =
  require(path.join(__dirname, '..', 'markdown.cjs'));

const minimalSpec = {
  embedded_sources: [{ name: 'design', path: 'design.md', label: 'Design' }],
  external_links: { 'TICKET-': 'https://x.example/{id}' },
  cross_ref_patterns: [
    // R1: canonical anchor scheme — bare slug, no `section-` prefix.
    { pattern: '§(\\d+(?:\\.\\d+)*)', source: 'design', anchor_format: '{1}' }
  ]
};

module.exports = [
  { name: 'normalizeLineEndings collapses CRLF', fn: () => {
    assert.strictEqual(normalizeLineEndings('a\r\nb\rc'), 'a\nb\nc');
  }},
  { name: 'slugify lowercases and dashifies', fn: () => {
    assert.strictEqual(slugify('Hello, World!  Foo--Bar'), 'hello-world-foo-bar');
  }},
  { name: 'slugify trims leading/trailing dashes', fn: () => {
    assert.strictEqual(slugify('--abc--'), 'abc');
  }},
  { name: 'escapeForScriptTag neutralises </script', fn: () => {
    assert.strictEqual(
      escapeForScriptTag('a</script>b</SCRIPT>c'),
      'a<\\/script>b<\\/SCRIPT>c'
    );
  }},
  { name: 'renders a heading and paragraph', fn: () => {
    const html = renderBody('# Title\n\nHello.', minimalSpec);
    assert.match(html, /<h1>Title<\/h1>/);
    assert.match(html, /<p>Hello\.<\/p>/);
  }},
  { name: 'callout fence produces callout block', fn: () => {
    const html = renderBody(':::callout {type=warn}\nBe careful.\n:::', minimalSpec);
    assert.match(html, /class="callout warn"/);
    assert.match(html, /Be careful\./);
  }},
  { name: 'callout containing fenced code is preserved', fn: () => {
    const src = ':::callout {type=info}\n```\ncode\n```\n:::';
    const html = renderBody(src, minimalSpec);
    assert.match(html, /class="callout info"/);
    assert.match(html, /<code>code\n<\/code>/);
  }},
  // R14: a `:::` line INSIDE a fenced block must not close the callout early.
  { name: 'callout closing scan skips fenced code (R14)', fn: () => {
    const src = ':::callout {type=info}\n```\nfoo\n:::\nbar\n```\n:::';
    const html = renderBody(src, minimalSpec);
    assert.match(html, /class="callout info"/);
    // bar stays inside the fenced code, not promoted to its own paragraph
    assert.doesNotMatch(html, /<p>bar<\/p>/);
    assert.match(html, /<code>foo\n:::\nbar\n<\/code>/);
  }},
  { name: 'mermaid fence produces mermaid div', fn: () => {
    const html = renderBody('```mermaid\nflowchart LR\nA-->B\n```', minimalSpec);
    assert.match(html, /<div class="mermaid">/);
    assert.match(html, /flowchart LR/);
  }},
  { name: 'filepath span replaces [label](path:LINE)', fn: () => {
    const html = renderBody('See [Service](src/Service.cs:42).', minimalSpec);
    assert.match(html, /<button[^>]+class="filepath"/);
    assert.match(html, /data-path="src\/Service\.cs:42"/);
  }},
  // R2: Windows backslash path (markdown-it percent-encodes `\` to %5C).
  { name: 'filepath span handles Windows backslash path (R2)', fn: () => {
    const html = renderBody('See [Service](src\\Payments\\Service.cs:42).', minimalSpec);
    assert.match(html, /<button[^>]+class="filepath"/);
    assert.match(html, /data-path="src\/Payments\/Service\.cs:42"/);
  }},
  { name: 'real URLs are not eaten by filepath rule', fn: () => {
    const html = renderBody('[link](https://host:8080/x)', minimalSpec);
    assert.match(html, /<a href="https:\/\/host:8080\/x"/);
    assert.doesNotMatch(html, /class="filepath"/);
  }},
  { name: 'cross-ref token gets data-source attr', fn: () => {
    const html = renderBody('See §3.1 for details.', minimalSpec);
    assert.match(html, /<button[^>]+class="xref"/);
    assert.match(html, /data-source="design"/);
    assert.match(html, /data-anchor="3-1"/);
  }},
  { name: 'cross-ref does NOT match inside code spans', fn: () => {
    const html = renderBody('Inline `§3.1` literal.', minimalSpec);
    assert.match(html, /<code>§3\.1<\/code>/);
    assert.doesNotMatch(html, /class="xref"/);
  }},
  // R10: adjacent cross-ref tokens both linkify (sticky-flag walk correctness).
  { name: 'adjacent cross-ref tokens both linkify (R10)', fn: () => {
    const html = renderBody('see §1 §2 here', minimalSpec);
    const count = (html.match(/class="xref"/g) || []).length;
    assert.strictEqual(count, 2, html);
  }},
  // R10: a genuinely catastrophic (ReDoS) pattern is guarded out, so the renderer
  // cannot hang on a crafted input. Without the guard this input would backtrack forever.
  { name: 'catastrophic cross-ref pattern is guarded, no hang (R10)', fn: () => {
    const spec = {
      embedded_sources: [{ name: 'd', path: 'd.md', label: 'D' }],
      cross_ref_patterns: [{ pattern: '(a+)+b', source: 'd' }]
    };
    const start = Date.now();
    const html = renderBody('a'.repeat(4000), spec);
    const ms = Date.now() - start;
    assert.doesNotMatch(html, /class="xref"/);
    assert.ok(ms < 4000, 'render took ' + ms + 'ms — catastrophic pattern not guarded');
  }},
  // R10: linear-time on large input (the buggy O(n^2) walk would take minutes).
  { name: 'large input renders quickly (R10 sticky walk)', fn: () => {
    const big = 'x '.repeat(100000) + ' §1 end';
    const start = Date.now();
    const html = renderBody(big, minimalSpec);
    const ms = Date.now() - start;
    assert.match(html, /class="xref"/);
    assert.ok(ms < 8000, 'render took ' + ms + 'ms (possible O(n^2) regression)');
  }},
  { name: 'external link token gets external link', fn: () => {
    const html = renderBody('Owner: TICKET-42.', minimalSpec);
    assert.match(html, /href="https:\/\/x\.example\/42"/);
    assert.match(html, /class="ext-link"/);
  }},
  { name: 'external link does NOT match inside code spans', fn: () => {
    const html = renderBody('Inline `TICKET-42` literal.', minimalSpec);
    assert.match(html, /<code>TICKET-42<\/code>/);
    assert.doesNotMatch(html, /class="ext-link"/);
  }},
  // R3: external-link rule enforces a scheme allowlist (no javascript: links).
  { name: 'external link with javascript: scheme renders as plain text (R3)', fn: () => {
    const spec = {
      embedded_sources: [],
      external_links: { 'EVIL-': 'javascript:document.title=1//{id}' }
    };
    const html = renderBody('Click EVIL-9 now.', spec);
    assert.doesNotMatch(html, /class="ext-link"/);
    assert.doesNotMatch(html, /javascript:/);
    assert.match(html, /EVIL-9/);
  }},
  // R9: Unicode (Cyrillic) headings produce distinct, non-empty slugs.
  { name: 'slugify preserves Unicode letters (R9)', fn: () => {
    const a = slugify('Раздел Один');
    const b = slugify('Раздел Два');
    assert.notStrictEqual(a, b);
    assert.ok(a.length > 0 && b.length > 0, JSON.stringify([a, b]));
  }}
];
