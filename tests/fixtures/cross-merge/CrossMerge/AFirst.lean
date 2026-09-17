/-- Sorts before `CrossMerge.Other`, imports nothing: the project wins the name
`shared3`, the environment keeps the dependency's body. Both bodies are real proofs, so
`shared3` (an atom, attributed to this module) reads `transitively-verified` — not
`trusted`: a cross-boundary name follows the merged-declaration policy, and it is a
theorem. -/
theorem shared3 : True := True.intro
