// epic-decompose.js - decompose a large/epic issue into child issues (spec sec 6.1).
// For an issue too big to drive as one PR: three proposers draft a child breakdown
// from distinct angles, one or two adversarial critics check each breakdown against
// the actual code (independently mergeable, acyclic dependency order, complete
// coverage), and one judge synthesizes a single dependency-ordered set of children.
// Invoked by the SKILL as:
//   Workflow({scriptPath: "${CLAUDE_PLUGIN_ROOT}/workflows/epic-decompose.js",
//             args: {issue, title, body, contextFiles:[...], constraints}})
// Returns {plan_md, children[], open_questions[]}. The SKILL shows plan_md at the
// ledger checkpoint for approval (no raw JSON), opens each child as its own issue
// linked "Part of #<parent>", and routes preference-bound open_questions to the
// ledger. Workflow agents have Read/Grep, so contextFiles are paths they read.

export const meta = {
  name: 'epic-decompose',
  description: 'Decompose an epic issue into dependency-ordered child issues: 3 proposers, 2 adversarial critics, 1 opus judge',
  phases: [
    { title: 'Propose', detail: 'three breakdown angles in parallel' },
    { title: 'Critique', detail: 'two adversarial critics vs the codebase' },
    { title: 'Judge', detail: 'opus synthesizes one dependency-ordered breakdown' },
  ],
}

const a = args || {}
const issue = a.issue ?? '?'
const title = a.title ?? ''
const body = a.body ?? ''
const contextFiles = Array.isArray(a.contextFiles) ? a.contextFiles : []
const constraints = a.constraints || 'none stated'

const ctxLine = contextFiles.length
  ? `Relevant files to read: ${contextFiles.join(', ')}`
  : 'Explore the repo (Grep/Glob/Read) to find the relevant files.'
const base = `Epic issue #${issue}: ${title}\n\nParent issue body:\n${body || '(no body provided)'}\n\n${ctxLine}\nConstraints: ${constraints}`

// One child issue: independently mergeable/testable, with its dependencies named.
const CHILD_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    title: { type: 'string' },
    body: { type: 'string' },
    depends_on: { type: 'array', items: { type: 'string' } },
    tier_estimate: { type: 'string', enum: ['trivial', 'standard', 'complex'] },
  },
  required: ['title', 'body', 'depends_on', 'tier_estimate'],
}

const PROPOSE_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    children: { type: 'array', items: CHILD_SCHEMA },
  },
  required: ['children'],
}

const ANGLES = [
  { key: 'by-layer', lens: 'Split along architectural boundaries (data model, service/logic, API, UI, config/build). Each child owns one layer end-to-end enough to merge and test on its own.' },
  { key: 'by-risk', lens: 'Sequence the riskiest and most uncertain work first: land a thin spike or foundation that de-risks the unknowns, then build safer increments on top of it.' },
  { key: 'by-deliverable', lens: 'Split into independently shippable, user-visible slices. Each child delivers one coherent capability that could merge and provide value even if the rest slips.' },
]

phase('Propose')
// Attach each breakdown's angle to its result BEFORE filtering, so a failed
// proposer can't shift the remaining proposals' labels (ANGLES[i] would mislabel).
const proposals = (await parallel(ANGLES.map(angle => () =>
  agent(
    `Decompose this epic into child issues from the "${angle.key}" angle. ${angle.lens}\n\n${base}\n\nRead the actual code first. Return an ordered list of children: each must be independently mergeable and testable standalone. For each child give a title, a body (what it does, which files, how it is tested), its depends_on (reference the other children it needs by their exact title, or 1-based index; empty for none), and a tier_estimate of trivial / standard / complex. The union of all children must cover the full parent scope with no gaps and no overlap.`,
    { label: `propose:${angle.key}`, phase: 'Propose', model: 'sonnet', effort: 'high', schema: PROPOSE_SCHEMA },
  ).then(r => (r ? { ...r, _angle: angle.key } : null)),
))).filter(Boolean)

if (proposals.length === 0) {
  // Total proposer failure: signal the SKILL to use its next fallback.
  return { plan_md: '', children: [], open_questions: [], _failed: 'no proposals produced' }
}

const proposalsText = proposals
  .map((p, i) => {
    const childLines = (Array.isArray(p.children) ? p.children : [])
      .map((c, j) => `  ${j + 1}. ${c.title} [${c.tier_estimate}] depends_on: ${(Array.isArray(c.depends_on) && c.depends_on.length) ? c.depends_on.join(', ') : 'none'}\n     ${c.body}`)
      .join('\n')
    return `--- Breakdown ${i + 1} (${p._angle}) ---\n${childLines || '  (no children)'}`
  })
  .join('\n\n')

phase('Critique')
const CRITIQUE_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    verdicts: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        properties: {
          breakdown: { type: 'string' },
          verdict: { type: 'string', enum: ['kill', 'refine', 'keep'] },
          independently_mergeable: { type: 'boolean' },
          dependency_order_ok: { type: 'boolean' },
          coverage_complete: { type: 'boolean' },
          why: { type: 'string' },
        },
        required: ['breakdown', 'verdict', 'independently_mergeable', 'dependency_order_ok', 'coverage_complete', 'why'],
      },
    },
    synthesis_hint: { type: 'string' },
  },
  required: ['verdicts', 'synthesis_hint'],
}
const critiques = (await parallel([1, 2].map(n => () => agent(
  `You are adversarial critic ${n} of the candidate epic breakdowns for:\n${base}\n\n${proposalsText}\n\nRead the actual code to verify each breakdown. For each, check three things and set the booleans: (a) independently_mergeable - is every child mergeable and testable standalone, not a half-change that breaks the build; (b) dependency_order_ok - is the depends_on graph acyclic and correct, with no missing edges; (c) coverage_complete - does the union of children cover the whole parent scope with no gaps and no overlap. Return kill / refine / keep with a concrete reason grounded in the codebase (a breakdown that reads plausibly but contradicts the code, has a dependency cycle, or leaves a scope gap should be killed or refined). Then give one synthesis hint for the strongest combined breakdown.`,
  { label: `critique:${n}`, phase: 'Critique', model: 'sonnet', effort: 'high', schema: CRITIQUE_SCHEMA },
)))).filter(Boolean)

phase('Judge')
const JUDGE_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    plan_md: { type: 'string' },
    children: { type: 'array', items: CHILD_SCHEMA },
    open_questions: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        properties: {
          question: { type: 'string' },
          preference_bound: { type: 'boolean' },
          decision_if_auto: { type: 'string' },
        },
        required: ['question', 'preference_bound', 'decision_if_auto'],
      },
    },
  },
  required: ['plan_md', 'children', 'open_questions'],
}
const judge = await agent(
  `You are the decomposition judge for:\n${base}\n\nCandidate breakdowns:\n${proposalsText}\n\nCritiques:\n${JSON.stringify(critiques, null, 2)}\n\nSynthesize ONE final set of children, grafting the best of the runners-up. Rules you MUST follow:\n- Every child is independently mergeable and testable standalone.\n- Order the children so that every child's depends_on entries appear BEFORE it in the list; reference dependencies by the exact title of the earlier child. The graph must be acyclic.\n- The union of children covers the full parent scope with no gaps and no overlap.\n- Each child body ends with a line noting it will link "Part of #${issue}".\n- Give each child a tier_estimate of trivial / standard / complex.\n\nAlso write plan_md: a human-readable rendered plan the user approves WITHOUT reading raw JSON. Number the children; for each show its title, a one-line intent, its depends_on, and its tier_estimate. End plan_md with a "Execution order" list naming the children in dependency order (the order a worker would pick them up).\n\nList open_questions: set preference_bound=true ONLY for scope or product decisions that need the human (what is in vs out of scope, which slices ship, user-visible product choices); for everything else set preference_bound=false and give your decision in decision_if_auto.`,
  { label: 'judge', phase: 'Judge', model: 'opus', effort: 'high', schema: JUDGE_SCHEMA },
)

if (!judge || !judge.plan_md) {
  // Judge failed or produced nothing usable: signal the SKILL's next fallback.
  return { plan_md: '', children: [], open_questions: [], _failed: 'judge produced no plan' }
}
return judge
