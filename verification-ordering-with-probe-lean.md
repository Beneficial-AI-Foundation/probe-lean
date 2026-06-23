# Verification Ordering with probe-lean: a Bottom-Up Loop under Top-Down Pressure

Short answer: **real verification is bottom-up construction driven by top-down semantic pressure — an iterative repair loop, not a one-shot ordering.** You prove leaves first and march up; the root goal keeps pushing back down to reveal which leaf specs were too weak; you fix them and re-prove. probe-lean's job is not to impose a single direction but to *structure that loop* — it gives the dependency graph, the leaf frontier, and the root pressure points so the agent knows where it is in the cycle. For Aeneas projects it gives substantially more, because the Aeneas-specific facts it surfaces are exactly the inputs the loop consumes.

## Two axes, two directions — but one loop

It's tempting to describe verification as a clean two-phase pipeline: "reason top-down to decide *what* the specs say, then prove bottom-up." That's the right intuition about the **two axes**, but it's wrong about the **execution**. The two axes don't run once each; they interleave in a feedback loop until the graph stabilizes.

Fix the terms against probe-lean's graph first. Edges point from a declaration to what it depends on (`type-`/`term-dependencies`). A **leaf** has no outgoing in-project edges (depends on nothing local); a **root** is something nothing depends on (your top-level theorem / entry function).

- **Logical dependency of specs → root drives leaves.** *What* a leaf's spec must guarantee is ultimately determined by what the root property needs from it. This is the top-down constraint.
- **Construction dependency of proofs → leaves drive root.** To actually *prove* anything, you need callees proven and registered first — especially under Aeneas's `progress` tactic, which looks up the `@[progress]` lemma for each call it steps over. You cannot soundly prove a caller before its callees. This is the bottom-up execution.

These two pull in opposite directions, and that tension *is* the workflow. You don't resolve it once; you converge on it.

## The realistic model: bottom-up execution under top-down pressure

```
verification = bottom-up execution with top-down semantic pressure
```

In practice the agent runs a three-beat closed loop over the dependency graph:

**Phase A — bottom-up construction.** Start at the leaves: no dependencies, so the spec can be derived directly from the implementation's behavior (for Aeneas, from the linked Rust). Write the spec, prove it, register it as a usable contract. Topologically sort the forward edges and march toward the root. probe-lean gives this sort directly, and `verification-status` tells you which leaves are already done so you don't redo them.

**Phase B — top-down validation pressure.** As you climb, the root specification presses down. A parent proof stalls. That stall is *information*: it surfaces that a child spec is

> **locally sound but globally insufficient** —

the leaf was proven correctly in isolation, but its contract is too weak (or the abstraction is wrong, or an invariant is missing) to discharge the parent's obligation. This is the single most common failure mode in compositional verification, and it is only visible from above.

**Phase C — repair loop.** Go back down and strengthen: tighten the leaf spec, fix the abstraction, or introduce the missing invariant. Re-prove the leaf, then retry the parent. Repeat until the SCC/subtree stabilizes.

So "prove leaves first" is correct, but it is not a sort you run once — it's the forward pass of a fixed-point iteration. The backward pass is the root pushing failure information down. The loop terminates when every node is proven against a spec strong enough for its parents.

The workflow probe-lean enables, then, is not a pipeline but a graph-iterative refinement:

1. **Construct bottom-up** — topo-sort the forward edges; write+prove leaf specs; climb.
2. **Apply top-down pressure** — when a parent fails, read it as "a descendant's spec is globally insufficient," using the reverse `specs`/`primary-spec` edges to find which contracts feed that parent.
3. **Repair and re-converge** — strengthen the implicated leaf spec/abstraction/invariant and re-prove the affected subtree.

**The one structural caveat: cycles.** Mutual recursion and Aeneas's `divergent`/`_loop` helpers create dependency cycles, and a topological sort doesn't exist across them. The agent must detect strongly-connected components in probe-lean's graph and treat each SCC as a *single* unit — proven together, usually via a shared loop invariant, and repaired together as one node in the loop above. probe-lean shows the cycle (the `_loop` declaration and its parent each appear with the back-edge); the agent runs SCC detection on top and collapses each SCC before sorting.

## For Aeneas projects, probe-lean helps much more

A pure-Lean project gives probe-lean only the call graph + sorry frontier. An Aeneas project lights up several extra fields that are precisely the inputs each beat of the loop consumes:

| probe-lean fact (Aeneas) | Which beat it feeds |
|---|---|
| **`rust-source`** (from the Aeneas docstring) | **Phase A construction.** The Rust is the ground truth for *what the function should do*. The agent reads the linked Rust to **derive the initial leaf spec** — the starting point the graph alone can't supply. |
| **`primary-spec` + `@[progress]`/`@[pspec]`/`@[step]` attributes** | **Phase A ordering / readiness.** Tells the agent which callees *already have a registered progress-spec*. Since `progress` needs those, this is the exact readiness signal: a caller is provable once all its callees show a registered spec. |
| **Reverse `specs`/`primary-spec` edges** | **Phase B pressure routing.** When a parent proof stalls, these edges identify *which* descendant contracts feed that parent — i.e. where to apply repair pressure rather than guessing. |
| **Trust base: `trusted` / `trusted-reason` (`external`, `axiom`, `externally_verified`)** — i.e. `*External.lean` (`FunsExternal`, `TypesExternal`) | **Loop boundary.** These are the **assumed boundary** — opaque/external functions Aeneas doesn't model. The agent must *not* try to prove or repair them; the loop bottoms out here. Prevents wasted effort on unprovable stubs. |
| **`viewify` molecules** (filtered to `Funs.lean`, carrying `rust-path`/`rust-lines`/`rust-name` + spec) | **The worklist itself.** One row = Lean function ↔ its Rust origin ↔ its spec file: the natural unit that moves through Phases A→B→C. |
| **Loop/`divergent` structure in the graph** | **SCC collapse.** Surfaces the loop helpers up front, so the agent knows which nodes must be proven (and repaired) together with a loop invariant rather than straight-line `progress`. |

So for Aeneas, probe-lean stops being just a call graph and becomes a **loop controller**: it gives (a) the Rust↔Lean mapping to *seed* leaf specs bottom-up, (b) the progress-spec readiness state to *order* the construction pass, (c) the reverse spec edges to *route* top-down repair pressure when a parent fails, (d) the trust boundary to know where the loop terminates, and (e) the loop/cycle structure to know which nodes converge together.

## What it still doesn't give (so the LLM still earns its keep)

probe-lean hands you the *scaffold, the facts, and your position in the loop* — order, contracts-already-present, trust base, Rust links, the pressure-routing edges. It does **not** write the spec content, decide *how much* to strengthen a spec when a parent fails, supply loop invariants, choose tactics, or carry the live goal state. Those remain the LLM's job (and the FVS prover/specifier agents'). The clean split: **probe-lean structures the loop — which nodes, in what order, and where failure points back to; the LLM runs each beat — what to prove, how to prove it, and how to repair when the pressure says a spec is too weak.**
