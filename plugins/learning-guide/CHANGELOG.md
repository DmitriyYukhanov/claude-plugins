# Changelog

All notable changes to the **learning-guide** plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.3] - 2026-06-30

### Added
- Browser-side assets: HTML template, styles, runtime JS (sidebar nav, progress tracking, on-demand side-panel source viewer, click-to-copy paths, quizzes), English and Russian i18n bundles, the static Windows launcher, and vendored Mermaid 10.9.1. The runtime resolves cross-reference anchors with a shared Unicode-aware slug, escapes and scheme-checks links inside embedded sources, keeps the side panel reachable by assistive tech, and announces quiz results.

## [1.0.2] - 2026-06-30

### Added
- Markdown processor (vendored markdown-it) with five custom transforms: callout fences, mermaid fences, click-to-copy file paths, cross-reference tokens, and external-link tokens. Hardened for Windows backslash paths, non-Latin (e.g. Cyrillic) heading slugs, an external-link scheme allowlist, and catastrophic-regex (ReDoS) cross-ref patterns.

## [1.0.1] - 2026-06-30

### Added
- Tour-spec JSON Schema (with an external-link scheme allowlist) and a zero-dependency validator that reports line-pointed errors.

## [1.0.0] - 2026-04-30

### Added
- Initial scaffold for the `learning-guide` plugin.
