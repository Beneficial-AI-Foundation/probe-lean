import Dep.SwapA

/-- Built against the axiom `sa` of `Dep.SwapA`. In the merged environment `sa` is the
theorem of `Dep.SwapB`: `["sa", "sb"]`. -/
theorem useSwapA : False := sa
