# Codex Prompting Verification Steps

Run these in WSL (Codex requires WSL on Windows).

## Prerequisites

```bash
# Verify Codex is installed and authenticated
codex --version
codex login 2>&1 | head -3  # verify auth is configured

# Verify config
cat ~/.codex/config.toml
# Should show model and model_reasoning_effort

# Verify multi_agent is enabled
grep -q 'multi_agent = true' ~/.codex/config.toml && echo "OK: multi_agent enabled" || echo "MISSING: add [features] multi_agent = true"
```

## 1. Verify base prompt writes correctly

```bash
# Run the base prompt write from SKILL.md Step A
# Then check it exists and contains key directives
cat /tmp/codex-review-base.txt | head -5
# Should start with: "You are a senior engineer..."

# Verify key sections are present
grep -c "Critical Issues" /tmp/codex-review-base.txt
# Should be 1

grep -c "you MUST cite" /tmp/codex-review-base.txt
# Should be 1

grep -c "Batch-read them" /tmp/codex-review-base.txt
# Should be 1
```

## 2. Verify artifact-type fragments write correctly

```bash
# Write each artifact-type fragment from SKILL.md
# Then verify they exist
for type in code plan architecture design; do
  test -f /tmp/codex-review-${type}.txt && echo "OK: ${type}" || echo "MISSING: ${type}"
done
```

## 3. Verify prompt assembly

```bash
# Assemble a test prompt for code artifact, round 1
cat /tmp/codex-review-base.txt > /tmp/codex-review-prompt.txt
cat /tmp/codex-review-code.txt >> /tmp/codex-review-prompt.txt
cat >> /tmp/codex-review-prompt.txt <<ROUND
Files to review: src/example.ts
Claude's review: docs/plans/review-claude-round-1.md
Round: 1
Write the full review to: docs/plans/review-codex-round-1.md
ROUND

# Verify assembled prompt
wc -l /tmp/codex-review-prompt.txt
# Should be ~55-65 lines

# Verify all sections are present
grep "senior engineer performing an independent technical review" /tmp/codex-review-prompt.txt && echo "OK: autonomy framing"
grep "Batch-read" /tmp/codex-review-prompt.txt && echo "OK: parallel reads"
grep "Skip preamble" /tmp/codex-review-prompt.txt && echo "OK: no-preamble"
grep "Type safety" /tmp/codex-review-prompt.txt && echo "OK: quality criteria"
grep "Critical Issues" /tmp/codex-review-prompt.txt && echo "OK: severity-first output"
grep "you MUST cite" /tmp/codex-review-prompt.txt && echo "OK: disagreement evidence"
grep "Files to review" /tmp/codex-review-prompt.txt && echo "OK: round context"
```

## 4. Verify `codex review --base` works for code

```bash
# Dry run — check that the command parses correctly
# Use a small file to minimize cost
echo 'function add(a, b) { return a + b; }' > /tmp/test-file.js

echo "Review this file for correctness: /tmp/test-file.js" \
  | codex review --base main - \
  > /tmp/test-codex-output.md

# Check output was produced
test -s /tmp/test-codex-output.md && echo "OK: codex review produced output" || echo "FAIL: no output"

# Cleanup
rm -f /tmp/test-file.js /tmp/test-codex-output.md
```

## 5. Verify cleanup removes all temp files

```bash
# Create all expected temp files
touch /tmp/codex-review-base.txt \
      /tmp/codex-review-code.txt \
      /tmp/codex-review-plan.txt \
      /tmp/codex-review-architecture.txt \
      /tmp/codex-review-design.txt \
      /tmp/codex-review-prompt.txt

# Run cleanup command from SKILL.md Step 7
rm -f /tmp/codex-review-base.txt \
      /tmp/codex-review-code.txt \
      /tmp/codex-review-plan.txt \
      /tmp/codex-review-architecture.txt \
      /tmp/codex-review-design.txt \
      /tmp/codex-review-prompt.txt

# Verify all removed
for f in base code plan architecture design prompt; do
  test -f /tmp/codex-review-${f}.txt && echo "FAIL: ${f} still exists" || echo "OK: ${f} cleaned"
done
```

## 6. Spot-check severity-first output format

After running a real cross-review, verify the Codex output uses global severity grouping:

```bash
# The output should have severity headers at the top level, not nested under areas
head -30 docs/plans/review-codex-round-1.md

# Good: "### Critical Issues" appears before any area-specific grouping
# Bad: "## Security Review" → "### Critical Issues" (area-first, not severity-first)
```
