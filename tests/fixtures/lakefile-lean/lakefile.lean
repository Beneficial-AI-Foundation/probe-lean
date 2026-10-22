import Lake
open Lake DSL

/-! A `lakefile.lean` project for `extract` (issue #123). The package sets `srcDir`,
`Lib` adds its own `srcDir` under it, `«a.b»` needs `«»` quotes, and the default
executable `«my-exe»` has a quoted name. probe-lean reads all of it with Lake's
`loadWorkspace`, builds the executable root as `+Main` without linking it, and
emits the atoms of both libraries and of `Main`. -/

package «lakefile-lean» where
  srcDir := "src"

@[default_target] lean_lib Lib where
  srcDir := "Lib"
  roots := #[`Inner.A]

@[default_target] lean_lib «a.b» where

@[default_target] lean_exe «my-exe» where
  root := `Main
