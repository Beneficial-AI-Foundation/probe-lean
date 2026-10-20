import Lean

/-! Stubs for the Aeneas names that probe-lean reads. `Aeneas.Std.WP.spec` has the
arity (3) and the program index (1) of the real statement. A label attribute
accepts `local` and `scoped`, as the Aeneas `step` attribute does. It must be
declared in a module that the theorem modules import. -/

namespace Aeneas.Std.WP
def spec {α : Type} (_x : Option α) (_p : α → Prop) : Prop := True
end Aeneas.Std.WP

register_label_attr step
