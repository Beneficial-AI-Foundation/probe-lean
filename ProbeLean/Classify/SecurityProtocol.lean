/-
  Pure security-protocol classifier.

  `classify : Array DeclInfo → Array (Name × Classification) × Array String`
  assigns each project declaration a category (scheme / construction /
  correctness / security / ambiguous) and resolves its hierarchy links, using
  the facts on `DeclInfo` (kind, codomain shape/head, class tags, typed deps)
  and the VCVio catalogue. Pure ⇒ unit-testable on hand-built `DeclInfo`.

  Stages run in dependency order (each uses what the previous established):
    1. schemes        — @[scheme_def] | *Scheme/*Alg naming (+ kind/algebra guard)
    2. constructions  — return-type head is a scheme | @[construction_def]
    3. property defs  — attr/naming classify & PROMOTE to anchors, then a
                        type-reach fixed point (order-independent)
    4. theorems       — attr | bounded BFS walk to nearest anchor | naming

  A genuine equal-depth correctness/security tie, or conflicting `@[…_spec]`
  tags, yields `ambiguous` (links still resolved). See
  docs/classification-security-protocol.md.
-/
import ProbeLean.Types
import ProbeLean.Analysis
import ProbeLean.Classify.Catalogue

namespace ProbeLean.Classify

open Lean ProbeLean

/-- Max reachability-walk depth (cycle/visited-guarded). -/
def maxWalkDepth : Nat := 16

-- ============================================================
-- Signal predicates (pure, per-declaration)
-- ============================================================

private def lower (s : String) : String := s.map Char.toLower

private def hasTag (d : DeclInfo) (t : String) : Bool := d.classAttributes.contains t

private def isStructureKind (d : DeclInfo) : Bool :=
  match d.kind with | .structure | .class => true | _ => false

private def isTheorem (d : DeclInfo) : Bool :=
  match d.kind with | .theorem => true | _ => false

/-- Kinds that can realise a scheme (a *construction*): a plain def, an abbrev,
or an `instance` of a scheme class. -/
private def isConstructionKind (d : DeclInfo) : Bool :=
  match d.kind with | .def | .abbrev | .instance => true | _ => false

/-- Kinds that can carry a correctness/security property: theorems and defs.
Attributes are honoured on these **regardless of codomain shape**, so a
transformer-stacked game (`StateT σ ProbComp Bool`, shape `other`) tagged
`@[security_spec]` is still classified. -/
private def isPropertyTaggable (d : DeclInfo) : Bool :=
  match d.kind with | .theorem | .def | .abbrev => true | _ => false

/-- A declaration whose codomain *looks* like a property: a theorem, or a `def`
whose codomain is a predicate / game / advantage. The **naming** signal is gated
on this (it is heuristic); **attributes** are not (see `isPropertyTaggable`). -/
private def isPropertyShaped (d : DeclInfo) : Bool :=
  isTheorem d
    || d.codomainShape == .prop || d.codomainShape == .game || d.codomainShape == .advantage

/-- A non-theorem property *definition* eligible for stage 3: a def/abbrev that
is either property-shaped or carries an explicit correctness/security tag. -/
private def isPropertyDef (d : DeclInfo) : Bool :=
  !isTheorem d && isPropertyTaggable d
    && (isPropertyShaped d || hasTag d "correctness_spec" || hasTag d "security_spec")

private def schemeByNaming (d : DeclInfo) : Bool :=
  isStructureKind d
    && (d.displayName.endsWith "Scheme" || d.displayName.endsWith "Alg")
    && !Catalogue.mathlibAlgebraGuard.any (fun g => g.toString == d.displayName)

private def correctnessByNaming (d : DeclInfo) : Bool :=
  isPropertyShaped d
    && (containsSubstring (lower d.displayName) "correct"
        || containsSubstring (lower d.displayName) "complete")

private def securityByNaming (d : DeclInfo) : Bool :=
  isPropertyShaped d
    && (containsSubstring (lower d.displayName) "secur"
        || containsSubstring (lower d.displayName) "advantage"
        || d.displayName.endsWith "Adv")

-- ============================================================
-- Classifier state
-- ============================================================

/-- Working state threaded through the stages. Small project-local sets are
arrays (a few entries each); `anchors` also seeds the catalogued VCVio anchors. -/
structure St where
  result : Array (Name × Classification) := #[]
  schemes : Array Name := #[]
  constructions : Array Name := #[]
  anchors : Array (Name × SecurityProtocolCategory × ClassVia) := #[]
  diags : Array String := #[]

namespace St

def isClassified (st : St) (n : Name) : Bool := st.result.any (·.1 == n)

def record (st : St) (n : Name) (c : Classification) : St :=
  { st with result := st.result.push (n, c) }

def addScheme (st : St) (n : Name) : St := { st with schemes := st.schemes.push n }
def addConstruction (st : St) (n : Name) : St := { st with constructions := st.constructions.push n }

def promote (st : St) (n : Name) (cat : SecurityProtocolCategory) (v : ClassVia) : St :=
  { st with anchors := st.anchors.push (n, cat, v) }

def diag (st : St) (msg : String) : St := { st with diags := st.diags.push msg }

def isScheme (st : St) (n : Name) : Bool := st.schemes.contains n
def isConstruction (st : St) (n : Name) : Bool := st.constructions.contains n

/-- Look up a classified atom's category (for link resolution). -/
def categoryOf (st : St) (n : Name) : Option SecurityProtocolCategory :=
  (st.result.find? (·.1 == n)).map (·.2.category)

end St

/-- Seed the anchor set with the catalogued VCVio anchors (`via: type`). -/
private def seedAnchors : Array (Name × SecurityProtocolCategory × ClassVia) :=
  Catalogue.correctnessAnchors.map (fun n => (n, SecurityProtocolCategory.correctness, ClassVia.type))
    ++ Catalogue.securityAnchors.map (fun n => (n, SecurityProtocolCategory.security, ClassVia.type))

-- ============================================================
-- Conflict detection
-- ============================================================

/-- Both correctness and security tags ⇒ an axis conflict (→ ambiguous). -/
private def hasAxisConflict (d : DeclInfo) : Bool :=
  hasTag d "correctness_spec" && hasTag d "security_spec"

/-- A class tag on an incompatible kind (e.g. `@[scheme_def]` on a theorem):
the tag is ignored and a diagnostic is emitted; the decl falls through to other
signals. Returns a diagnostic message when such a misuse is present. -/
private def kindTagMisuse (d : DeclInfo) : Option String :=
  if hasTag d "scheme_def" && !isStructureKind d then
    some s!"@[scheme_def] on non-structure '{d.name}' ignored"
  else if hasTag d "construction_def" && !isConstructionKind d then
    some s!"@[construction_def] on non-def '{d.name}' ignored"
  else if (hasTag d "correctness_spec" || hasTag d "security_spec") && !isPropertyTaggable d then
    some s!"@[…_spec] on non-property '{d.name}' ignored"
  else none

-- ============================================================
-- Bounded reachability walk (stages 3B and 4)
-- ============================================================

/-- A theorem inherits the *weakest* tier in its chain. A structural hop is
`type`-grade, so a naming-classified anchor drags the verdict to `naming`;
otherwise it stays `type` (an attribute-pinned anchor upgrades the chain). -/
private def weakenVia (v : ClassVia) : ClassVia :=
  match v with | .naming => .naming | _ => .type

inductive WalkResult where
  | none
  | decided (cat : SecurityProtocolCategory) (via : ClassVia)
  | tie (via : ClassVia)
  deriving Repr, BEq

/-- Neighbours to expand from `n`: a game-shaped def descends into its body
(term-deps) as well as its statement (type-deps); everything else follows
type-deps only. Imported anchors (absent from `declMap`) do not expand. -/
private def neighbors (declMap : Std.HashMap Name DeclInfo) (n : Name) : Array Name :=
  match declMap[n]? with
  | some d =>
    if d.codomainShape == .game then d.typeDependencies ++ d.termDependencies
    else d.typeDependencies
  | none => #[]

private partial def walkBFS (declMap : Std.HashMap Name DeclInfo)
    (anchorMap : Std.HashMap Name (SecurityProtocolCategory × ClassVia))
    (frontier : Array Name) (visited : Std.HashMap Name Unit) (depth : Nat)
    (cBest sBest : Option (Nat × ClassVia)) : Option (Nat × ClassVia) × Option (Nat × ClassVia) :=
  if frontier.isEmpty || depth > maxWalkDepth then (cBest, sBest)
  else
    -- Record the nearest depth per category. Among anchors at the SAME nearest
    -- depth, take the weakest `via` (a naming anchor drags the verdict to
    -- naming), so the result is independent of frontier order.
    let recordHit (best : Option (Nat × ClassVia)) (v : ClassVia) : Option (Nat × ClassVia) :=
      match best with
      | none => some (depth, v)
      | some (d0, v0) => if d0 == depth && v == .naming then some (d0, .naming) else some (d0, v0)
    let (cBest, sBest) := frontier.foldl (init := (cBest, sBest)) fun (cb, sb) n =>
      match anchorMap[n]? with
      | some (.correctness, v) => (recordHit cb v, sb)
      | some (.security, v) => (cb, recordHit sb v)
      | _ => (cb, sb)
    if cBest.isSome && sBest.isSome then (cBest, sBest)
    else
      let (next, visited) := frontier.foldl (init := (#[], visited)) fun (acc, vis) n =>
        (neighbors declMap n).foldl (init := (acc, vis)) fun (acc, vis) m =>
          if vis.contains m then (acc, vis) else (acc.push m, vis.insert m ())
      walkBFS declMap anchorMap next visited (depth + 1) cBest sBest

/-- Classify a declaration by walking its statement to the nearest anchor.
Strictly-shallower category wins; equal-depth ⇒ `tie`. -/
private def walk (declMap : Std.HashMap Name DeclInfo)
    (anchorMap : Std.HashMap Name (SecurityProtocolCategory × ClassVia)) (d : DeclInfo) : WalkResult :=
  let roots := neighbors declMap d.name
  let visited : Std.HashMap Name Unit := roots.foldl (·.insert · ()) {}
  let (cBest, sBest) := walkBFS declMap anchorMap roots visited 1 none none
  match cBest, sBest with
  | none, none => .none
  | some (_, v), none => .decided .correctness (weakenVia v)
  | none, some (_, v) => .decided .security (weakenVia v)
  | some (cd, cv), some (sd, sv) =>
    if cd < sd then .decided .correctness (weakenVia cv)
    else if sd < cd then .decided .security (weakenVia sv)
    else .tie (if cv == .naming || sv == .naming then .naming else .type)

-- ============================================================
-- Stages
-- ============================================================

private def baseClass (cat : SecurityProtocolCategory) (v : ClassVia) : Classification :=
  { category := cat, «via» := v }

/-- Stage 1 — schemes. -/
private def stageSchemes (decls : Array DeclInfo) (st : St) : St :=
  decls.foldl (init := st) fun st d =>
    let st := match kindTagMisuse d with | some m => st.diag m | none => st
    if st.isClassified d.name then st
    else if hasTag d "scheme_def" && isStructureKind d then
      (st.record d.name (baseClass .scheme .attribute)).addScheme d.name
    else if schemeByNaming d then
      (st.record d.name (baseClass .scheme .naming)).addScheme d.name
    else st

/-- Stage 2 — constructions: a `def`/`abbrev`/`instance` whose return-type head
is a scheme (project-own or catalogued VCVio), or carrying `@[construction_def]`.
A def carrying an explicit property tag (`@[correctness_spec]`/`@[security_spec]`)
is **deferred** to the property stage even if it returns a scheme — attributes are
authoritative and must not be preempted by construction type-inference. -/
private def stageConstructions (decls : Array DeclInfo) (st : St) : St :=
  decls.foldl (init := st) fun st d =>
    if st.isClassified d.name || !isConstructionKind d
        || hasTag d "correctness_spec" || hasTag d "security_spec" then st
    else if hasTag d "construction_def" then
      (st.record d.name (baseClass .construction .attribute)).addConstruction d.name
    else
      match d.codomainHead with
      | some h =>
        if st.isScheme h || Catalogue.vcvioSchemeTypes.contains h then
          (st.record d.name (baseClass .construction .type)).addConstruction d.name
        else st
      | none => st

/-- Classify + promote a property declaration to the anchor set. -/
private def recordProperty (st : St) (d : DeclInfo) (cat : SecurityProtocolCategory) (v : ClassVia) : St :=
  (st.record d.name (baseClass cat v)).promote d.name cat v

/-- Stage 3 sub-pass A — attribute and naming signals on property *definitions*
(non-theorem defs that are property-shaped or tagged), with promotion. -/
private def stagePropAttrNaming (decls : Array DeclInfo) (st : St) : St :=
  decls.foldl (init := st) fun st d =>
    if st.isClassified d.name || !isPropertyDef d then st
    else if hasAxisConflict d then
      (st.record d.name (baseClass .ambiguous .attribute)).diag
        s!"conflicting @[correctness_spec]+@[security_spec] on '{d.name}'"
    else if hasTag d "correctness_spec" then recordProperty st d .correctness .attribute
    else if hasTag d "security_spec" then recordProperty st d .security .attribute
    else if correctnessByNaming d && securityByNaming d then
      st.record d.name (baseClass .ambiguous .naming)
    else if correctnessByNaming d then recordProperty st d .correctness .naming
    else if securityByNaming d then recordProperty st d .security .naming
    else st

/-- Stage 3 sub-pass B — one type-reach pass over the candidate property defs in
`work`. Returns `(state, remaining, anchorAdded)`: `remaining` are the candidates
that reached no anchor this pass (to retry next pass); `anchorAdded` is whether a
*new anchor* was promoted (a `.decided` result) — NOT merely whether something was
recorded. A `.tie` records `ambiguous` but promotes no anchor, so it cannot unblock
any remaining candidate; only a new anchor can. Tracking anchor additions (rather
than any record) lets the fixpoint stop one pass sooner without changing the result.

This refactor is **behavior-preserving** relative to the previous loop, not a
re-derivation of ideal nearest-anchor semantics: like before, an unresolved def is
re-walked against a later (larger) anchor set, but a def that already reached a
verdict — including a `.tie` → `ambiguous` — keeps that verdict (the old loop
skipped it via `isClassified`; here it is simply not carried forward). A later
anchor that would have been *nearer* does not retroactively revise an earlier
verdict; that is a pre-existing property of the staged classifier, unchanged here. -/
private def stagePropReachPass (declMap : Std.HashMap Name DeclInfo) (work : Array DeclInfo)
    (st : St) : St × Array DeclInfo × Bool :=
  -- Snapshot the anchor set ONCE: every def in this pass is evaluated against
  -- the same set, and defs promoted during the pass become visible only in the
  -- NEXT pass. This makes the within-pass order irrelevant — the fixed point is
  -- order-independent (the anchor set grows monotonically across passes).
  let anchorMap : Std.HashMap Name (SecurityProtocolCategory × ClassVia) :=
    st.anchors.foldl (fun m e => m.insert e.1 (e.2.1, e.2.2)) {}
  work.foldl (init := (st, #[], false)) fun (st, rem, anchorAdded) d =>
    if st.isClassified d.name then (st, rem, anchorAdded)   -- e.g. classified by sub-pass A
    else
      match walk declMap anchorMap d with
      | .none => (st, rem.push d, anchorAdded)               -- no anchor yet → retry next pass
      | .tie v => (st.record d.name (baseClass .ambiguous v), rem, anchorAdded)  -- no new anchor
      | .decided cat v => (recordProperty st d cat v, rem, true)

/-- Iterate sub-pass B to a fixed point. The candidate set is filtered **once**
and only the still-unresolved defs are carried forward, so each pass re-walks
just what is left (not all decls). We recurse only when a *new anchor* was added
**and** unresolved candidates remain: a pass that produced only ties (or nothing)
left the anchor set unchanged, so another pass over `rem` would walk the identical
anchor map and find nothing new. The per-pass anchor snapshot — and thus
order-independence — is unchanged. -/
private partial def reachFixpoint (declMap : Std.HashMap Name DeclInfo) (work : Array DeclInfo)
    (st : St) : St :=
  let (st, rem, anchorAdded) := stagePropReachPass declMap work st
  if anchorAdded && !rem.isEmpty then reachFixpoint declMap rem st else st

private def stagePropReachLoop (declMap : Std.HashMap Name DeclInfo) (decls : Array DeclInfo)
    (st : St) : St :=
  -- Filter mirrors the old per-pass guard exactly; sub-pass-A-classified defs
  -- fall out on pass 1 via the `isClassified` check in `stagePropReachPass`.
  let work := decls.filter fun d => !isTheorem d && isPropertyTaggable d && isPropertyShaped d
  reachFixpoint declMap work st

/-- Stage 4 — theorems: attribute, then walk, then naming. The anchor set is
frozen by now (theorems never promote), so the anchor map is built once. -/
private def stageTheorems (declMap : Std.HashMap Name DeclInfo) (decls : Array DeclInfo) (st : St) : St :=
  let anchorMap : Std.HashMap Name (SecurityProtocolCategory × ClassVia) :=
    st.anchors.foldl (fun m e => m.insert e.1 (e.2.1, e.2.2)) {}
  decls.foldl (init := st) fun st d =>
    if st.isClassified d.name || !isTheorem d then st
    else if hasAxisConflict d then
      (st.record d.name (baseClass .ambiguous .attribute)).diag
        s!"conflicting @[correctness_spec]+@[security_spec] on '{d.name}'"
    else if hasTag d "correctness_spec" then st.record d.name (baseClass .correctness .attribute)
    else if hasTag d "security_spec" then st.record d.name (baseClass .security .attribute)
    else
      match walk declMap anchorMap d with
      | .decided cat v => st.record d.name (baseClass cat v)
      | .tie v => st.record d.name (baseClass .ambiguous v)
      | .none =>
        if correctnessByNaming d && securityByNaming d then
          st.record d.name (baseClass .ambiguous .naming)
        else if correctnessByNaming d then st.record d.name (baseClass .correctness .naming)
        else if securityByNaming d then st.record d.name (baseClass .security .naming)
        else st

-- ============================================================
-- Link resolution (fail-closed)
-- ============================================================

/-- The unique members of `cands` that are classified atoms of `kind`, as a
sorted-deduped array (`[]` = none, one = string link, many = ambiguous array). -/
private def uniqueClassified (cands : Array Name) (pred : Name → Bool) : Array Name :=
  let hits := cands.filter pred
  (hits.foldl (init := #[]) fun acc n => if acc.contains n then acc else acc.push n)
    |>.qsort (·.toString < ·.toString)

private def schemeOfConstruction (st : St) (construction : Name) : Array Name :=
  match st.result.find? (·.1 == construction) with
  | some (_, c) => c.scheme
  | none => #[]

/-- Resolve `scheme`/`construction` links for every classified atom. Two passes:
constructions first (so properties can read their scheme), then properties. -/
private def resolveLinks (decls : Array DeclInfo) (emitted : Array Name) (st : St) : St :=
  let declOf (n : Name) : Option DeclInfo := decls.find? (·.name == n)
  -- pass 1: constructions → scheme = return-type head iff a classified, emitted scheme atom
  let st := st.result.foldl (init := { st with result := #[] }) fun st (n, c) =>
    match c.category with
    | .construction =>
      let scheme := match declOf n |>.bind (·.codomainHead) with
        | some h => if st.isScheme h && emitted.contains h then #[h] else #[]
        | none => #[]
      st.record n { c with scheme }
    | _ => st.record n c
  -- pass 2: correctness/security/ambiguous → construction (unique) + scheme
  let st := st.result.foldl (init := { st with result := #[] }) fun st (n, c) =>
    match c.category with
    | .correctness | .security | .ambiguous =>
      let typeDeps := (declOf n).map (·.typeDependencies) |>.getD #[]
      let constructions := uniqueClassified typeDeps
        (fun m => st.isConstruction m && emitted.contains m)
      let scheme :=
        if constructions.isEmpty then
          uniqueClassified typeDeps (fun m => st.isScheme m && emitted.contains m)
        else
          (constructions.foldl (init := #[]) fun acc cn =>
            (schemeOfConstruction st cn).foldl (init := acc) fun acc s =>
              if acc.contains s then acc else acc.push s).qsort (·.toString < ·.toString)
      st.record n { c with construction := constructions, scheme }
    | _ => st.record n c
  st

-- ============================================================
-- Entry point
-- ============================================================

/-- Classify all project declarations. Returns `(name, classification)` pairs
for the classified atoms (unclassified atoms are simply absent) and a list of
diagnostics (tag conflicts/misuse). Pure. -/
def classify (decls : Array DeclInfo) : Array (Name × Classification) × Array String :=
  let declMap : Std.HashMap Name DeclInfo := decls.foldl (fun m d => m.insert d.name d) {}
  let emitted := decls.map (·.name)
  let st0 : St := { anchors := seedAnchors }
  let st := stageSchemes decls st0
  let st := stageConstructions decls st
  let st := stagePropAttrNaming decls st
  let st := stagePropReachLoop declMap decls st
  let st := stageTheorems declMap decls st
  let st := resolveLinks decls emitted st
  (st.result, st.diags)

end ProbeLean.Classify
