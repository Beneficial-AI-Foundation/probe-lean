/-
  Nix environment detection.
  When a target Lean project ships a shell.nix or flake.nix, lake
  invocations can be wrapped inside the Nix environment so that FFI
  system dependencies (zlib, OpenSSL, …) are available automatically.
-/

namespace ProbeLean

/-- Which flavour of Nix environment a project provides. -/
inductive NixMode where
  | flake
  | shell
  deriving Repr, BEq

instance : ToString NixMode where
  toString
    | .flake => "flake"
    | .shell => "shell"

/-- Check if the target project provides a Nix shell environment.
    `flake.nix` takes precedence (newer Nix convention). -/
def detectNixShell (projectPath : System.FilePath) : IO (Option NixMode) := do
  if ← (projectPath / "flake.nix").pathExists then return some .flake
  if ← (projectPath / "shell.nix").pathExists then return some .shell
  return none

/-- Check if the nix binary required for the given mode is on PATH. -/
def isNixAvailable (mode : NixMode) : IO Bool := do
  let bin := match mode with
    | .flake => "nix"
    | .shell => "nix-shell"
  let result ← IO.Process.output { cmd := "which", args := #[bin] }
  return result.exitCode == 0

end ProbeLean
