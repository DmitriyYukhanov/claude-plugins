# Third-party assets

The two libraries reach the reader by different routes. markdown-it is vendored here and
runs at build time only. Mermaid is not vendored at all: the generated tour loads it from a
CDN in the reader's browser.

## markdown-it

- Version: 14.1.0
- License: MIT
- Source: https://github.com/markdown-it/markdown-it
- Bundle: assets/markdown-it.min.js
- Loaded as a CommonJS factory by `scripts/markdown.cjs` (build-time only; not shipped to the browser).

## mermaid

- Version: 10.9.1
- License: MIT
- Source: https://github.com/mermaid-js/mermaid
- **Not vendored, not inlined.** `scripts/render.cjs` writes a pinned `<script src>` tag
  (`https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js`) into `index.html`,
  only when the tour actually contains a diagram. This is what keeps a tour around 30 KB
  instead of 3.3 MB. The cost: **a tour needs network access to draw its diagrams.**
  Everything else in it — navigation, quizzes, progress, embedded sources — still works with
  no network.
- The tag carries a Subresource Integrity hash and `crossorigin="anonymous"`, so the browser
  runs the file only if its bytes match `MERMAID_SRI` in render.cjs. jsdelivr serves
  `Access-Control-Allow-Origin: *`, which is what makes that work from a `file://` page.
  Recompute the hash if the version changes:
  `openssl dgst -sha384 -binary mermaid.min.js | openssl base64 -A`
- **Do not bump MERMAID_VERSION in render.cjs to mermaid 11.x without rewriting the init
  snippet:** 11.x ships an IIFE bundle that exposes the API under `mermaid.default`, so the
  `typeof mermaid !== 'undefined' && mermaid.initialize` guard used by the renderer silently
  no-ops and no diagram renders. 10.9.1 is the last line whose dist bundle exposes a UMD
  `mermaid` global usable from a `file://` classic script.
