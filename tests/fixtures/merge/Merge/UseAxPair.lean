import Merge.AxPairThm

/-- Built against the theorem version of `pairAx`. Its `assumptions` still list
`pairAx`, because the other version is an axiom. -/
theorem callerAx : True := pairAx
