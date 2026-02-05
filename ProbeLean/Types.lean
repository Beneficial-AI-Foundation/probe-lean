/-
  Types for probe-lean atomize output.
  Defines Atom and CodeTextInfo with JSON serialization matching probe-verus format.
-/
import Lean.Data.Json

namespace ProbeLean

/-- Source location information with line range -/
structure CodeTextInfo where
  linesStart : Nat
  linesEnd : Nat
  deriving Repr, BEq

/-- Custom JSON serialization for CodeTextInfo with hyphenated field names -/
instance : Lean.ToJson CodeTextInfo where
  toJson info := Lean.Json.mkObj [
    ("lines-start", Lean.toJson info.linesStart),
    ("lines-end", Lean.toJson info.linesEnd)
  ]

instance : Lean.FromJson CodeTextInfo where
  fromJson? json := do
    let linesStart ← json.getObjValAs? Nat "lines-start"
    let linesEnd ← json.getObjValAs? Nat "lines-end"
    return { linesStart, linesEnd }

/-- Declaration kind -/
inductive DeclKind where
  | «def»
  | «theorem»
  | «abbrev»
  | «class»
  | «structure»
  | «inductive»
  | «instance»
  | «axiom»
  | «opaque»
  | «quot»
  deriving Repr, BEq

instance : Lean.ToJson DeclKind where
  toJson
    | .def => "def"
    | .theorem => "theorem"
    | .abbrev => "abbrev"
    | .class => "class"
    | .structure => "structure"
    | .inductive => "inductive"
    | .instance => "instance"
    | .axiom => "axiom"
    | .opaque => "opaque"
    | .quot => "quot"

instance : Lean.FromJson DeclKind where
  fromJson? json := do
    let s ← json.getStr?
    match s with
    | "def" => return .def
    | "theorem" => return .theorem
    | "abbrev" => return .abbrev
    | "class" => return .class
    | "structure" => return .structure
    | "inductive" => return .inductive
    | "instance" => return .instance
    | "axiom" => return .axiom
    | "opaque" => return .opaque
    | "quot" => return .quot
    | _ => throw s!"Unknown DeclKind: {s}"

/-- An atom representing a declaration in the dependency graph -/
structure Atom where
  /-- Full qualified name -/
  name : String
  /-- Display name (last component) -/
  displayName : String
  /-- Names of declarations this depends on -/
  dependencies : Array String
  /-- Module name containing this declaration -/
  codeModule : String
  /-- File path to source -/
  codePath : String
  /-- Source location info -/
  codeText : Option CodeTextInfo
  /-- Declaration kind -/
  kind : DeclKind
  deriving Repr, BEq

/-- Custom JSON serialization for Atom with hyphenated field names -/
instance : Lean.ToJson Atom where
  toJson atom := Lean.Json.mkObj [
    ("name", Lean.toJson atom.name),
    ("display-name", Lean.toJson atom.displayName),
    ("dependencies", Lean.toJson atom.dependencies),
    ("code-module", Lean.toJson atom.codeModule),
    ("code-path", Lean.toJson atom.codePath),
    ("code-text", Lean.toJson atom.codeText),
    ("kind", Lean.toJson atom.kind)
  ]

instance : Lean.FromJson Atom where
  fromJson? json := do
    let name ← json.getObjValAs? String "name"
    let displayName ← json.getObjValAs? String "display-name"
    let dependencies ← json.getObjValAs? (Array String) "dependencies"
    let codeModule ← json.getObjValAs? String "code-module"
    let codePath ← json.getObjValAs? String "code-path"
    let codeText ← json.getObjValAs? (Option CodeTextInfo) "code-text"
    let kind ← json.getObjValAs? DeclKind "kind"
    return { name, displayName, dependencies, codeModule, codePath, codeText, kind }

/-- Output format for atoms.json -/
structure AtomsOutput where
  atoms : Array Atom
  deriving Repr

instance : Lean.ToJson AtomsOutput where
  toJson output := Lean.Json.mkObj [
    ("atoms", Lean.toJson output.atoms)
  ]

end ProbeLean
