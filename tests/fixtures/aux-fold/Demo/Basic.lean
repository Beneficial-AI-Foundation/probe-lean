/-- A lemma with a `sorry`: must contaminate everything that uses it. -/
theorem sorried_bound (n : Nat) : 0 < n + 1 := by sorry

/-- Control. A theorem's proof *is* its value, so nothing is abstracted and the
edge to `sorried_bound` already survives `partitionDeps`. The fold must leave
this atom byte-identical. -/
theorem theoremUse : 0 < 4 := sorried_bound 3

/-- Fold case. The proof obligation of the anonymous constructor is abstracted
into an auxiliary (`_proof_N`), so `tacticUse`'s only direct project dependency
is that auxiliary and the edge to `sorried_bound` is hidden. -/
def tacticUse : { n : Nat // 0 < n + 1 } := ⟨3, by exact sorried_bound 3⟩

/-- Shared-auxiliary case. Writing the proof as a term rather than a tactic
block does *not* avoid the abstraction on this toolchain — and because the
resulting proof term is identical to `tacticUse`'s, both declarations reference
the **same** auxiliary. The fold must therefore attribute it to both hosts,
driven by who references it rather than by its name prefix. -/
def atomicUse : { n : Nat // 0 < n + 1 } := ⟨3, sorried_bound 3⟩

/-- Negative control. Same abstraction, but the auxiliary reaches no `sorry`:
folding must not contaminate this atom, which stays `transitively-verified`. -/
def cleanUse : { n : Nat // 0 < n + 1 } := ⟨3, by exact Nat.succ_pos 3⟩
