# Browser compatibility

Generated tours run from `file://`. Tested on:

- Chrome (latest stable)
- Edge (latest stable)
- Firefox (latest ESR) — verified specifically for the clipboard fallback path

## Constraints

- **No `fetch()` against `file://`.** Embedded sources are read via DOM (`document.getElementById(...).textContent`).
- **No ES modules from `file://`.** The runtime is a classic script.
- **`navigator.clipboard.writeText` requires a secure context.** Chrome/Edge often satisfy `file://` as secure; Firefox does not. The runtime falls back to `document.execCommand('copy')` inside a try/catch.
- **`localStorage`** scoping varies by browser. Progress is local to one machine and is lost when the file is shared.

## What does NOT work

- Sending the generated `index.html` over email and expecting recipients to share progress state.
- Hosting the file behind a path that strips the `.html` extension (some servers do this and break Mermaid loading via `data:` URIs).
