// design-panel.js - autonomous design for a complex issue-to-pr task (spec sec 5.3).
// Replaces the brainstorming interview: three proposers from distinct angles, two
// adversarial critics that check claims against the actual code, and one judge that
// synthesizes a single design. Invoked by the SKILL as:
//   Workflow({scriptPath: "${CLAUDE_PLUGIN_ROOT}/workflows/design-panel.js",
//             args: {issue, title, contextFiles:[...], constraints, openQuestions:[...]}})
// Returns {design_md, rejected_alternatives[], open_questions[]}. The SKILL writes
// design_md to tmp/task-<N>/design.md and routes preference-bound open_questions to
// the ledger. Workflow agents have Read/Grep, so contextFiles are paths they read.

export const meta = {
  name: 'design-panel',
  description: 'Autonomous design panel for a complex issue: 3 proposers, 2 adversarial critics, 1 opus judge',
  phases: [
    { title: 'Propose', detail: 'three angles in parallel' },
    { title: 'Critique', detail: 'two adversarial critics vs the codebase' },
    { title: 'Judge', detail: 'opus synthesizes one design' },
  ],
}

const a = args || {}
const issue = a.issue ?? '?'
const title = a.title ?? ''
const contextFiles = Array.isArray(a.contextFiles) ? a.contextFiles : []
const constraints = a.constraints || 'none stated'
const openQuestions = Array.isArray(a.openQuestions) ? a.openQuestions : []

const ctxLine = contextFiles.length
  ? `Relevant files to read: ${contextFiles.join(', ')}`
  : 'Explore the repo (Grep/Glob/Read) to find the relevant files.'
const base = `Issue #${issue}: ${title}\n${ctxLine}\nConstraints: ${constraints}\nKnown open questions: ${openQuestions.length ? openQuestions.join('; ') : 'none'}`

const DESIGN_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    approach: { type: 'string' },
    design_md: { type: 'string' },
    tradeoffs: { type: 'string' },
    risks: { type: 'string' },
  },
  required: ['approach', 'design_md', 'tradeoffs', 'risks'],
}

const ANGLES = [
  { key: 'minimal-change', lens: 'Prefer the smallest change that solves the issue. Reuse existing patterns; avoid new abstractions and files unless clearly warranted.' },
  { key: 'robustness-first', lens: 'Prefer correctness and failure handling. Make invariants explicit, enumerate edge cases, and plan the tests before the code.' },
  { key: 'ux-first', lens: 'Prefer the clearest experience for the user or calling code: naming, defaults, and error messages that need no documentation.' },
]

phase('Propose')
// Attach each proposal's angle to its result BEFORE filtering, so a failed
// proposer can't shift the remaining proposals' labels (ANGLES[i] would mislabel).
const proposals = (await parallel(ANGLES.map(angle => () =>
  agent(
    `Propose a design for this issue from the "${angle.key}" angle. ${angle.lens}\n\n${base}\n\nRead the actual code first, then return a concrete design: what changes, in which files, and why; its tradeoffs; and its risks.`,
    { label: `propose:${angle.key}`, phase: 'Propose', model: 'sonnet', effort: 'high', schema: DESIGN_SCHEMA },
  ).then(r => (r ? { ...r, _angle: angle.key } : null)),
))).filter(Boolean)

if (proposals.length === 0) {
  // Total proposer failure: signal the SKILL to use its next fallback.
  return { design_md: '', rejected_alternatives: [], open_questions: [], _failed: 'no proposals produced' }
}

const proposalsText = proposals
  .map((p, i) => `--- Proposal ${i + 1} (${p._angle}) ---\nApproach: ${p.approach}\nDesign:\n${p.design_md}\nTradeoffs: ${p.tradeoffs}\nRisks: ${p.risks}`)
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
          proposal: { type: 'string' },
          verdict: { type: 'string', enum: ['kill', 'refine', 'keep'] },
          why: { type: 'string' },
        },
        required: ['proposal', 'verdict', 'why'],
      },
    },
    synthesis_hint: { type: 'string' },
  },
  required: ['verdicts', 'synthesis_hint'],
}
const critiques = (await parallel([1, 2].map(n => () => agent(
  `You are adversarial critic ${n} of the candidate designs for:\n${base}\n\n${proposalsText}\n\nRead the actual code to verify each proposal's claims. For each, return kill / refine / keep with a concrete reason grounded in the codebase (a design that reads plausibly but contradicts the code should be killed). Then give one synthesis hint for the strongest combined design.`,
  { label: `critique:${n}`, phase: 'Critique', model: 'sonnet', effort: 'high', schema: CRITIQUE_SCHEMA },
)))).filter(Boolean)

phase('Judge')
const JUDGE_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    design_md: { type: 'string' },
    rejected_alternatives: { type: 'array', items: { type: 'string' } },
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
  required: ['design_md', 'rejected_alternatives', 'open_questions'],
}
const judge = await agent(
  `You are the design judge for:\n${base}\n\nCandidate designs:\n${proposalsText}\n\nCritiques:\n${JSON.stringify(critiques, null, 2)}\n\nSynthesize ONE design_md (<=200 lines: problem, chosen approach, what changes where, an explicit test plan — anything UI/layout/browser must be verifiable with a visual command or a browser test, not eyeballing — and risks), grafting the best of the runners-up. List rejected_alternatives (one line each with why it lost). List open_questions: set preference_bound=true for public API naming, user-visible UX/copy, paid/external resources, new external dependencies or licenses, or breaking API/schema changes (these go to the human); for everything else set preference_bound=false and give your decision in decision_if_auto.`,
  { label: 'judge', phase: 'Judge', model: 'opus', effort: 'high', schema: JUDGE_SCHEMA },
)

if (!judge || !judge.design_md) {
  // Judge failed or produced nothing usable: signal the SKILL's next fallback.
  return { design_md: '', rejected_alternatives: [], open_questions: [], _failed: 'judge produced no design' }
}
return judge
