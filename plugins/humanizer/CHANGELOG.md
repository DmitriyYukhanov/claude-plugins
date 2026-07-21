# Changelog

All notable changes to the **humanizer** plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-07-21

### Changed
- English ruleset refreshed to upstream v2.8.2: 29 → 33 patterns (diff-anchored writing, manufactured punchlines, aphorism formulas, conversational rhetorical openers), an outright ban on em and en dashes, and a rule that a rewrite must cover everything the original covered
- English ruleset now says which tells are false positives and which signs of human writing to leave alone, so clean prose survives the pass instead of getting flattened
- Russian ruleset refreshed to upstream v3.14.2: 44 → 54 patterns, adding persuasion tropes, information rhythm, systematic hedging, and 2025-2026 style fingerprints such as decorative emoji and pseudo-therapeutic register

## [1.0.0] - 2026-04-30

### Added
- English ruleset vendored from blader/humanizer (29 Wikipedia AI-writing patterns)
- Russian ruleset vendored from ilyautov/humanizer-ru (44 patterns, hard bans, triple-pass audit)
- Auto language detection by Cyrillic ratio with explicit override and mixed-text handling
