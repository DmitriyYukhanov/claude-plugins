# Third-party assets

Both libraries end up fully inlined into the generated `index.html`, so the tour itself
stays offline-first regardless of how the library reached the renderer. markdown-it is
vendored and committed. mermaid is not — see below.

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
- **Not vendored.** `scripts/render.cjs` downloads it from a pinned CDN URL
  (`https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js`) the first time a spec
  needs it, and caches the file on disk (`$CLAUDE_CONFIG_DIR/cache/learning-guide/`, or the
  OS temp dir if that isn't writable) so every later render is offline again. Rendering a
  tour with a diagram for the very first time on a machine needs network access once; the
  generated `index.html` itself still has mermaid fully inlined and needs no network to view.
- Inlined into `index.html` only when `body_md` contains a diagram.
- **Do not bump MERMAID_VERSION in render.cjs to mermaid 11.x without rewriting the init
  snippet:** 11.x ships an IIFE bundle that exposes the API under `mermaid.default`, so the
  `typeof mermaid !== 'undefined' && mermaid.initialize` guard used by the renderer silently
  no-ops and no diagram renders. 10.9.1 is the last line whose dist bundle exposes a UMD
  `mermaid` global usable from a `file://` classic script.
