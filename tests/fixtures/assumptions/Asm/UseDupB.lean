import Dep.DupB

/-- Built against the `sorry` version of `dd1`: `["sorryAx"]`. -/
theorem useDd1B : True := dd1

/-- Built against the clean `dd2` of `Dep.DupB`: `["sorryAx"]`. -/
theorem useDd2B : True := dd2
