# Remediation increments

This page is the maintainer-architecture owner for the four remediation increments C, D, E, and F: what each one owns, the order they land in, and how they compose.
The private reports under `data/` own the chronological DeepSeek I1A evidence, run identifiers, and per-round detail; this page keeps only the distilled reason each increment exists and points at the code and configuration owners that carry the mechanics.
The split follows one owner per failure mode rather than one large fix: C versions the task instructions, D filters worker suitability, E preserves review findings, and F binds validation proof to immutable content generations.

## C - version the task instructions

C is the opt-in task-contract binding owned by the firstmate repository.
The task's existing Markdown `## Captain's intent` and `## Firstmate spec` bodies stay the editable specification, and the binding records the intent digest, the effective-spec digest, the task id, ship kind, a monotonic revision, the Firstmate-supplied risk levels, and one canonical binding digest.
For promoted scout briefs, the effective spec also includes the promoted ship spec and delivery contract sections so a ship relaunch cannot accept edited promoted delivery instructions without re-adoption.
[`bin/fm-task-contract.sh`](../bin/fm-task-contract.sh) owns adoption and the read-only check, [`bin/fm-task-contract-lib.sh`](../bin/fm-task-contract-lib.sh) owns the record format and the launch gate, and [`bin/fm-spawn.sh`](../bin/fm-spawn.sh) is the sole emitter of the `binding_*` task-record fields.
Editing those Markdown inputs without deliberate re-adoption makes an enrolled launch or relaunch refuse, so "the same task" means the same instructions.
In the DeepSeek I1A run the brief was corrected between rounds and evidence was attributed to a moving task; C would have made each accepted instruction set a numbered revision so a result cannot silently belong to different words.
C's limit is identity, not quality: it proves the instructions did not change, never that they were complete, so the prompt gaps the incident review found would still be the author's problem.

## D - filter worker suitability

D adds declared capability to the existing dispatch configuration and makes the shared suitability predicate check it before a candidate is selected or a `clear` result is emitted.
[`bin/fm-dispatch-resolve.sh`](../bin/fm-dispatch-resolve.sh) and [`bin/fm-bootstrap.sh`](../bin/fm-bootstrap.sh) own validation through one shared helper, and [`docs/configuration.md`](configuration.md) owns the profile schema while `AGENTS.md` sections 4 and 7 keep the routing and authority rules.
Its dependency is C: suitability is declared against a bound task identity rather than a free-form description.
The I1A run sent one large coupled financial-evidence state machine to a Flash model as a "contracts-only" task; D would have forced a declared reasoning class before ranking and returned non-clear when no suitable candidate existed instead of launching the unsuitable one.
D's limit is that it filters declared capability, not measured ability, and unmodeled or unmeasurable headroom stays disclosed uncertainty rather than a fabricated low score.

## E - preserve findings until closure

E is the no-mistakes engine's durable findings ledger: immutable finding ids, per-round observations, fix revisions, reproducer links, and an explicit closure reviewer.
An unresolved blocking finding must prevent a final acceptance verdict even when the next scan is empty, and imported legacy history becomes `needs_reconciliation` rather than fabricated closure.
The engine owns this contract and Firstmate only consumes it.
In the I1A run the first review found three error-level blockers and two ask-user scope warnings, answering the two ask-user findings let the three unselected blockers disappear from the next stateless review, and the pipeline reported that no issues remained; E keeps them open until they are explicitly closed.
E's limit is that it preserves what a review reported, not what a review missed; it cannot discover a defect nobody found, so independent review remains useful.

## F - bind proof to immutable generations

F is the no-mistakes engine's work-generation and attestation contract: sealed inputs, immutable result objects, phase-scoped write sets, and a final attestation bound to the exact tested content.
A later documentation or lint phase that changes relevant inputs invalidates the transitive dependent results instead of leaving stale proof attributed to the current head.
The engine owns the generations, phase scope, plan input, and attestation, and Firstmate consumption waits for a compatible release and the public protocol.
In the I1A run evidence was generated before source and tests changed, and the document phase changed source and test files after the test phase, so stale evidence was repeatedly corrected and invalidated; F would keep each proof attached to the generation it actually tested.
F's limit is that a digest binds content, not trust: it cannot prove the executor was trustworthy, and it does not prove the selected tests were adequate.

## Dependency order and composition

The landing order is C, then D, with E independent and F after E.
C lands first because it is the identity the later increments reference: D binds suitability to it, and later engine receipts are compared against it.
E is an independent engine release, and F depends on E plus an agreed public protocol.
A later increment consumes engine receipts from a compatible release plus C, and the cursor-wait adapter waits on the durable engine revision protocol.
The four are complementary, not substitutable: C fixes which instructions were accepted, D fixes which worker should run them, E fixes what the review found, and F fixes what the proof actually tested.
No single increment would have prevented the DeepSeek I1A run on its own, and none of them replaces an independent oracle or a clear specification.
