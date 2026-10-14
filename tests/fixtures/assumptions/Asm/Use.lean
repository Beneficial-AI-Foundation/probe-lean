import Dep.Basic
import Dep.DepExternal
import Dep.Merge
import Asm.FooExternal

/-! Callers of the dependency rows and of the trusted constructor and recursor. -/

/-- `["d"]`. -/
noncomputable def useD : Nat := d

/-- `["sorryAx"]`, `transitively-verified`. -/
theorem useDepSorry : True := depSorry

/-- `["sorryAx"]`, `transitively-verified`. -/
theorem useDepVouched : True := depVouched

/-- `["sorryAx"]`, `transitively-verified`. -/
def useDepExt : Nat := depExt 1

/-- A caller of the trusted recursor `BadBox.rec`: `["sorryAx"]`. -/
theorem badBoxCases (b : BadBox) : True := BadBox.rec (fun _ => trivial) b

/-- A caller of the trusted constructor `BadBox.mk`: `["sorryAx"]`. -/
def badMk := @BadBox.mk
