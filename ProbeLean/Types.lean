/-
  Types for probe-lean output.
  Defines atoms, specs, proofs, stubs, and Schema 4.0 envelope types
  with JSON serialization matching the probe interchange spec.
-/
import Lean.Data.Json
import Lean.PrivateName
import ProbeLean.Version

namespace ProbeLean

-- ============================================================
-- Constants
-- ============================================================

namespace Constants
  def verilibDir : String := ".verilib"
  def probesDir : String := "probes"
  def viewsDir : String := "views"
  def mapsDir : String := "maps"
  def toolName : String := "probe-lean"
  def toolVersion : String := ProbeLean.version
  def schemaVersion : String := "4.0"
  def schemaExtract : String := "probe-lean/extract"
  def schemaView : String := "probe-lean/viewify"
end Constants

-- ============================================================
-- Schema 4.0 envelope types
-- ============================================================

/-- Tool metadata for the Schema 4.0 envelope -/
structure ToolInfo where
  name : String := Constants.toolName
  version : String := Constants.toolVersion
  command : String
  deriving Repr, BEq

instance : Lean.ToJson ToolInfo where
  toJson info := Lean.Json.mkObj [
    ("name", Lean.toJson info.name),
    ("version", Lean.toJson info.version),
    ("command", Lean.toJson info.command)
  ]

instance : Lean.FromJson ToolInfo where
  fromJson? json := do
    let name ← json.getObjValAs? String "name"
    let version ← json.getObjValAs? String "version"
    let command ← json.getObjValAs? String "command"
    return { name, version, command }

/-- Source metadata for the Schema 4.0 envelope.
    `repo` and `commit` are non-optional String (empty when unavailable)
    to conform to the probe repo JSON Schema which declares them required. -/
structure SourceInfo where
  repo : String
  commit : String
  language : String := "lean"
  package : String
  packageVersion : String
  deriving Repr, BEq

instance : Lean.ToJson SourceInfo where
  toJson info :=
    Lean.Json.mkObj [
      ("repo", Lean.toJson info.repo),
      ("commit", Lean.toJson info.commit),
      ("language", Lean.toJson info.language),
      ("package", Lean.toJson info.package),
      ("package-version", Lean.toJson info.packageVersion)
    ]

instance : Lean.FromJson SourceInfo where
  fromJson? json := do
    let repo ← json.getObjValAs? String "repo"
    let commit ← json.getObjValAs? String "commit"
    let language ← json.getObjValAs? String "language" <|> pure "lean"
    let package ← json.getObjValAs? String "package"
    let packageVersion ← json.getObjValAs? String "package-version"
    return { repo, commit, language, package, packageVersion }

/-- Typed envelope wrapper for all Schema 4.0 outputs -/
structure Envelope (α : Type) where
  schema : String
  schemaVersion : String := Constants.schemaVersion
  tool : ToolInfo
  source : SourceInfo
  timestamp : String
  data : α
  deriving Repr

instance [Lean.ToJson α] : Lean.ToJson (Envelope α) where
  toJson env := Lean.Json.mkObj [
    ("schema", Lean.toJson env.schema),
    ("schema-version", Lean.toJson env.schemaVersion),
    ("tool", Lean.toJson env.tool),
    ("source", Lean.toJson env.source),
    ("timestamp", Lean.toJson env.timestamp),
    ("data", Lean.toJson env.data)
  ]

instance [Lean.FromJson α] : Lean.FromJson (Envelope α) where
  fromJson? json := do
    let schema ← json.getObjValAs? String "schema"
    let schemaVersion ← json.getObjValAs? String "schema-version"
    let tool ← json.getObjValAs? ToolInfo "tool"
    let source ← json.getObjValAs? SourceInfo "source"
    let timestamp ← json.getObjValAs? String "timestamp"
    let data ← json.getObjValAs? α "data"
    return { schema, schemaVersion, tool, source, timestamp, data }

-- ============================================================
-- Shared utilities
-- ============================================================

/-- Add probe: prefix to a name -/
def addProbePrefix (name : String) : String :=
  s!"probe:{name}"

/-- `probe:`-prefixed reference for a declaration. Normalises Lean's synthetic
    private name (`_private.<module>.0.Bar.foo` → `Bar.foo`) so emitted references
    match the atom published under the user-facing name. No-op for public names. -/
def probeRef (n : Lean.Name) : String :=
  addProbePrefix (Lean.privateToUserName n).toString

/-- Strip the probe: prefix from a name, or return unchanged if no prefix -/
def stripProbePrefix (name : String) : String :=
  if name.startsWith "probe:" then (name.drop 6).toString else name

-- ============================================================
-- Core types
-- ============================================================

/-- Source location information with line range -/
structure CodeTextInfo where
  linesStart : Nat
  linesEnd : Nat
  deriving Repr, BEq

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
  | «projection»
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
    | .projection => "projection"
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
    | "projection" => return .projection
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
  name : String
  displayName : String
  dependencies : Array String
  typeDependencies : Array String := #[]
  termDependencies : Array String := #[]
  /-- Non-project (external) type dependencies — deps referenced by the result
  type that are not project decls (e.g. Mathlib/VCVio names). Emitted so a
  downstream classifier can reconstruct the full reachability graph, which the
  project-filtered `typeDependencies` omits. -/
  typeDependenciesExternal : Array String := #[]
  /-- Non-project (external) term dependencies — the body's external deps. -/
  termDependenciesExternal : Array String := #[]
  codeModule : String
  codePath : String
  codeText : Option CodeTextInfo
  kind : DeclKind
  language : String := "lean"
  isHidden : Bool := false
  isLeanGenerated : Bool := false
  isAeneasGenerated : Bool := false
  isIgnored : Bool := false
  isRelevant : Bool := true
  isInPackage : Bool := true
  rustSource : Option String := none
  attributes : Array String := #[]
  specs : Array String := #[]
  isPrimarySpec : Bool := false
  primarySpec : Option String := none
  /-- Head constant of the result type, if any (neutral fact). -/
  codomainHead : Option String := none
  /-- Result type is `Sort 0` (a `Prop`). -/
  codomainIsProp : Bool := false
  /-- Final application arg of the result type is `Bool`. -/
  codomainLastArgIsBool : Bool := false
  deriving Repr, BEq, Inhabited

instance : Lean.ToJson Atom where
  toJson atom :=
    let base := [
      ("display-name", Lean.toJson atom.displayName),
      ("dependencies", Lean.toJson atom.dependencies),
      ("type-dependencies", Lean.toJson atom.typeDependencies),
      ("term-dependencies", Lean.toJson atom.termDependencies),
      ("code-module", Lean.toJson atom.codeModule),
      ("code-path", Lean.toJson atom.codePath),
      ("code-text", Lean.toJson atom.codeText),
      ("kind", Lean.toJson atom.kind),
      ("language", Lean.toJson atom.language),
      ("is-hidden", Lean.toJson atom.isHidden),
      ("is-lean-generated", Lean.toJson atom.isLeanGenerated),
      ("is-aeneas-generated", Lean.toJson atom.isAeneasGenerated),
      ("is-ignored", Lean.toJson atom.isIgnored),
      ("is-relevant", Lean.toJson atom.isRelevant),
      ("is-in-package", Lean.toJson atom.isInPackage),
      ("rust-source", Lean.toJson atom.rustSource)
    ]
    let withAttrs := if atom.attributes.isEmpty then base
      else base ++ [("attributes", Lean.toJson atom.attributes)]
    let withSpecs := if atom.specs.isEmpty then withAttrs
      else withAttrs ++ [("specs", Lean.toJson atom.specs)]
    let withPrimary := match atom.primarySpec with
      | some ps => withSpecs ++ [("primary-spec", Lean.toJson ps)]
      | none => withSpecs
    Lean.Json.mkObj withPrimary

instance : Lean.FromJson Atom where
  fromJson? json := do
    let name ← json.getObjValAs? String "name" <|> pure ""
    let displayName ← json.getObjValAs? String "display-name"
    let dependencies ← json.getObjValAs? (Array String) "dependencies"
    let typeDependencies ← json.getObjValAs? (Array String) "type-dependencies" <|> pure #[]
    let termDependencies ← json.getObjValAs? (Array String) "term-dependencies" <|> pure #[]
    let codeModule ← json.getObjValAs? String "code-module"
    let codePath ← json.getObjValAs? String "code-path"
    let codeText ← json.getObjValAs? (Option CodeTextInfo) "code-text"
    let kind ← json.getObjValAs? DeclKind "kind"
    let language ← json.getObjValAs? String "language" <|> pure "lean"
    let isHidden ← json.getObjValAs? Bool "is-hidden" <|> pure false
    let isLeanGenerated ← json.getObjValAs? Bool "is-lean-generated" <|> pure false
    let isAeneasGenerated ← json.getObjValAs? Bool "is-aeneas-generated" <|> pure false
    let isIgnored ← json.getObjValAs? Bool "is-ignored" <|> pure false
    let isRelevant ← json.getObjValAs? Bool "is-relevant" <|> pure true
    let isInPackage ← json.getObjValAs? Bool "is-in-package" <|> pure true
    let rustSource ← json.getObjValAs? (Option String) "rust-source" <|> pure none
    let attributes ← json.getObjValAs? (Array String) "attributes" <|> pure #[]
    let specs ← json.getObjValAs? (Array String) "specs" <|> pure #[]
    let isPrimarySpec ← json.getObjValAs? Bool "is-primary-spec" <|> pure false
    let primarySpec ← json.getObjValAs? (Option String) "primary-spec" <|> pure none
    return { name, displayName, dependencies, typeDependencies, termDependencies, codeModule, codePath, codeText, kind, language, isHidden, isLeanGenerated, isAeneasGenerated, isIgnored, isRelevant, isInPackage, rustSource, attributes, specs, isPrimarySpec, primarySpec }

/-- Output format for atoms - an object keyed by atom name -/
structure AtomsOutput where
  atoms : Array Atom
  deriving Repr

instance : Lean.ToJson AtomsOutput where
  toJson output :=
    let sorted := output.atoms.qsort fun a b => a.name < b.name
    let entries := sorted.map fun atom => (atom.name, Lean.toJson atom)
    Lean.Json.mkObj entries.toList

instance : Lean.FromJson AtomsOutput where
  fromJson? json := do
    let obj ← json.getObj?
    let mut atoms : Array Atom := #[]
    for (key, value) in obj.toArray do
      let parsed : Atom ← Lean.FromJson.fromJson? value
      let withKey : Atom := { parsed with name := key }
      atoms := atoms.push withKey
    return { atoms }

/-- A spec entry for specs output -/
structure SpecEntry where
  specified : Bool
  codePath : String
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
  | success
  | sorries
  | failure
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

/-- A proof entry for proofs output -/
structure ProofEntry where
  verified : Bool
  status : VerifyStatus
  codePath : String
  codeLine : Nat
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
  | trusted
  | transitivelyVerified
  deriving Repr, BEq

instance : Lean.ToJson WebVerificationStatus where
  toJson
    | .verified => "verified"
    | .failed => "failed"
    | .unverified => "unverified"
    | .trusted => "trusted"
    | .transitivelyVerified => "transitively-verified"

instance : Lean.FromJson WebVerificationStatus where
  fromJson? json := do
    let s ← json.getStr?
    match s with
    | "verified" => return .verified
    | "failed" => return .failed
    | "unverified" => return .unverified
    | "trusted" => return .trusted
    | "transitively-verified" => return .transitivelyVerified
    | _ => throw s!"Unknown WebVerificationStatus: {s}"

/-- A unified atom combining all atom fields with verification and specification status -/
structure UnifiedAtom where
  name : String
  displayName : String
  dependencies : Array String
  typeDependencies : Array String := #[]
  termDependencies : Array String := #[]
  /-- Non-project (external) type dependencies — deps referenced by the result
  type that are not project decls (e.g. Mathlib/VCVio names). Emitted so a
  downstream classifier can reconstruct the full reachability graph, which the
  project-filtered `typeDependencies` omits. -/
  typeDependenciesExternal : Array String := #[]
  /-- Non-project (external) term dependencies — the body's external deps. -/
  termDependenciesExternal : Array String := #[]
  codeModule : String
  codePath : String
  codeText : Option CodeTextInfo
  kind : DeclKind
  language : String := "lean"
  isHidden : Bool := false
  isLeanGenerated : Bool := false
  isAeneasGenerated : Bool := false
  isIgnored : Bool := false
  isRelevant : Bool := true
  isInPackage : Bool := true
  rustSource : Option String := none
  attributes : Array String := #[]
  specs : Array String := #[]
  isPrimarySpec : Bool := false
  primarySpec : Option String := none
  verificationStatus : Option WebVerificationStatus
  trustedReason : Option String := none
  /-- Head constant of the result type, if any (neutral fact). -/
  codomainHead : Option String := none
  /-- Result type is `Sort 0` (a `Prop`). -/
  codomainIsProp : Bool := false
  /-- Final application arg of the result type is `Bool`. -/
  codomainLastArgIsBool : Bool := false
  deriving Repr, BEq, Inhabited

instance : Lean.ToJson UnifiedAtom where
  toJson atom :=
    let base := [
      ("display-name", Lean.toJson atom.displayName),
      ("dependencies", Lean.toJson atom.dependencies),
      ("type-dependencies", Lean.toJson atom.typeDependencies),
      ("term-dependencies", Lean.toJson atom.termDependencies),
      ("code-module", Lean.toJson atom.codeModule),
      ("code-path", Lean.toJson atom.codePath),
      ("code-text", Lean.toJson atom.codeText),
      ("kind", Lean.toJson atom.kind),
      ("language", Lean.toJson atom.language),
      ("is-hidden", Lean.toJson atom.isHidden),
      ("is-lean-generated", Lean.toJson atom.isLeanGenerated),
      ("is-aeneas-generated", Lean.toJson atom.isAeneasGenerated),
      ("is-ignored", Lean.toJson atom.isIgnored),
      ("is-relevant", Lean.toJson atom.isRelevant),
      ("is-in-package", Lean.toJson atom.isInPackage),
      ("rust-source", Lean.toJson atom.rustSource)
    ]
    let withExtType := if atom.typeDependenciesExternal.isEmpty then base
      else base ++ [("type-dependencies-external", Lean.toJson atom.typeDependenciesExternal)]
    let withExtTerm := if atom.termDependenciesExternal.isEmpty then withExtType
      else withExtType ++ [("term-dependencies-external", Lean.toJson atom.termDependenciesExternal)]
    let withAttrs := if atom.attributes.isEmpty then withExtTerm
      else withExtTerm ++ [("attributes", Lean.toJson atom.attributes)]
    let withSpecs := if atom.specs.isEmpty then withAttrs
      else withAttrs ++ [("specs", Lean.toJson atom.specs)]
    let withPrimary := match atom.primarySpec with
      | some ps => withSpecs ++ [("primary-spec", Lean.toJson ps)]
      | none => withSpecs
    let withVerification := match atom.verificationStatus with
      | some status => withPrimary ++ [("verification-status", Lean.toJson status)]
      | none => withPrimary
    let withTrustedReason := match atom.trustedReason with
      | some reason => withVerification ++ [("trusted-reason", Lean.toJson reason)]
      | none => withVerification
    let withCodomainHead := match atom.codomainHead with
      | some h => withTrustedReason ++ [("codomain-head", Lean.toJson h)]
      | none => withTrustedReason
    let withCodomain := withCodomainHead ++ [
      ("codomain-is-prop", Lean.toJson atom.codomainIsProp),
      ("codomain-last-arg-is-bool", Lean.toJson atom.codomainLastArgIsBool)
    ]
    Lean.Json.mkObj withCodomain

instance : Lean.FromJson UnifiedAtom where
  fromJson? json := do
    let name ← json.getObjValAs? String "name" <|> pure ""
    let displayName ← json.getObjValAs? String "display-name"
    let dependencies ← json.getObjValAs? (Array String) "dependencies"
    let typeDependencies ← json.getObjValAs? (Array String) "type-dependencies" <|> pure #[]
    let termDependencies ← json.getObjValAs? (Array String) "term-dependencies" <|> pure #[]
    let typeDependenciesExternal ← json.getObjValAs? (Array String) "type-dependencies-external" <|> pure #[]
    let termDependenciesExternal ← json.getObjValAs? (Array String) "term-dependencies-external" <|> pure #[]
    let codeModule ← json.getObjValAs? String "code-module"
    let codePath ← json.getObjValAs? String "code-path"
    let codeText ← json.getObjValAs? (Option CodeTextInfo) "code-text"
    let kind ← json.getObjValAs? DeclKind "kind"
    let language ← json.getObjValAs? String "language" <|> pure "lean"
    let isHidden ← json.getObjValAs? Bool "is-hidden" <|> pure false
    let isLeanGenerated ← json.getObjValAs? Bool "is-lean-generated" <|> pure false
    let isAeneasGenerated ← json.getObjValAs? Bool "is-aeneas-generated" <|> pure false
    let isIgnored ← json.getObjValAs? Bool "is-ignored" <|> pure false
    let isRelevant ← json.getObjValAs? Bool "is-relevant" <|> pure true
    let isInPackage ← json.getObjValAs? Bool "is-in-package" <|> pure true
    let rustSource ← json.getObjValAs? (Option String) "rust-source" <|> pure none
    let attributes ← json.getObjValAs? (Array String) "attributes" <|> pure #[]
    let specs ← json.getObjValAs? (Array String) "specs" <|> pure #[]
    let isPrimarySpec ← json.getObjValAs? Bool "is-primary-spec" <|> pure false
    let primarySpec ← json.getObjValAs? (Option String) "primary-spec" <|> pure none
    let verificationStatus ← json.getObjValAs? (Option WebVerificationStatus) "verification-status" <|> pure none
    let trustedReason ← json.getObjValAs? (Option String) "trusted-reason" <|> pure none
    let codomainHead ← json.getObjValAs? (Option String) "codomain-head" <|> pure none
    let codomainIsProp ← json.getObjValAs? Bool "codomain-is-prop" <|> pure false
    let codomainLastArgIsBool ← json.getObjValAs? Bool "codomain-last-arg-is-bool" <|> pure false
    return { name, displayName, dependencies, typeDependencies, termDependencies, typeDependenciesExternal, termDependenciesExternal, codeModule, codePath, codeText, kind, language, isHidden, isLeanGenerated, isAeneasGenerated, isIgnored, isRelevant, isInPackage, rustSource, attributes, specs, isPrimarySpec, primarySpec, verificationStatus, trustedReason, codomainHead, codomainIsProp, codomainLastArgIsBool }

/-- Output format for unified atoms - an object keyed by atom name -/
structure UnifiedAtomsOutput where
  atoms : Array UnifiedAtom
  deriving Repr

instance : Lean.ToJson UnifiedAtomsOutput where
  toJson output :=
    let sorted := output.atoms.qsort fun a b => a.name < b.name
    let entries := sorted.map fun atom => (atom.name, Lean.toJson atom)
    Lean.Json.mkObj entries.toList

instance : Lean.FromJson UnifiedAtomsOutput where
  fromJson? json := do
    let obj ← json.getObj?
    let mut atoms : Array UnifiedAtom := #[]
    for (key, value) in obj.toArray do
      let parsed : UnifiedAtom ← Lean.FromJson.fromJson? value
      let withKey : UnifiedAtom := { parsed with name := key }
      atoms := atoms.push withKey
    return { atoms }

/-- A stub/molecule entry for view output -/
structure StubEntry where
  codePath : Option String
  codeLines : Option String
  codeName : String
  rustPath : String
  rustLines : CodeTextInfo
  rustName : String
  specPath : Option String
  specLines : Option String
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

/-- Output format for specs - an object keyed by atom name -/
structure SpecsOutput where
  entries : Array (String × SpecEntry)
  deriving Repr

instance : Lean.ToJson SpecsOutput where
  toJson output :=
    let pairs := output.entries.map fun (name, entry) => (name, Lean.toJson entry)
    Lean.Json.mkObj pairs.toList

instance : Lean.FromJson SpecsOutput where
  fromJson? json := do
    let obj ← json.getObj?
    let mut entries : Array (String × SpecEntry) := #[]
    for (name, value) in obj.toArray do
      let entry ← Lean.FromJson.fromJson? value
      entries := entries.push (name, entry)
    return { entries }

/-- Output format for proofs - an object keyed by atom name -/
structure ProofsOutput where
  entries : Array (String × ProofEntry)
  deriving Repr

instance : Lean.ToJson ProofsOutput where
  toJson output :=
    let pairs := output.entries.map fun (name, entry) => (name, Lean.toJson entry)
    Lean.Json.mkObj pairs.toList

instance : Lean.FromJson ProofsOutput where
  fromJson? json := do
    let obj ← json.getObj?
    let mut entries : Array (String × ProofEntry) := #[]
    for (name, value) in obj.toArray do
      let entry ← Lean.FromJson.fromJson? value
      entries := entries.push (name, entry)
    return { entries }

/-- Output format for molecules (view) - an object keyed by stub key -/
structure MoleculesOutput where
  entries : Array (String × StubEntry)
  deriving Repr

instance : Lean.ToJson MoleculesOutput where
  toJson output :=
    let pairs := output.entries.map fun (key, entry) => (key, Lean.toJson entry)
    Lean.Json.mkObj pairs.toList

instance : Lean.FromJson MoleculesOutput where
  fromJson? json := do
    let obj ← json.getObj?
    let mut entries : Array (String × StubEntry) := #[]
    for (key, value) in obj.toArray do
      let entry ← Lean.FromJson.fromJson? value
      entries := entries.push (key, entry)
    return { entries }

end ProbeLean
