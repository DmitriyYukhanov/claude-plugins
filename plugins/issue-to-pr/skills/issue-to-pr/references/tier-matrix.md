# Tier matrix — scale the machinery to the task (spec sec 5.2)

The pipeline runs the same gates every time, but the *depth* between them scales to
a tier. `scripts/tier-select.sh` computes the tier deterministically from
`triage-evidence.sh` signals (so it is CI-tested and cannot silently drift); the
SKILL reads `TIER` and routes each step accordingly.

## Machinery per tier

| Machinery | trivial | standard | complex | epic |
|---|---|---|---|---|
| Examples | typo, copy change, config value | bugfix, small feature in known code | new behavior / multi-file / design choices | new service or product, "from scratch" |
| Session effort | suggest `low` | default | `high` | `high` |
| Research (`skills/research`) | - | - | if unknowns | per child |
| Design | - | mini-design in the PR body | **design-panel** or `/cross-review` | **decompose** into children (`epic.md`) |
| Plan | - | inline checklist | writing-plans | per child |
| Tests / gates | always | always | always | per child |
| `/code-review` | `low --fix`, 1 pass | `medium --fix`, <=2 passes | `high --fix`, <=3 passes (may raise to `max` on escalation) | per child + `ultra` on integrator PRs |
| Security overlay | if sensitive paths | if sensitive paths | if sensitive paths | mandatory sweep |
| Report | 3 lines | short | full | dashboard |

## Rubric — signals to tier (implemented in `tier-select.sh`)

Fed `triage-evidence.sh` output on stdin; `--tier <t>` always overrides; borderline
picks the **higher** tier. Checked strongest-first:

- **epic:** `NEW_THING_HITS >= 3` AND `REF_PATHS_EXIST = 0` (a new system referencing
  no existing code). Epic *mode* is active (v2.0): the SKILL runs `epic-decompose.js`,
  gets one approval on the child breakdown, then drives the children sequentially
  in dependency order (full lifecycle in `epic.md`).
- **complex:** `NEW_THING_HITS >= 1` OR `CHECKLIST_ITEMS >= 3` OR `REF_PATHS_EXIST >= 3`
  OR a `design` / `ux` / `breaking` label.
- **trivial:** `NEW_THING_HITS = 0` AND `REF_PATHS_EXIST <= 1` AND `CHECKLIST_ITEMS <= 1`
  AND `BODY_LENGTH < 400` AND no `feature` / `design` / `epic` label.
- **standard:** everything else (a known-code change).

Every tier: the test plan for anything UI/layout/browser must be verifiable with the
project's `visual_cmd` or a dedicated browser test — never eyeballing alone.

## Security overlay

Regardless of tier, run `git diff --name-only "$BASE"...HEAD | sensitive-paths.sh`;
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
