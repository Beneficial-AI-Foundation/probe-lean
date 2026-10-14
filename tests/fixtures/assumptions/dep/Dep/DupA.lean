/-- With `Dep.DupB`: two modules declare the same theorems, one proof with `sorry`.
Lean keeps one version of each name. `dd1` is clean here and `dd2` uses `sorry`, and
`Dep.DupB` swaps them, so one of the two kept versions is clean whatever the import
order. The set walk follows the dropped versions too, so every caller lists
`sorryAx`. -/
theorem dd1 : True := True.intro

/-- See `dd1`. -/
theorem dd2 : True := sorry
