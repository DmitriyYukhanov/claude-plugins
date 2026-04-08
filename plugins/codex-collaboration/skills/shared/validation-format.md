# Validation Format

Per-finding validation output used in collaborative-loop step 4. Distinct from the verdict format — this evaluates the driver's individual findings, not the overall state.

Include this as `<structured_output_contract>` in Codex validation prompts composed via `gpt-5-4-prompting`.

## Output Structure

```
## Confirmed Findings
- [finding #] CONFIRM — evidence from code/spec

## Refined Findings
- [finding #] REFINE — agree with the issue but disagree on severity/fix: <revised assessment>

## Rejected Findings
- [finding #] REJECT — evidence why this is a false positive

## New Findings (Missed by Driver)
- [severity] [category] file:line — description

## Status
VALIDATED | PARTIALLY_VALIDATED | REJECTED

## Summary
Brief assessment (confirmed X, refined Y, rejected Z, found W new)
```

## Parsing Rules

- `VALIDATED` — majority confirmed, proceed with confirmed + refined + new findings
- `PARTIALLY_VALIDATED` — some confirmed, some rejected, proceed with confirmed + refined + new only
- `REJECTED` — majority rejected, escalate to user before proceeding
- REFINE counts as partial agreement — the issue is real but the severity or fix needs adjustment. Treat refined findings as confirmed with the validator's severity/fix taking precedence.
