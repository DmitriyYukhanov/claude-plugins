#!/usr/bin/env python3
"""Prove that splitting a CLAUDE.md moved content instead of losing it.

Splitting is only safe if every substantive line still exists somewhere. Reading the diff will not
tell you: the diff of a large move is unreviewable, and a dropped paragraph looks exactly like an
intentional trim. This compares the ORIGINAL file's substantive lines against the union of the files
that replaced it and fails loudly on anything that vanished.

Trivial lines (blank, short, pure markdown scaffolding) are ignored, because they legitimately get
rewritten. Everything else must survive verbatim.

USE --section. This check is meaningful for content you MOVED verbatim, not for prose you rewrote:
comparing a whole rewritten file reports every reworded sentence as "lost" and buries the real
losses in noise. Name the sections you moved and check only those. Rewriting the remaining core is
a separate, reviewable edit -- keep the two operations apart so this check stays trustworthy.

Usage:
    # the normal case: verify the sections you moved landed in the rules files intact
    python verify_extraction.py --original-git HEAD:CLAUDE.md \
        --section "YouTube autoposting" --section "Stories autoposting" \
        --now .claude/rules/destinations.md

    # whole-file comparison (only when nothing was rewritten)
    python verify_extraction.py --original OLD.md --now CLAUDE.md --now .claude/rules/a.md

Exit codes: 0 nothing lost, 1 content lost, 2 usage/IO error.
"""
import argparse
import os
import re
import subprocess
import sys

MIN_LEN = 40  # below this a line is scaffolding (headings, bullets markers, table rules)
SCAFFOLD = re.compile(r"^[\s|`~#*_>+-]*$")


def substantive(text):
    """Lines that carry meaning and must survive a move."""
    out = []
    for line in text.split("\n"):
        s = line.strip()
        if len(s) >= MIN_LEN and not SCAFFOLD.match(s):
            out.append(s)
    return out


def select_sections(text, wanted):
    """The '## ' sections whose heading contains any of `wanted` (case-insensitive substring).

    Substring rather than exact match so callers can pass a short stable fragment instead of
    reproducing a long heading, which would itself be a transcription risk.
    """
    picked, keep, matched = [], False, set()
    for line in text.split("\n"):
        if line.startswith("## "):
            heading = line[3:].strip()
            hit = next((w for w in wanted if w.lower() in heading.lower()), None)
            keep = hit is not None
            if hit:
                matched.add(hit)
        if keep:
            picked.append(line)
    missing = [w for w in wanted if w not in matched]
    if missing:
        print("error: no section heading matched: %s" % ", ".join(repr(m) for m in missing), file=sys.stderr)
        print("       check the spelling against the original file's '## ' headings.", file=sys.stderr)
        raise SystemExit(2)
    return "\n".join(picked)


def read_git(ref):
    try:
        return subprocess.run(["git", "show", ref], check=True, capture_output=True).stdout.decode("utf-8")
    except subprocess.CalledProcessError as exc:
        print("error: git show %s failed: %s" % (ref, exc.stderr.decode("utf-8", "replace").strip()), file=sys.stderr)
        raise SystemExit(2)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--original", help="path to the pre-split file")
    src.add_argument("--original-git", help="git ref of the pre-split file, e.g. HEAD:CLAUDE.md")
    ap.add_argument("--now", action="append", required=True,
                    help="a file that now holds the content; repeat for each (CLAUDE.md + every rules file)")
    ap.add_argument("--section", action="append", default=[],
                    help="only check this '## ' section of the original (substring match); repeat. "
                         "Strongly recommended -- without it, rewritten prose reports as lost.")
    ap.add_argument("--show", type=int, default=10, help="how many missing lines to print (default 10)")
    args = ap.parse_args()

    if args.original:
        if not os.path.isfile(args.original):
            print("error: no such file: %s" % args.original, file=sys.stderr)
            return 2
        original = open(args.original, encoding="utf-8").read()
        label = args.original
    else:
        original = read_git(args.original_git)
        label = args.original_git

    haystack = []
    for path in args.now:
        if not os.path.isfile(path):
            print("error: no such file: %s" % path, file=sys.stderr)
            return 2
        haystack.append(open(path, encoding="utf-8").read())
    combined = "\n".join(haystack)

    if args.section:
        original = select_sections(original, args.section)
        label += " [sections: %s]" % ", ".join(args.section)
    else:
        print("warning: no --section given, comparing the WHOLE original. Any rewritten line will be",
              file=sys.stderr)
        print("         reported as lost. Use --section to check only what you moved verbatim.",
              file=sys.stderr)

    want = substantive(original)
    missing = [line for line in want if line not in combined]

    print("original: %s (%d substantive lines)" % (label, len(want)))
    print("now:      %s" % ", ".join(args.now))
    if not missing:
        print("RESULT:   OK -- every substantive line survived the move")
        return 0

    print("RESULT:   %d LINE(S) LOST" % len(missing))
    for line in missing[:args.show]:
        print("  LOST: %s" % line[:160])
    if len(missing) > args.show:
        print("  ... and %d more" % (len(missing) - args.show))
    print("\nEither restore them or delete them deliberately. A line that vanished by accident during")
    print("a move is indistinguishable from one you meant to cut, which is why this check exists.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
