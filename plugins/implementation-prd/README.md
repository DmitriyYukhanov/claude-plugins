# implementation-prd

A Claude Code plugin for writing implementation-ready spec bundles that another coding agent can build from directly across frontend, backend, desktop, mobile, SaaS, platform, and feature work.

## Installation

```bash
/plugin install implementation-prd@DmitriyYukhanov/claude-plugins
```

## Features

### Skill: `implementation-prd`

Auto-activating reference knowledge for turning app, service, platform, or complex feature requests into a build-ready spec bundle.

Covers:
- decisive PRDs for apps, services, products, platforms, and large features;
- explicit in-scope / out-of-scope boundaries;
- contracts for APIs, IPC, queues, webhooks, background jobs, and error envelopes;
- SQL schema or data-model artifacts;
- test plans with unit, integration, E2E or end-to-end-equivalent, negative, and exit criteria;
- implementation order, risks, default technical decisions, and Definition of Done.

### Script: `init-spec-bundle.sh`

Scaffolds the standard bundle:
- `<slug>_prd.md`
- `<slug>_contracts.md`
- `<slug>_schema.sql` or `<slug>_data-model.md`
- `<slug>_testplan.md`

Usage:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-spec-bundle.sh" my-feature feature docs/specs/my-feature sql

bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-spec-bundle.sh" billing-worker system docs/specs/billing-worker data-model
```

## Usage

The skill activates automatically when the user asks for a detailed PRD, implementation-ready spec, backend service spec, frontend or mobile app spec, build-ready feature requirements, or a documentation bundle that Claude Code or Codex can implement with minimal follow-up.

Examples:

```text
Write an implementation-ready PRD bundle for a local-first podcast clipping app

Draft a build-ready feature spec for subscription-gated cloud analysis in our desktop product

Turn this rough brief into a PRD + contracts + schema or data model + test plan that Codex can one-shot implement

Write an implementation-ready spec bundle for a multi-tenant billing API and worker pipeline

Create a mobile app spec bundle for offline field inspections with sync and conflict resolution
```

## License

MIT
