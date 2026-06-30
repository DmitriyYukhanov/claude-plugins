# Third-party assets

Vendored, committed, offline-first. End users never fetch these — they are inlined
into the generated `index.html` at render time.

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
- Bundle: assets/mermaid.min.js
- Inlined into `index.html` only when `body_md` contains a diagram.
- **Do not bump to mermaid 11.x without rewriting the init snippet:** 11.x ships an IIFE
  bundle that exposes the API under `mermaid.default`, so the `typeof mermaid !== 'undefined'
  && mermaid.initialize` guard used by the renderer silently no-ops and no diagram renders.
  10.9.1 is the last line whose dist bundle exposes a UMD `mermaid` global usable from a
  `file://` classic script.
