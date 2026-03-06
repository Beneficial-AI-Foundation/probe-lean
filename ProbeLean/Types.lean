/-
  Types for probe-lean output.
  Defines atoms, specs, proofs, stubs, and Schema 2.0 envelope types
  with JSON serialization matching the probe interchange spec.
-/
import Lean.Data.Json

namespace ProbeLean

-- ============================================================
-- Schema 2.0 envelope types
-- ============================================================

/-- Tool metadata for the Schema 2.0 envelope -/
structure ToolInfo where
  name : String
  version : String
  command : String
  deriving Repr, BEq

instance : Lean.ToJson ToolInfo where
  toJson info := Lean.Json.mkObj [
    ("name", Lean.toJson info.name),
    ("version", Lean.toJson info.version),
    ("command", Lean.toJson info.command)
  ]

/-- Source metadata for the Schema 2.0 envelope -/
structure SourceInfo where
  repo : String
  commit : String
  language : String
  package : String
  packageVersion : String
  deriving Repr, BEq

instance : Lean.ToJson SourceInfo where
  toJson info := Lean.Json.mkObj [
    ("repo", Lean.toJson info.repo),
    ("commit", Lean.toJson info.commit),
    ("language", Lean.toJson info.language),
    ("package", Lean.toJson info.package),
    ("package-version", Lean.toJson info.packageVersion)
  ]

-- ============================================================
-- Core types
-- ============================================================

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

instance : Inhabited DeclKind where
  default := .def

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
  /-- Source language of this atom -/
  language : String := "lean"
  /-- Whether this atom is hidden (from config.json's user/is-hidden list) -/
  isHidden : Bool := false
  /-- Whether this atom is an extraction artifact (suffix matches config.json's user/extraction-artifact-suffixes) -/
  isExtractionArtifact : Bool := false
  /-- Whether this atom is ignored (from config.json's user/is-ignored list) -/
  isIgnored : Bool := false
  /-- Whether this atom is relevant (from crate source, not stdlib/external deps) -/
  isRelevant : Bool := true
  /-- Rust source path from Aeneas docstring (e.g., "curve25519-dalek/src/field.rs") -/
  rustSource : Option String := none
  deriving Repr, BEq, Inhabited

/-- Custom JSON serialization for Atom with hyphenated field names.
    Note: The "name" field is not included here as it becomes the key in atoms.json -/
instance : Lean.ToJson Atom where
  toJson atom := Lean.Json.mkObj [
    ("display-name", Lean.toJson atom.displayName),
    ("dependencies", Lean.toJson atom.dependencies),
    ("code-module", Lean.toJson atom.codeModule),
    ("code-path", Lean.toJson atom.codePath),
    ("code-text", Lean.toJson atom.codeText),
    ("kind", Lean.toJson atom.kind),
    ("language", Lean.toJson atom.language),
    ("is-hidden", Lean.toJson atom.isHidden),
    ("is-extraction-artifact", Lean.toJson atom.isExtractionArtifact),
    ("is-ignored", Lean.toJson atom.isIgnored),
    ("is-relevant", Lean.toJson atom.isRelevant),
    ("rust-source", Lean.toJson atom.rustSource)
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
    let language ← json.getObjValAs? String "language" <|> pure "lean"
    let isHidden ← json.getObjValAs? Bool "is-hidden" <|> pure false
    let isExtractionArtifact ← json.getObjValAs? Bool "is-extraction-artifact" <|> pure false
    let isIgnored ← json.getObjValAs? Bool "is-ignored" <|> pure false
    let isRelevant ← json.getObjValAs? Bool "is-relevant" <|> pure true
    let rustSource ← json.getObjValAs? (Option String) "rust-source" <|> pure none
    return { name, displayName, dependencies, codeModule, codePath, codeText, kind, language, isHidden, isExtractionArtifact, isIgnored, isRelevant, rustSource }

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
    let obj ← json.getObj?
    let mut atoms : Array Atom := #[]
    for (name, value) in obj.toArray do
      let displayName ← value.getObjValAs? String "display-name"
      let dependencies ← value.getObjValAs? (Array String) "dependencies"
      let codeModule ← value.getObjValAs? String "code-module"
      let codePath ← value.getObjValAs? String "code-path"
      let codeText ← value.getObjValAs? (Option CodeTextInfo) "code-text"
      let kind ← value.getObjValAs? DeclKind "kind"
      let language ← value.getObjValAs? String "language" <|> pure "lean"
      let isHidden ← value.getObjValAs? Bool "is-hidden" <|> pure false
      let isExtractionArtifact ← value.getObjValAs? Bool "is-extraction-artifact" <|> pure false
      let isIgnored ← value.getObjValAs? Bool "is-ignored" <|> pure false
      let isRelevant ← value.getObjValAs? Bool "is-relevant" <|> pure true
      atoms := atoms.push { name, displayName, dependencies, codeModule, codePath, codeText, kind, language, isHidden, isExtractionArtifact, isIgnored, isRelevant }
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
  language : String := "lean"
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
      ("kind", Lean.toJson atom.kind),
      ("language", Lean.toJson atom.language)
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
  /-- Code (Lean) file path -/
  codePath : Option String
  /-- Code (Lean) line info -/
  codeLines : Option String
  /-- Code (Lean) name with probe: prefix -/
  codeName : String
  /-- Rust source file path -/
  rustPath : String
  /-- Rust line range -/
  rustLines : CodeTextInfo
  /-- Rust function name -/
  rustName : String
  /-- Spec file path or null -/
  specPath : Option String
  /-- Spec line info (placeholder, always null) -/
  specLines : Option String
  /-- Spec name or null -/
  specName : Option String
  deriving Repr, BEq

instance : Lean.ToJson StubEntry where
  toJson entry := Lean.Json.mkObj [
    ("code-path", Lean.toJson entry.codePath),
    ("code-lines", Lean.toJson entry.codeLines),
    ("code-name", Lean.toJson entry.codeName),
    ("rust-path", Lean.toJson entry.rustPath),
    ("rust-lines", Lean.toJson entry.rustLines),
    ("rust-name", Lean.toJson entry.rustName),
    ("spec-path", Lean.toJson entry.specPath),
    ("spec-lines", Lean.toJson entry.specLines),
    ("spec-name", Lean.toJson entry.specName)
  ]

instance : Lean.FromJson StubEntry where
  fromJson? json := do
    let codePath ← json.getObjValAs? (Option String) "code-path"
    let codeLines ← json.getObjValAs? (Option String) "code-lines"
    let codeName ← json.getObjValAs? String "code-name"
    let rustPath ← json.getObjValAs? String "rust-path"
    let rustLines ← json.getObjValAs? CodeTextInfo "rust-lines"
    let rustName ← json.getObjValAs? String "rust-name"
    let specPath ← json.getObjValAs? (Option String) "spec-path"
    let specLines ← json.getObjValAs? (Option String) "spec-lines"
    let specName ← json.getObjValAs? (Option String) "spec-name"
    return { codePath, codeLines, codeName, rustPath, rustLines, rustName, specPath, specLines, specName }

-- ============================================================
-- Typed output wrappers (keyed-dict serialization)
-- ============================================================

/-- Output format for specs.json - an object keyed by atom name -/
structure SpecsOutput where
  entries : Array (String × SpecEntry)
  deriving Repr

instance : Lean.ToJson SpecsOutput where
  toJson output :=
    let pairs := output.entries.map fun (name, entry) => (name, Lean.toJson entry)
    Lean.Json.mkObj pairs.toList

/-- Output format for proofs.json - an object keyed by atom name -/
structure ProofsOutput where
  entries : Array (String × ProofEntry)
  deriving Repr

instance : Lean.ToJson ProofsOutput where
  toJson output :=
    let pairs := output.entries.map fun (name, entry) => (name, Lean.toJson entry)
    Lean.Json.mkObj pairs.toList

/-- Output format for stubs.json - an object keyed by stub key -/
structure StubsOutput where
  entries : Array (String × StubEntry)
  deriving Repr

instance : Lean.ToJson StubsOutput where
  toJson output :=
    let pairs := output.entries.map fun (key, entry) => (key, Lean.toJson entry)
    Lean.Json.mkObj pairs.toList

end ProbeLean
