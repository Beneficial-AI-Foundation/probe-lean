/-
  The data that the workspace helper (`ProbeLean/Workspace.lean`) prints, and its
  decoders. The helper runs as `lake env <probe-lean> workspace-info` and
  `lake env <probe-lean> workspace-owners <file>`, so it sees the project as Lake
  does. This module does not import `Lake`, so the unit tests can use the decoders
  without it. Every name stays a `Name`, written and read with `Name`'s `ToJson` and
  `FromJson`, so a `«a.b»` name keeps its single component.
-/
import Lean

namespace ProbeLean

open Lean

/-- A `lean_lib` of the root package and the modules of `LeanLib.getModuleArray`.
    `error` holds the message if `getModuleArray` failed, and `modules` is then
    empty. -/
structure LibInfo where
  name : Name
  modules : Array Name
  error : Option String := none
  deriving ToJson, FromJson, Repr, BEq, Inhabited

/-- A `lean_exe` of the root package and the name of its root module. -/
structure ExeInfo where
  name : Name
  root : Name
  deriving ToJson, FromJson, Repr, BEq, Inhabited

/-- The answer of `workspace-info`. `leanLibDir` is `ws.root.leanLibDir` as Lake
    stores it, relative to the project directory. `leanPath` is `LEAN_PATH` in the
    environment of `lake env`. -/
structure WorkspaceInfo where
  leanGithash : String
  leanPath : String
  leanLibDir : String
  defaultTargets : Array Name
  libs : Array LibInfo
  exes : Array ExeInfo
  deriving ToJson, FromJson, Repr, Inhabited

/-- One entry of the answer of `workspace-owners`: the `lean_lib` that
    `ws.root.findModule?` returns for `module`, and the `lean_exe` of the root
    package whose root is `module`. -/
structure OwnerInfo where
  module : Name
  lib : Option Name := none
  exe : Option Name := none
  deriving ToJson, FromJson, Repr, BEq, Inhabited

/-- The exit code of the helper when the target's Lean is not the Lean of
    probe-lean. The helper then does not load the workspace. -/
def helperGithashExit : UInt32 := 3

/-- Whether the githash of the target's Lean equals the githash of probe-lean's
    Lean. Surrounding whitespace, such as the newline of `lean --githash`, does not
    count. -/
def githashMatches (target probe : String) : Bool :=
  target.trimAscii.toString == probe.trimAscii.toString

/-- The error for a target whose Lean is not the Lean of probe-lean. -/
def formatGithashMismatch (target probe : String) : String :=
  "Error: the target project uses a different Lean than probe-lean.\n" ++
    s!"  target Lean githash:      {target.trimAscii}\n" ++
    s!"  probe-lean Lean githash:  {probe.trimAscii}\n" ++
    "probe-lean reads .olean files, which only the same Lean can read. Install the " ++
    "probe-lean build for the target's Lean with the installer's --from-project option."

/-- Decode the answer of a helper subcommand: the last non-empty line of stdout,
    one JSON value. The lines before it are skipped, because a Nix `shellHook` can
    print to stdout before the helper runs. On a failure, the error holds the raw
    output. -/
def decodeLastLine [FromJson α] (command stdout : String) : Except String α :=
  let lines := (stdout.splitOn "\n").filter (!·.trimAscii.isEmpty)
  let fail (e : String) : Except String α :=
    .error s!"could not decode the output of {command}: {e}\nRaw output:\n{stdout}"
  match lines.getLast? with
  | none => fail "no output"
  | some line =>
    match Json.parse line >>= fromJson? with
    | .ok a => .ok a
    | .error e => fail e

/-- Decode the answer of `workspace-info` (`decodeLastLine`). -/
def decodeWorkspaceInfo (stdout : String) : Except String WorkspaceInfo :=
  decodeLastLine "workspace-info" stdout

/-- Decode the answer of `workspace-owners`: one JSON array of `OwnerInfo` objects
    on the last line (`decodeLastLine`). -/
def decodeOwners (stdout : String) : Except String (Array OwnerInfo) :=
  decodeLastLine "workspace-owners" stdout

/-- The answer of `workspace-owners` must hold exactly one object per requested
    name and no other object. -/
def checkOwnersComplete (requested : Array Name) (answers : Array OwnerInfo)
    : Except String Unit := do
  let req := Std.HashSet.ofArray requested
  let mut seen : Std.HashSet Name := {}
  for a in answers do
    unless req.contains a.module do
      throw s!"workspace-owners answered for {a.module}, which was not requested"
    if seen.contains a.module then
      throw s!"workspace-owners answered twice for {a.module}"
    seen := seen.insert a.module
  for n in requested do
    unless seen.contains n do
      throw s!"workspace-owners gave no answer for {n}"

/-- The request file of `workspace-owners`: one name per line, each a JSON string,
    so that a name with `«»` quotes is read back as the same `Name`. -/
def encodeOwnerRequest (names : Array Name) : String :=
  String.join (names.toList.map fun n => (toJson n).compress ++ "\n")

/-- Read the request file of `workspace-owners` (`encodeOwnerRequest`). -/
def decodeOwnerRequest (content : String) : Except String (Array Name) := do
  let lines := (content.splitOn "\n").filter (!·.trimAscii.isEmpty)
  lines.toArray.mapM fun l => Json.parse l >>= fromJson?

end ProbeLean
