---
name: task-contract
description: >-
  Agent-only semantic risk and specification procedure.
  Load before finalizing or materially revising a ship specification or scout question, and before revising a coupled, unresolved, or evidence-heavy handoff for validation.
  Owns the proportionate high-risk handoff and pre-validation self-check guidance, and feeds task suitability into existing model-fit selection without adding a routing system.
user-invocable: false
metadata:
  internal: true
---

# task-contract

Assess the work's semantics before selecting a profile, not its project, model, language, file count, or labels such as "DTO", "frontend", or "docs-only".
Record a compact suitability basis and specification in `## Firstmate spec`; `../../../bin/fm-brief.sh` owns the scaffold.
This is task-authoring guidance, not a machine-checked schema or proof that every invariant has been identified.
Do not add a model call, project adapter, capability registry, or extra review merely to fill the contract.

## Semantic risk and disposition

Assess all six independent dimensions, with short evidence for nontrivial judgments.
Use `unknown` explicitly when evidence is missing, naming what must be learned and why it matters; unknown is never zero or low risk.
Axes do not cancel one another: five low risks cannot offset an irreversible operation.

| Dimension | Low | Elevated | High |
| --- | --- | --- | --- |
| Invariant complexity | Independent field or value rule | Interacting rules or ordering | State-machine, conservation, completeness, temporal or recovery proof |
| Cross-object coupling | Local object | One specified relationship | Multiple identities, joins, resources, transactions or distributed state |
| Ambiguity | Exact accepted behavior and oracle | Bounded implementation choice | Unresolved product semantics or incompatible accepted requirements |
| Blast radius | Isolated reversible behavior | Shared component or user-facing behavior | Privileged operation, broad failure or shared mutable external state |
| Reversibility | Simple code rollback | Data compatibility or staged recovery | Destructive or irreversible effect, or unproven rollback |
| Evidence burden | Known local check or text inspection | Integration, browser or multiple environments | Provenance, isolation, migration rehearsal, deployment-specific or unavailable proof |

Choose the disposition from the limiting dimension, retaining any other constraints rather than averaging scores:

- **routine:** bounded, reversible work with explicit behavior and a readily available oracle.
- **coupled:** behavior is specified but invariants interact; select a profile with evidence for that reasoning shape, or decompose at real invariant boundaries.
- **unresolved:** uncertainty could change whether or what to build; route the question through the existing decision owner, or commission a scout when a separate knowledge deliverable is needed.
- **authority-limited:** execution or acceptance needs authority not granted; more capable reasoning cannot supply that authority.

Scale the handoff to the limiting disposition: keep routine work at the short specification below, and for coupled, unresolved, authority-conflicting, or evidence-heavy work make the governing accepted behavior, its authority or source of truth, the disposition of every material unresolved or permission question, adversarial examples across the affected paths, evidence limits and the unresolved owners explicit in Firstmate spec.
A conflict between accepted requirements is itself unresolved work: escalate it to the existing decision owner rather than choosing silently, and when it cannot be settled before dispatch, scope an honestly incomplete result instead of promising a positive case.

Resolve an unknown that could change implementation or permission before shipping; bounded research may stay inside a ship only when it cannot change whether or what to build.
A scout may carry unresolved questions because answering them is its deliverable, not because it has implementation authority.
Decomposition must retain an owner and end-to-end validation for each shared invariant; dividing a transaction into easy files does not reduce its coupling.
A large generated mapping can be routine while a two-line authorization predicate needs substantial proof.

## Specification completeness

Keep routine work to one short paragraph or row where possible, not a mandatory set of empty headings or matrices.
Cover the following in Firstmate spec, expanding only where the work requires it:

| Element | Minimum useful content |
| --- | --- |
| Accepted behavior | The user-visible or operator-visible change, its authoritative source, and the source of truth that governs when accepted requirements conflict |
| Invariants | What must remain true, including relevant scope, identities and quantifiers |
| Examples and counterexamples | A scenario-to-positive/negative-oracle map across each affected path: an allowed case and a meaningful rejection or boundary for every changed executable claim, with negative cases derived independently of the implementation |
| Non-goals | What the request does not authorize, including tempting adjacent redesign or activation |
| Allowed scope and public surface | Bounded paths or justified patterns, protected exclusions, allowed abstractions and API changes; explicitly say when project instruction files are excluded |
| Validation and evidence limits | Known safe commands with arguments and working directory, expected results and what they prove, what evidence is unavailable or must not be substituted, and the exact unresolved prerequisite |
| Unresolved decisions | Explicitly none, or each material question with its checkpoint disposition, owner and affected behavior, including an authority conflict left unresolved |

`not applicable` requires a reason; do not use it to hide unknown behavior, missing authority or unavailable proof.
For a typo fix, one row can say: replace the requested phrase, preserve links and other text, no API or instruction-file changes, inspect the text/rendered diff, executable examples not applicable because no executable claim changes, no unresolved decisions.
For coupled work, expand relation or transition tables and adversarial combinations only as needed to make the invariant and its oracle explicit.
Reuse the project's established safe validation path; an unavailable prerequisite is not permission to run against production or invent a successful proof.

Preserve the actual request in `## Captain's intent`, including the substance of material it incorporates by reference, without widening it into Firstmate's checklist.
`../../../bin/fm-dod-lib.sh` alone owns intent provenance and the no-mistakes `--intent` selector, including legacy compatibility.
The suitability assessment, completeness procedure and Firstmate-authored constraints remain specification, never extra `--intent` content.
`../../../bin/fm-brief.sh` owns scope-aware project-memory instructions; excluded instruction-file knowledge belongs in the task report for separately authorized follow-up.

## Pre-validation self-check

For coupled, unresolved, authority-conflicting, or evidence-heavy work, instruct the worker in Firstmate spec to self-check before entering the already-selected no-mistakes run: inspect the complete changed diff, exercise the intended counterexamples with the targeted behavioral or traceability tests, record the exact tested commit, and list omitted evidence, skipped checks and outstanding conflicts.
Instruct the worker to pass those facts into the existing gate as evidence through the ordinary gate flow.
That self-check is input, not approval: it does not replace independent review, tests, lint, docs or CI, it never answers an ask-user finding, and it cannot weaken, skip or replace the selected delivery path.

## Existing selection and authority owners

Feed the suitability basis into `../harness-adapters/SKILL.md`'s model/effort and dispatch references and `../quota-array-dispatch/SKILL.md`'s reasoning-class fit gate.
Apply it to explicit, configured, static and typed-resolver choices alike, including a `clear` result or default fallback; a rule match is not suitability evidence.
Compare task demand with evidence for the candidate's exact runtime, model, effective effort and tool environment, recording uncertainty rather than inventing capability scores or inferring ability from a brand.
Unassessed capability calls for disclosed judgment, not an invented low score, authentication failure or automatic model upgrade.
Quota ranks suitable candidates through its existing owner; spare quota cannot make an unsuitable candidate fit.

Reassess and route to firstmate if a new identity boundary appears, requirements conflict, the oracle is missing, proof requires unauthorized execution, or implementation would invent semantics.
Narrowing scope, supplying a missing example, resolving a decision or repairing the evidence path may be better than switching models.
Repeated failures do not relax acceptance.
`../../../AGENTS.md` sections 7 and 11 retain delivery, scope-change, validation custody, decision and merge authority: this procedure grants none of them and adds no review outside the selected delivery path.
