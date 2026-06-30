'use strict';
const path = require('path');
const MarkdownIt = require(path.join(__dirname, '..', 'assets', 'markdown-it.min.js'));

function normalizeLineEndings(s) {
  return s.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
}

// R9 — Unicode-aware slug: keep letters/numbers from any script (Cyrillic etc.) so
// non-Latin headings don't collapse to empty. Shared byte-for-byte with runtime.js.
function slugify(s) {
  return String(s).toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, '-')
    .replace(/^-+|-+$/g, '');
}

function escapeForScriptTag(s) {
  return s.replace(/<\/script/gi, m => '<\\/' + m.slice(2));
}

function applyAnchorFormat(format, captures) {
  if (format == null) return null;
  return format.replace(/\{(\d+)\}/g, (_, n) => slugify(captures[Number(n)] || ''));
}

// Custom rule: callout fence (:::callout {type=warn}) ... :::
// R14 — the closing-`:::` scan tracks open fenced-code regions so a `:::` line INSIDE
// a fenced block does not close the callout early.
function calloutPlugin(md) {
  md.block.ruler.before('fence', 'callout', function callout(state, startLine, endLine, silent) {
    const start = state.bMarks[startLine] + state.tShift[startLine];
    const max = state.eMarks[startLine];
    const line = state.src.slice(start, max);
    const m = line.match(/^:::callout\s*\{type=(info|warn|danger|success|tip)\}\s*$/);
    if (!m) return false;
    if (silent) return true;

    const type = m[1];
    let nextLine = startLine + 1;
    let found = false;
    let fence = null;
    while (nextLine < endLine) {
      const s = state.bMarks[nextLine] + state.tShift[nextLine];
      const e = state.eMarks[nextLine];
      const text = state.src.slice(s, e);
      const fm = text.match(/^(`{3,}|~{3,})/);
      if (fence) {
        if (fm && fm[1][0] === fence.char && fm[1].length >= fence.len &&
            text.slice(fm[1].length).trim() === '') {
          fence = null;
        }
        nextLine++;
        continue;
      }
      if (fm) { fence = { char: fm[1][0], len: fm[1].length }; nextLine++; continue; }
      if (text.trim() === ':::') { found = true; break; }
      nextLine++;
    }
    if (!found) return false;

    const oldParent = state.parentType;
    const oldLine = state.lineMax;
    state.parentType = 'callout';
    state.lineMax = nextLine;

    const tokOpen = state.push('callout_open', 'div', 1);
    tokOpen.attrs = [['class', 'callout ' + type]];
    tokOpen.markup = ':::callout';
    tokOpen.block = true;
    tokOpen.map = [startLine, nextLine + 1];

    state.md.block.tokenize(state, startLine + 1, nextLine);

    const tokClose = state.push('callout_close', 'div', -1);
    tokClose.markup = ':::';
    tokClose.block = true;

    state.parentType = oldParent;
    state.lineMax = oldLine;
    state.line = nextLine + 1;
    return true;
  }, { alt: ['paragraph', 'reference', 'blockquote', 'list'] });
}

// Custom rule: mermaid fence renders to <div class="mermaid">
function mermaidPlugin(md) {
  const defaultFence = md.renderer.rules.fence;
  md.renderer.rules.fence = function (tokens, idx, options, env, self) {
    const t = tokens[idx];
    const info = (t.info || '').trim();
    if (info === 'mermaid') {
      const content = md.utils.escapeHtml(t.content);
      return `<div class="mermaid">${content}</div>\n`;
    }
    return defaultFence(tokens, idx, options, env, self);
  };
}

// Custom rule: link [label](path:LINE) -> click-to-copy filepath span.
// R2 — markdown-it percent-encodes `\` to %5C in hrefs, so decode before matching;
// then normalize backslashes to forward slashes for the copied value.
function filepathPlugin(md) {
  const defaultLinkOpen = md.renderer.rules.link_open ||
    function (t, i, o, e, s) { return s.renderToken(t, i, o); };
  md.renderer.rules.link_open = function (tokens, idx, options, env, self) {
    const t = tokens[idx];
    let href = t.attrGet('href') || '';
    try { href = decodeURIComponent(href); } catch (e) { /* keep raw on malformed escapes */ }
    const m = href.match(/^([\w./\\-]+):(\d+)$/);
    if (m) {
      const normalized = m[1].replace(/\\/g, '/') + ':' + m[2];
      t.meta = t.meta || {};
      t.meta.filepath = normalized;
      const closeIdx = findCloseLink(tokens, idx);
      if (closeIdx !== -1) tokens[closeIdx].meta = { filepath: normalized };
      const esc = md.utils.escapeHtml(normalized);
      return `<button type="button" class="filepath" data-path="${esc}" aria-label="Copy ${esc}">`;
    }
    return defaultLinkOpen(tokens, idx, options, env, self);
  };
  const defaultLinkClose = md.renderer.rules.link_close ||
    function (t, i, o, e, s) { return s.renderToken(t, i, o); };
  md.renderer.rules.link_close = function (tokens, idx, options, env, self) {
    if (tokens[idx].meta && tokens[idx].meta.filepath) return '</button>';
    return defaultLinkClose(tokens, idx, options, env, self);
  };
}

function findCloseLink(tokens, openIdx) {
  let depth = 1;
  for (let i = openIdx + 1; i < tokens.length; i++) {
    if (tokens[i].type === 'link_open') depth++;
    else if (tokens[i].type === 'link_close') {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

// R3 — external-link scheme allowlist (the custom rule bypasses markdown-it validateLink).
const ALLOWED_SCHEME = /^(https?:|mailto:)/i;
// R10 — cross-ref patterns are author-supplied (and learning guides get shared). Compile
// each ONCE with the sticky flag (kills the O(n^2) per-position recompile + forward-scan),
// cap the source length, and empirically reject catastrophic-backtracking patterns with a
// short time-budgeted probe: a safe pattern mismatches the probe strings instantly, while a
// ReDoS pattern blows up on a run of a's/digits with a failing tail. Shape-agnostic, so it
// doesn't false-reject legitimate nested quantifiers like `§(\d+(?:\.\d+)*)`.
const MAX_XREF_PATTERN_LEN = 300;
const PROBE_STRINGS = [
  'a'.repeat(24) + '!',
  '1'.repeat(24) + '!',
  '1.1.1.1.1.1.1.1.1.1.1.1.1.1.1!'
];
const PROBE_BUDGET_MS = 50;

function patternIsSafe(re) {
  for (const s of PROBE_STRINGS) {
    re.lastIndex = 0;
    const t0 = Date.now();
    try { re.exec(s); } catch (e) { return false; }
    if (Date.now() - t0 > PROBE_BUDGET_MS) return false;
  }
  return true;
}

function safeCompileXref(p) {
  const src = p && p.pattern;
  if (typeof src !== 'string' || src.length === 0 || src.length > MAX_XREF_PATTERN_LEN) return null;
  let re;
  try { re = new RegExp(src, 'y'); } catch (e) { return null; }
  if (!patternIsSafe(re)) return null;
  return { re, source: p.source, anchor_format: p.anchor_format || null };
}

// Inline-text-only token rewriter for cross-refs and external links.
function inlineRewritePlugin(md, spec) {
  const xrefs = (spec.cross_ref_patterns || []).map(safeCompileXref).filter(Boolean);
  const extTemplates = spec.external_links || {};
  const extPrefixes = Object.keys(extTemplates);

  md.core.ruler.after('inline', 'xref-and-ext', function (state) {
    for (const blockTok of state.tokens) {
      if (blockTok.type !== 'inline') continue;
      const newChildren = [];
      for (const child of blockTok.children || []) {
        if (child.type !== 'text') { newChildren.push(child); continue; }
        const parts = splitText(child.content, xrefs, extPrefixes, extTemplates);
        for (const p of parts) {
          if (p.kind === 'text') {
            const tk = new state.Token('text', '', 0);
            tk.content = p.text;
            newChildren.push(tk);
          } else if (p.kind === 'xref') {
            const tk = new state.Token('html_inline', '', 0);
            const anchor = applyAnchorFormat(p.anchor_format, p.captures);
            const anchorAttr = anchor ? ` data-anchor="${escapeAttr(anchor)}"` : '';
            tk.content = `<button type="button" class="xref" data-source="${escapeAttr(p.source)}"${anchorAttr}>${escapeHtml(p.text)}</button>`;
            newChildren.push(tk);
          } else if (p.kind === 'ext') {
            const tk = new state.Token('html_inline', '', 0);
            tk.content = `<a class="ext-link" href="${escapeAttr(p.url)}" target="_blank" rel="noopener">${escapeHtml(p.text)}</a>`;
            newChildren.push(tk);
          }
        }
      }
      blockTok.children = newChildren;
    }
  });
}

function splitText(text, xrefs, extPrefixes, extTemplates) {
  const out = [];
  let i = 0;
  let buf = '';
  while (i < text.length) {
    let matched = null;
    for (const x of xrefs) {
      x.re.lastIndex = i;            // sticky: matches only at i, no forward scan / no recompile
      const m = x.re.exec(text);
      if (m) {
        matched = { kind: 'xref', text: m[0], source: x.source, anchor_format: x.anchor_format, captures: m.slice() };
        i += m[0].length;
        break;
      }
    }
    if (!matched) {
      for (const prefix of extPrefixes) {
        if (text.startsWith(prefix, i)) {
          const rest = text.slice(i + prefix.length);
          const m2 = rest.match(/^[A-Za-z0-9_-]+/);
          if (m2) {
            const id = m2[0];
            const url = String(extTemplates[prefix]).replace('{id}', id);
            if (ALLOWED_SCHEME.test(url)) {   // R3: refuse non-allowlisted schemes
              matched = { kind: 'ext', text: prefix + id, url };
              i += prefix.length + id.length;
              break;
            }
          }
        }
      }
    }
    if (matched) {
      if (buf) { out.push({ kind: 'text', text: buf }); buf = ''; }
      out.push(matched);
      continue;
    }
    buf += text[i];
    i++;
  }
  if (buf) out.push({ kind: 'text', text: buf });
  return out;
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c => ({
    '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'
  }[c]));
}
function escapeAttr(s) { return escapeHtml(s); }

function build(spec) {
  const md = new MarkdownIt({ html: false, linkify: false, typographer: false });
  calloutPlugin(md);
  mermaidPlugin(md);
  filepathPlugin(md);
  inlineRewritePlugin(md, spec || {});
  return md;
}

function renderBody(src, spec) {
  const md = build(spec);
  return md.render(normalizeLineEndings(src));
}

module.exports = {
  renderBody, normalizeLineEndings, slugify, escapeForScriptTag, applyAnchorFormat, build
};
