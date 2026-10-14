/-- With `Dep.SwapB`: two modules that swap an axiom and a theorem. Lean keeps the
theorem of each name, so the kept bodies only call each other. The set walk follows
the dropped versions too, so a caller still lists `sa` and `sb`. -/
axiom sa : False

/-- See `sa`. -/
theorem sb : False := sa
