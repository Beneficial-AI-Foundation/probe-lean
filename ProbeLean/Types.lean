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

/-- Custom JSON serialization for Atom with hyphenated field names.
    Note: The "name" field is not included here as it becomes the key in atoms.json -/
instance : Lean.ToJson Atom where
  toJson atom := Lean.Json.mkObj [
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

/-- Output format for atoms.json - an object keyed by atom name -/
structure AtomsOutput where
  atoms : Array Atom
  deriving Repr

/-- Serialize atoms as an object with atom names as keys -/
instance : Lean.ToJson AtomsOutput where
  toJson output :=
    let entries := output.atoms.map fun atom => (atom.name, Lean.toJson atom)
    Lean.Json.mkObj entries.toList

instance : Lean.FromJson AtomsOutput where
  fromJson? json := do
    -- Parse as object where keys are atom names
    let obj ← json.getObj?
    let mut atoms : Array Atom := #[]
    for (name, value) in obj.toArray do
      let displayName ← value.getObjValAs? String "display-name"
      let dependencies ← value.getObjValAs? (Array String) "dependencies"
      let codeModule ← value.getObjValAs? String "code-module"
      let codePath ← value.getObjValAs? String "code-path"
      let codeText ← value.getObjValAs? (Option CodeTextInfo) "code-text"
      let kind ← value.getObjValAs? DeclKind "kind"
      atoms := atoms.push { name, displayName, dependencies, codeModule, codePath, codeText, kind }
    return { atoms }

/-- A spec entry for specs.json output -/
structure SpecEntry where
  /-- Whether the declaration has a complete specification -/
  specified : Bool
  /-- File path to source -/
  codePath : String
  /-- Source location info -/
  specText : Option CodeTextInfo
  deriving Repr, BEq

instance : Lean.ToJson SpecEntry where
  toJson entry := Lean.Json.mkObj [
    ("specified", Lean.toJson entry.specified),
    ("code-path", Lean.toJson entry.codePath),
    ("spec-text", Lean.toJson entry.specText)
  ]

instance : Lean.FromJson SpecEntry where
  fromJson? json := do
    let specified ← json.getObjValAs? Bool "specified"
    let codePath ← json.getObjValAs? String "code-path"
    let specText ← json.getObjValAs? (Option CodeTextInfo) "spec-text"
    return { specified, codePath, specText }

/-- Information about a sorry occurrence -/
structure SorryInfo where
  line : Nat
  message : String
  deriving Repr, BEq

instance : Lean.ToJson SorryInfo where
  toJson info := Lean.Json.mkObj [
    ("line", Lean.toJson info.line),
    ("message", Lean.toJson info.message)
  ]

instance : Lean.FromJson SorryInfo where
  fromJson? json := do
    let line ← json.getObjValAs? Nat "line"
    let message ← json.getObjValAs? String "message"
    return { line, message }

/-- Verification status -/
inductive VerifyStatus where
  | success   -- Proof is complete, no sorry
  | sorries   -- Proof contains sorry
  | failure   -- Compilation/type error
  deriving Repr, BEq

instance : Lean.ToJson VerifyStatus where
  toJson
    | .success => "success"
    | .sorries => "sorries"
    | .failure => "failure"

instance : Lean.FromJson VerifyStatus where
  fromJson? json := do
    let s ← json.getStr?
    match s with
    | "success" => return .success
    | "sorries" => return .sorries
    | "failure" => return .failure
    | _ => throw s!"Unknown VerifyStatus: {s}"

/-- A proof entry for proofs.json output -/
structure ProofEntry where
  /-- Whether the declaration is verified (no sorries) -/
  verified : Bool
  /-- Verification status -/
  status : VerifyStatus
  /-- File path to source -/
  codePath : String
  /-- Line number of declaration -/
  codeLine : Nat
  /-- List of sorries found (if any) -/
  sorries : Array SorryInfo
  deriving Repr, BEq

instance : Lean.ToJson ProofEntry where
  toJson entry :=
    let base := [
      ("verified", Lean.toJson entry.verified),
      ("status", Lean.toJson entry.status),
      ("code-path", Lean.toJson entry.codePath),
      ("code-line", Lean.toJson entry.codeLine)
    ]
    let withSorries := if entry.sorries.isEmpty then base
      else base ++ [("sorries", Lean.toJson entry.sorries)]
    Lean.Json.mkObj withSorries

instance : Lean.FromJson ProofEntry where
  fromJson? json := do
    let verified ← json.getObjValAs? Bool "verified"
    let status ← json.getObjValAs? VerifyStatus "status"
    let codePath ← json.getObjValAs? String "code-path"
    let codeLine ← json.getObjValAs? Nat "code-line"
    let sorries ← json.getObjValAs? (Array SorryInfo) "sorries" <|> pure #[]
    return { verified, status, codePath, codeLine, sorries }

/-- Verification status as consumed by the web frontend -/
inductive WebVerificationStatus where
  | verified
  | failed
  | unverified
  deriving Repr, BEq

instance : Lean.ToJson WebVerificationStatus where
  toJson
    | .verified => "verified"
    | .failed => "failed"
    | .unverified => "unverified"

/-- An enriched atom combining declaration info with verification and specification status -/
structure EnrichedAtom where
  name : String
  displayName : String
  dependencies : Array String
  codeModule : String
  codePath : String
  codeText : Option CodeTextInfo
  kind : DeclKind
  verificationStatus : Option WebVerificationStatus
  specified : Option Bool
  deriving Repr, BEq

instance : Lean.ToJson EnrichedAtom where
  toJson atom :=
    let base := [
      ("display-name", Lean.toJson atom.displayName),
      ("dependencies", Lean.toJson atom.dependencies),
      ("code-module", Lean.toJson atom.codeModule),
      ("code-path", Lean.toJson atom.codePath),
      ("code-text", Lean.toJson atom.codeText),
      ("kind", Lean.toJson atom.kind)
    ]
    let withVerification := match atom.verificationStatus with
      | some status => base ++ [("verification-status", Lean.toJson status)]
      | none => base
    let withSpecified := match atom.specified with
      | some spec => withVerification ++ [("specified", Lean.toJson spec)]
      | none => withVerification
    Lean.Json.mkObj withSpecified

/-- Output format for enriched atoms - an object keyed by atom name -/
structure EnrichedAtomsOutput where
  atoms : Array EnrichedAtom
  deriving Repr

instance : Lean.ToJson EnrichedAtomsOutput where
  toJson output :=
    let entries := output.atoms.map fun atom => (atom.name, Lean.toJson atom)
    Lean.Json.mkObj entries.toList

/-- A stub entry for stubs.json output -/
structure StubEntry where
  /-- Lean file path (placeholder, always null) -/
  leanPath : Option String
  /-- Lean line info (placeholder, always null) -/
  leanLines : Option String
  /-- Lean name with probe: prefix -/
  leanName : String
  /-- Rust source file path -/
  rustPath : String
  /-- Rust line range -/
  rustLines : CodeTextInfo
  /-- Rust function name -/
  rustName : String
  /-- Spec file path or null -/
  codePath : Option String
  /-- Code line info (placeholder, always null) -/
  codeLines : Option String
  /-- Spec name or null -/
  codeName : Option String
  deriving Repr, BEq

instance : Lean.ToJson StubEntry where
  toJson entry := Lean.Json.mkObj [
    ("lean-path", Lean.toJson entry.leanPath),
    ("lean-lines", Lean.toJson entry.leanLines),
    ("lean-name", Lean.toJson entry.leanName),
    ("rust-path", Lean.toJson entry.rustPath),
    ("rust-lines", Lean.toJson entry.rustLines),
    ("rust-name", Lean.toJson entry.rustName),
    ("code-path", Lean.toJson entry.codePath),
    ("code-lines", Lean.toJson entry.codeLines),
    ("code-name", Lean.toJson entry.codeName)
  ]

instance : Lean.FromJson StubEntry where
  fromJson? json := do
    let leanPath ← json.getObjValAs? (Option String) "lean-path"
    let leanLines ← json.getObjValAs? (Option String) "lean-lines"
    let leanName ← json.getObjValAs? String "lean-name"
    let rustPath ← json.getObjValAs? String "rust-path"
    let rustLines ← json.getObjValAs? CodeTextInfo "rust-lines"
    let rustName ← json.getObjValAs? String "rust-name"
    let codePath ← json.getObjValAs? (Option String) "code-path"
    let codeLines ← json.getObjValAs? (Option String) "code-lines"
    let codeName ← json.getObjValAs? (Option String) "code-name"
    return { leanPath, leanLines, leanName, rustPath, rustLines, rustName, codePath, codeLines, codeName }

end ProbeLean
