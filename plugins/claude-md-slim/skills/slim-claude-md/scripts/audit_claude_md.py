#!/usr/bin/env python3
"""Measure a CLAUDE.md against the documented size budget and report what to move out.

Claude Code loads CLAUDE.md in full on every session, and the official guidance is to target under
200 lines because longer files reduce instruction adherence. This reports the numbers that decide
whether a file needs splitting, and ranks its sections so the split targets the biggest wins first.

Counts the LOADED size, not the raw file: block-level HTML comments are stripped before the content
reaches the model, so they are free and are excluded here.

Usage:
    python audit_claude_md.py [path/to/CLAUDE.md] [--budget 200] [--json]

Exit codes: 0 within budget, 1 over budget, 2 usage/IO error.
"""
import argparse
import json
import os
import re
import sys

HTML_COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
FENCE = re.compile(r"^\s*```")

# Phrases that tend to mark content which silently rots. These are heuristics: every hit needs a
# human to confirm, but stale prose in a file nobody prunes is the failure mode that makes an
# oversized CLAUDE.md actively harmful rather than merely expensive.
STALE_HINTS = [
    (r"\bnot yet\b", "says something has not happened yet"),
    (r"\bpending\b", "describes a pending state"),
    (r"\bplaceholder\b", "mentions a placeholder"),
    (r"\bcoming soon\b", "promises future work"),
    (r"\bwill be\b", "describes an intended future state"),
    (r"\bcurrently\b", "pins a claim to an unstated 'now'"),
    (r"\bfor now\b", "describes a temporary state"),
    (r"\bTODO\b", "unresolved TODO"),
    (r"\bdeprecated\b", "claims something is deprecated"),
    (r"\bblocked on\b", "describes a blocker that may be resolved"),
]


def loaded_text(raw):
    """The text Claude actually receives: block-level HTML comments are stripped first."""
    return HTML_COMMENT.sub("", raw)


def split_sections(text):
    """[(heading, line_count)] for '## ' sections, plus a synthetic preamble."""
    out, name, count = [], "(preamble)", 0
    for line in text.split("\n"):
        if line.startswith("## "):
            out.append((name, count))
            name, count = line[3:].strip(), 1
        else:
            count += 1
    out.append((name, count))
    return [s for s in out if s[1] > 0]


def find_derivable(text):
    """Content the docs say to cut because Claude can read it from the codebase instead."""
    hits, in_fence = [], False
    for i, line in enumerate(text.split("\n"), 1):
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence and re.search(r"[├└│]|^\s*\w[\w.-]*/\s*$", line):
            hits.append((i, "directory tree in a code block"))
    return hits


def find_stale(text):
    hits, in_fence = [], False
    for i, line in enumerate(text.split("\n"), 1):
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        for pattern, why in STALE_HINTS:
            if re.search(pattern, line, re.IGNORECASE):
                hits.append((i, why, line.strip()[:100]))
                break
    return hits


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("path", nargs="?", default="CLAUDE.md")
    ap.add_argument("--budget", type=int, default=200,
                    help="line budget (default 200, the documented target)")
    ap.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    args = ap.parse_args()

    if not os.path.isfile(args.path):
        print("error: no such file: %s" % args.path, file=sys.stderr)
        return 2
    raw = open(args.path, encoding="utf-8").read()

    text = loaded_text(raw)
    raw_lines = raw.count("\n") + 1
    lines = text.count("\n") + 1
    approx_tokens = len(text) // 4
    sections = sorted(split_sections(text), key=lambda s: -s[1])
    over = lines > args.budget

    if args.json:
        json.dump({
            "path": args.path, "raw_lines": raw_lines, "loaded_lines": lines,
            "approx_tokens": approx_tokens, "budget": args.budget, "over_budget": over,
            "sections": [{"heading": h, "lines": n} for h, n in sections],
            "stale_hints": [{"line": i, "why": w, "text": t} for i, w, t in find_stale(text)],
            "derivable": [{"line": i, "why": w} for i, w in find_derivable(text)],
        }, sys.stdout, indent=2, ensure_ascii=False)
        print()
        return 1 if over else 0

    print("%s: %d loaded lines (~%d tokens), budget %d" % (args.path, lines, approx_tokens, args.budget))
    if raw_lines != lines:
        print("  (%d raw lines; HTML comments are stripped before loading and cost nothing)" % raw_lines)
    print("  VERDICT: %s" % ("OVER BUDGET -- split it" if over else "within budget"))

    if over:
        excess = lines - args.budget
        print("\nBiggest sections (move whole sections, largest first; need to shed ~%d lines):" % excess)
        running = 0
        for heading, n in sections:
            marker = " "
            if running < excess:
                marker, running = "*", running + n
            print("  %s %5d  %s" % (marker, n, heading))
        print("  ('*' = moving these alone would get you under budget)")

    derivable = find_derivable(text)
    if derivable:
        print("\nDerivable from the codebase (the docs say cut these; /doctor removes them too):")
        for i, why in derivable[:10]:
            print("  line %-5d %s" % (i, why))

    stale = find_stale(text)
    if stale:
        print("\nPossible staleness (%d hits) -- confirm each against reality, do not trust the prose:" % len(stale))
        for i, why, snippet in stale[:15]:
            print("  line %-5d %-42s %s" % (i, why, snippet))
        if len(stale) > 15:
            print("  ... and %d more" % (len(stale) - 15))

    return 1 if over else 0


if __name__ == "__main__":
    sys.exit(main())
