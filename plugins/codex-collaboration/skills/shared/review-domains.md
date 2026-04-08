# Review Domains

Focus areas per artifact type. Inject these into `<task>` blocks when composing prompts for Codex via the `gpt-5-4-prompting` skill patterns.

## Code

Agents: `security-reviewer`, `performance-reviewer`, `correctness-reviewer`, `test-coverage-reviewer`, `maintainability-reviewer`

- Correctness & edge cases
- Security vulnerabilities
- Performance bottlenecks
- Test coverage gaps
- Error handling completeness
- Consistency with surrounding code patterns
- Import/type correctness
- No debug code, TODOs, or placeholders

## Plan

Agents: `completeness-reviewer`, `feasibility-reviewer`

- Requirement completeness (every requirement → at least one task)
- DAG validity (no cycles in task ordering)
- Dependency correctness
- Realistic estimates given scope
- Task clarity and assumption identification

## Architecture

Agents: `patterns-reviewer`, `scalability-reviewer`

- Pattern consistency across components
- Separation of concerns / clear boundaries
- Scalability & bottleneck analysis
- Deployment constraints
- Coupling analysis
- Missing abstractions
- Trade-off rationale

## Design

Agents: `requirements-reviewer`, `tradeoffs-reviewer`

- Requirements coverage
- Technical feasibility
- Scope creep detection
- Missing decisions / unresolved trade-offs
- Decision rationale with alternatives considered
- User impact (UX, performance, accessibility)

## Shared Across All Types

- Severity levels: Critical > High > Medium > Minor
- Findings format: `[severity] [category] file:line — description`
- Global ordering by severity (not grouped by area)
- Every finding must cite specific code/text — no vague observations
