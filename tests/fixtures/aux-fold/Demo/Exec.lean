/-!
Executable bodies the kernel does not see. `verification-status` is about kernel
dependencies: a `partial def`'s body compiles to `X._unsafe_rec`, and the kernel
constant `X` is an opaque inhabitant with no edge to it. So `loopy` reads
`transitively-verified` although its body is a `sorry`, `loopy._unsafe_rec` is a
direct carrier listed `[direct] [not emitted]` by `check-axioms`, and the build-log
cross-check prints a specific `Note(log):` line instead of a generic divergence.
Documented in `docs/SCHEMA.md` (`verification-status`); whether such hosts should
count as carriers is a spec decision, not a silent change.
-/

/-- `transitively-verified` by the kernel; the `sorry` lives in `loopy._unsafe_rec`. -/
partial def loopy (n : Nat) : Nat := if n = 0 then sorry else loopy (n - 1)
