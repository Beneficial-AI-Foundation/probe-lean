/-
  The `@[externally_verified]` tag set, read from the environment.

  Rule 2 of the trusted base used to be decided by scanning the source text of a
  declaration's header for `@[externally_verified]`. Reconstructing the tag set from
  text kept producing false-trust paths (a window off by one line; tags inside
  comments and strings; range-sharing companions, derived instances and generated
  helpers; string content inside interpolations lexed as code; two commands on one
  line). The set is not in the text, it is in the olean: `registerTagAttribute name …
  (ref := decl_name%)` creates a persistent environment extension whose *name* is
  `ref` (the `initialize` constant's own name) and whose exported entries are exactly
  the tagged `Name`s, and stores them in `ModuleData.entries` under that name.

  probe-lean cannot use the `TagAttribute` handle of a target that registers the tag
  itself (curve25519-dalek-lean-verify does; its extension is `externallyVerifiedAttr`,
  probe-lean's is `ProbeLean.externallyVerifiedAttr`, and imported entries are keyed
  by extension name), and running the target's initializers would execute foreign code
  and change the import mode of the whole run. So the set is read statically: the
  `TagAttribute`-typed constant behind an extension name is found in the environment,
  its `[init]` function's body is the `registerTagAttribute` application, and the
  attribute name and `ref` are read off that application's literal arguments. Nothing
  is executed and no source is read.

  What this honours that the scan did not, by design: an after-the-fact
  `attribute [externally_verified] foo` command, and a tag on a constant without a
  declaration range (`impl_def`, `addDecl`). A tag is a tag, whatever syntax attached
  it (spec decision 3, amended 2026-09-17).

  Limits, all of them under-trust (a tag the reader does not see is a tag that is
  not honoured, never the reverse): a tag attribute registered with an explicit `ref`
  that is not the constant's own name; one created through a wrapper rather than a
  literal `registerTagAttribute` call in the `initialize` body; a `ParametricAttribute`
  or hand-rolled storage. `Taint.tagAudit` reports every declaration whose header
  shows the tag while the set does not contain it, so such a target is loud, not
  silently untrusted.
-/
import Lean
import ProbeLean.Analysis

namespace ProbeLean

open Lean

/-- A `Nat` literal as the elaborator emits it: `.lit (.natVal n)` or
    `OfNat.ofNat _ (lit n) _`. -/
private def natLiteral? (e : Expr) : Option Nat :=
  match e.consumeMData with
  | .lit (.natVal n) => some n
  | e =>
    match e.getAppFn, e.getAppArgs with
    | .const ``OfNat.ofNat _, #[_, .lit (.natVal n), _] => some n
    | _, _ => none

/-- A `String` literal. -/
private def strLiteral? (e : Expr) : Option String :=
  match e.consumeMData with
  | .lit (.strVal s) => some s
  | _ => none

/-- The `Name.mkStr1` … `Name.mkStr8` constructors the name quotation uses, by arity. -/
private def mkStrN : Array Name :=
  #[``Name.mkStr1, ``Name.mkStr2, ``Name.mkStr3, ``Name.mkStr4,
    ``Name.mkStr5, ``Name.mkStr6, ``Name.mkStr7, ``Name.mkStr8]

/-- A `Name` literal as the elaborator emits it for `` `foo.bar `` or `decl_name%`:
    `Name.anonymous`, `Name.mkStr1 … mkStr8` over string literals, `Name.mkSimple`, or
    nested `Name.str`/`Name.mkStr` and `Name.num`/`Name.mkNum` applications. Anything
    else — a computed name — is `none`. -/
partial def nameLiteral? (e : Expr) : Option Name :=
  let e := e.consumeMData
  match e.getAppFn with
  | .const ``Name.anonymous _ => if e.getAppNumArgs == 0 then some .anonymous else none
  | .const fn _ =>
    let args := e.getAppArgs
    if (fn == ``Name.str || fn == ``Name.mkStr) && args.size == 2 then
      match nameLiteral? args[0]!, strLiteral? args[1]! with
      | some p, some s => some (.str p s)
      | _, _ => none
    else if (fn == ``Name.num || fn == ``Name.mkNum) && args.size == 2 then
      match nameLiteral? args[0]!, natLiteral? args[1]! with
      | some p, some n => some (.num p n)
      | _, _ => none
    else if fn == ``Name.mkSimple && args.size == 1 then
      (strLiteral? args[0]!).map Name.mkSimple
    else match mkStrN.idxOf? fn with
      | some k =>
        if args.size == k + 1 then
          args.foldl (init := some .anonymous) fun acc a =>
            match acc, strLiteral? a with
            | some p, some s => some (.str p s)
            | _, _ => none
        else none
      | none => none
  | _ => none

/-- `(attribute name, extension name)` when `e` is a `registerTagAttribute` application
    whose `name` and `ref` arguments are name literals. The elaborator fills every
    default argument, so the application has at least the four leading explicit ones
    (`name descr validate ref`) whatever the source wrote. -/
def tagAttributeRegistration? (e : Expr) : Option (Name × Name) :=
  let e := e.consumeMData
  match e.getAppFn with
  | .const ``registerTagAttribute _ =>
    let args := e.getAppArgs
    if args.size ≥ 4 then do
      let attr ← nameLiteral? args[0]!
      let ref ← nameLiteral? args[3]!
      pure (attr, ref)
    else none
  | _ => none

/-- The registration behind the constant `x`, when `x` is an
    `initialize x : TagAttribute ← registerTagAttribute …`: its type is `TagAttribute`,
    it has an `[init]` function, and that function's body is the application. -/
def tagAttributeOf? (env : Environment) (x : Name) : Option (Name × Name) := do
  let ci ← env.find? x
  guard (ci.type.consumeMData == mkConst ``TagAttribute)
  let initFn ← getInitFnNameFor? env x
  let .defnInfo v ← env.find? initFn | none
  tagAttributeRegistration? v.value

/-- The entries a `TagAttribute` exports are its tagged names: `registerTagAttribute`
    builds a `PersistentEnvExtension Name Name NameSet` whose `exportEntriesFn`
    returns an `Array Name`, stored in the olean as opaque `EnvExtensionEntry`s. The
    cast is justified only after `tagAttributeOf?` has confirmed that the extension's
    name is a `TagAttribute` constant registered under that very name — the caller's
    responsibility (`externallyVerifiedTagSet`). -/
unsafe def tagEntriesUnsafe (es : Array EnvExtensionEntry) : Array Name := unsafeCast es

@[implemented_by tagEntriesUnsafe]
opaque tagEntries (es : Array EnvExtensionEntry) : Array Name

/-- Whether `extName` names an extension that stores an `externally_verified` tag
    set: the constant of that name is a `TagAttribute` registered by
    `registerTagAttribute `externally_verified … (ref := extName)`. -/
def isExternallyVerifiedExt (env : Environment) (extName : Name) : Bool :=
  match tagAttributeOf? env extName with
  | some (attr, ref) => attr == `externally_verified && ref == extName
  | none => false

/-- What `externallyVerifiedTagSet` found. -/
structure TagSet where
  /-- Every project constant tagged `externally_verified`, from every registration
      of that attribute the project modules carry entries for. -/
  tagged : Std.HashSet Name := {}
  /-- The extension names the set was read from, sorted. Empty when no project
      module carries an `externally_verified` entry — a target that does not use the
      tag (SPQR), or one whose registration the reader does not understand (then
      `Taint.tagAudit` says so per declaration). -/
  extensions : Array Name := #[]

/-- The `externally_verified` tag set over the project modules (`pFilter`), read from
    `ModuleData.entries`. Only extensions that have entries in a project module are
    examined, and each extension name is classified once, so the cost is a handful of
    `env.find?` calls per run. A tag can only sit in the module that declares the
    constant (`throwAttrDeclInImportedModule`), so project modules are the whole
    story for project constants. -/
def externallyVerifiedTagSet (env : Environment) (pFilter : ProjectFilter) : TagSet := Id.run do
  let mods := env.header.moduleData
  let mut known : Std.HashMap Name Bool := {}
  let mut exts : Array Name := #[]
  let mut tagged : Std.HashSet Name := {}
  for i in [:mods.size] do
    if !pFilter.moduleIdxs.contains i then continue
    for (extName, es) in mods[i]!.entries do
      if es.isEmpty then continue
      let isEv ← match known[extName]? with
        | some b => pure b
        | none =>
          let b := isExternallyVerifiedExt env extName
          known := known.insert extName b
          if b then exts := exts.push extName
          pure b
      if isEv then
        for n in tagEntries es do
          tagged := tagged.insert n
  return { tagged, extensions := exts.qsort fun a b => a.toString < b.toString }

end ProbeLean
