# Verdict Format

Structured output format for Codex review responses. Include this as `<structured_output_contract>` in prompts composed via `gpt-5-4-prompting`.

## Statuses

| Status | Meaning | Action |
|--------|---------|--------|
| `APPROVED` | No issues or all trivial | Stop, present summary |
| `MINOR_ISSUES` | Only minor/informational | Log findings, stop |
| `CHANGES_REQUESTED` | Actionable findings | Continue to next round |

## Output Structure

```
## Status
APPROVED | MINOR_ISSUES | CHANGES_REQUESTED

## Findings
- [severity] [category] file:line — description
  Fix: concrete suggested fix
- ...

## Summary
Brief overall assessment (2-3 sentences)
```

## Parsing Rules

- Extract status from first non-empty line after `## Status`
- Parse findings as list items matching `[severity] [category] file:line`
- If output doesn't match format, treat as `CHANGES_REQUESTED` with full output as a single finding (defensive — don't lose review content)

Aligns with codex plugin's `review-output.schema.json` for `/codex:review`. Provides markdown format for `/codex:rescue` responses.
