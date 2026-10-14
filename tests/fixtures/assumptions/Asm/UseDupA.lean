import Dep.DupA

/-- Built against the clean `dd1` of `Dep.DupA`: `["sorryAx"]`. -/
theorem useDd1A : True := dd1

/-- Built against the `sorry` version of `dd2`: `["sorryAx"]`. -/
theorem useDd2A : True := dd2
