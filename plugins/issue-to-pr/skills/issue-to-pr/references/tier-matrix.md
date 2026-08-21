# Tier matrix — scale the machinery to the task (spec sec 5.2)

The pipeline runs the same gates every time, but the *depth* between them scales to
a tier. You pick it at Step 2 from the issue itself: `standard` unless the signals
below argue otherwise, `--tier` pins it, and any tier but `standard` is logged in the
ledger with the signal that moved it.

## Machinery per tier

| Machinery | trivial | standard | complex | epic |
|---|---|---|---|---|
| Examples | typo, copy change, config value | bugfix, small feature in known code | new behavior / multi-file / design choices | new service or product, "from scratch" |
| Session effort | suggest `low` | default | `high` | `high` |
| Research (Explore fork) | - | - | if unknowns | per child |
| Design | - | mini-design in the PR body | **design-panel** or `/cross-review` | **decompose** into children (`epic.md`) |
| Plan | - | inline checklist | writing-plans | per child |
| Tests / gates | always | always | always | per child |
| `/code-review` | `low --fix`, 1 pass | `medium --fix`, <=2 passes | `high --fix`, <=3 passes (may raise to `max` on escalation) | per child + `ultra` on integrator PRs |
| Security overlay | if sensitive paths | if sensitive paths | if sensitive paths | mandatory sweep |
| Report | 3 lines | short | full | dashboard |

## Rubric — signals to tier

`--tier <t>` always overrides; borderline picks the **higher** tier. Read strongest-first:

- **epic:** a new system or product, written without reference to code that exists yet
  ("from scratch", a new service). Epic *mode* is active (v2.0): the SKILL runs
  `epic-decompose.js`, gets one approval on the child breakdown, then drives the children
  sequentially in dependency order (full lifecycle in `epic.md`).
- **complex:** new behavior rather than a change to behavior that exists, or several
  checklist items, or several existing paths in scope, or a `design` / `ux` / `breaking` label.
- **trivial:** a copy or config change, short, one path at most, no `feature` / `design` /
  `epic` label.
- **standard:** everything else, and the answer whenever the signals disagree.

Tier what the run will actually do: a scope the conversation widened past the issue text
tiers on the wider scope.

Every tier: the test plan for anything UI/layout/browser must be verifiable with the
project's `visual_cmd` or a dedicated browser test — never eyeballing alone.

## Security overlay

Regardless of tier, run `sensitive-paths.sh --base "<BASE>"` from the worktree;
if `SENSITIVE=true`, add one `/security-review` pass. Sensitive = a path segment or
filename stem naming auth/authz, crypto/keys, secrets/credentials/sessions,
payment/billing, or migrations, plus `.env*`, `*.sql`, and key material. Matching is
segment/stem-exact, so `authors.py` and `payment_ui_copy.md` do not false-trip.

## Escalation ratchet (one-way)

Track in `state.json.metrics`: `confirmed_bugs_this_pass` (count of `/code-review`
CONFIRMED verdicts) and `gate_fail_streak.<gate>`. When **2+ confirmed bugs land in
one review pass**, or **the same gate fails twice**, escalate the review level one
notch (never down); trivial->standard also re-enters the design step. Surface the raw
per-pass counts in the Step 10 report so a missed ratchet is visible at the merge gate.
