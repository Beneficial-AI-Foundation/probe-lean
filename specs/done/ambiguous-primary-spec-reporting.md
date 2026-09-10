# Feature: Report Ambiguous `@[primary_spec]` Tags

## Summary

When several theorems tagged `@[primary_spec]` resolve to the same target definition, `computeSpecs` keeps whichever one it inserts last into `attrPrimarySpecMap` (`ProbeLean/Atomize.lean:175-180`) and discards the rest without comment. The target's `primary-spec` names one theorem; the others sit in the same target's `specs` list looking like ordinary specs. Nothing in the artifact marks the pick as an arbitrary tie-break rather than a confident single designation.

The candidate set is *almost* recoverable from what is already emitted — `specs` and the `@[primary_spec]` map are built from the same `specTargets` function, so every tagged candidate for a target is guaranteed to appear in that target's `specs`. What is missing is a *reliable* per-theorem "was this tagged" bit.

A looser one already ships, and this spec does not claim otherwise: `ProbeLean/Analysis.lean:565-567` pushes `"primary_spec"` into `attributes` whenever the handle reports the tag, and `attributes` serializes whenever non-empty, so `"primary_spec" ∈ attributes` is a working recovery path today. It is imprecise because `attributes` merges the attribute handle with a source-level `@[...]` scan, so it also fires for a project that registers its own `primary_spec` attribute without importing `ProbeLean.Attrs` — a case `computeSpecs` does not honour. `Atom.isPrimarySpec` is the exact bit `computeSpecs` keys off, but it is **read** by both `fromJson` implementations (`ProbeLean/Types.lean:290`, `:547`) and **written** by neither `toJson`. The `<|> pure false` default hides the asymmetry, so the field silently round-trips to `false` for every atom.

This feature therefore adds no new concept. It closes the serializer gap by emitting `is-primary-spec`, which makes the candidate set derivable downstream as `{ s ∈ target.specs : atoms[s]["is-primary-spec"] }` — exactly so whenever published names are unique, which is the condition `duplicateAtomNames` already reports on (see *Known limitations*) — and it prints a stderr warning during `extract` so the project author sees the collision without post-processing the artifact.

The two halves are independent: the warning reads the in-memory atom array and needs no serializer change, so it could ship on its own if a smaller first step is wanted. They are specified together because the warning tells the author about one collision at build time while the emitted bit lets a downstream tool find all of them in the artifact.

## Requirements

- [ ] `Atom.toJson` and `UnifiedAtom.toJson` emit `is-primary-spec`, alongside the other `is-*` booleans in the `base` list, always present (not omitted when `false`) — matching `is-hidden` / `is-relevant` / `is-in-package`
- [ ] `is-primary-spec` means **tagged**, never **won**. It is set only at `ProbeLean/Analysis.lean:561` from the `@[primary_spec]` attribute handle; `computeSpecs` never writes it. A theorem chosen by the heuristic signals (known-attribute, `_spec` suffix, sole spec) is named by its target's `primary-spec` while its own atom serializes `is-primary-spec: false`. `specs/done/primary-spec-heuristic.md:42` shows this JSON shape under the heading *On the matched theorem*, i.e. the winner — that document supplies the **shape only, not the semantics**, and this feature does not change which declarations carry the flag
- [ ] The flag is also independent of declaration kind: `registerTagAttribute` (`ProbeLean/Attrs.lean:17-18`) installs no validator, so `@[primary_spec] def foo` is accepted and will now visibly serialize `is-primary-spec: true` even though a non-theorem can never enter a `specs` list or win `primary-spec`
- [ ] No new field on `Atom` or `UnifiedAtom`, and no new JSON field beyond `is-primary-spec`; `primarySpecCandidates` is explicitly **not** added
- [ ] A pure helper `ambiguousPrimarySpecs : Array Atom → Array PrimarySpecCollision` returns one record per target with two or more tagged candidates, sorted by target name. The record is named rather than a bare tuple so `target` and `winner` cannot be transposed silently at the formatting boundary
- [ ] The helper derives candidates from `atom.specs` intersected with the set of tagged theorem names — the same two pieces of data the artifact emits — so the warning cannot disagree with the post-`computeSpecs` atom array, and cannot disagree with the emitted JSON **whenever published names are unique**. Under duplicate published names the two deliberately diverge, and the warning is the more correct of the two: see *Known limitations*
- [ ] The tagged set is a **union of names**, not a `name → Bool` map: a name belongs to it iff *any* atom publishing that name satisfies `kind == theorem && isPrimarySpec`. A last-write-wins map would let a later untagged atom clobber an earlier tagged one under duplicate published names and drop a real candidate. The `kind == theorem` gate mirrors `attrPrimarySpecMap` (`ProbeLean/Atomize.lean:176-177`) and keeps a tagged non-theorem out of the candidate set even when its published name collides with a theorem's
- [ ] Candidate names are de-duplicated before the "two or more" test, so two private theorems that publish under the same `probe:` name cannot fabricate a collision (see `duplicateAtomNames`, `ProbeLean/Extract.lean:166-175`)
- [ ] One record per **target name**, not per atom. `computeSpecs` sets `primarySpec` on every atom whose name matches the target (`ProbeLean/Atomize.lean:210-212`), so iterating atoms directly would emit two identical records — and two identical warnings — for a single logical target whose name is duplicated
- [ ] `rejected` is sorted, making the warning text deterministic and independent of input array order (P14). Filtering an already-sorted `specs` (`ProbeLean/Atomize.lean:208`) happens to preserve order today, but the helper must not rely on that: an implementation that materialises candidates through an unordered set would otherwise produce non-deterministic warnings
- [ ] `extract` prints one stderr warning per affected target; exit code unchanged
- [ ] The warning loop runs on the **post-`computeSpecs`** atom array, i.e. after the `computeSpecs` call in `runExtractInProject` — not next to the duplicate-atom-name loop just above it, which runs before `computeSpecs` and would see an empty result
- [ ] `computeSpecs` is not modified: no change to `specs`, to the winner, or to the heuristic signals; no `IO` introduced
- [ ] `Constants.schemaVersion` stays `"3.0"` — this is an additive field, and the previous bump to `4.0` was reverted for breaking consumers (commit `97fd466`)
- [ ] Tests added; `docs/SCHEMA.md`, `docs/USAGE.md`, `README.md` updated; `CHANGELOG.md` entry and minor version bump

## API / Interface Design

No new CLI flags. `is-primary-spec` becomes a documented boolean on every atom in both output types. Extract output keys atoms by name, so the field appears inside the keyed object:

```json
"probe:MyModule.helper_correct": {
  "kind": "theorem",
  "is-primary-spec": true,
  "attributes": ["primary_spec"]
},
"probe:MyModule.helper": {
  "kind": "def",
  "is-primary-spec": false,
  "specs": ["probe:MyModule.helper_bounds", "probe:MyModule.helper_correct"],
  "primary-spec": "probe:MyModule.helper_correct"
}
```

A consumer reads the collision off those two atoms: both entries of `helper.specs` resolve to atoms, `helper_bounds` and `helper_correct` are both `is-primary-spec: true`, and only one of them is named by `primary-spec`.

The converse does not hold, and consumers must not assume it: a target's `primary-spec` may name a theorem whose own `is-primary-spec` is `false`, because the heuristic signals pick a winner without tagging it. `is-primary-spec: true` is also not restricted to theorems. The field answers *was this declaration tagged*, and is only meaningful as a collision signal when intersected with a target's `specs`.

### Warning text

One line per affected target, on stderr, modelled on the duplicate-atom-name warning at `ProbeLean/Extract.lean:289-290`:

```
Warning: 2 @[primary_spec] theorems target probe:MyModule.helper — chose probe:MyModule.helper_correct (arbitrary tie-break); also tagged: probe:MyModule.helper_bounds
```

The leading count is the total number of tagged candidates, i.e. `rejected.size + 1` — not `rejected.size`. The rejected names are sorted and comma-separated when there are several, so a three-candidate collision reads:

```
Warning: 3 @[primary_spec] theorems target probe:MyModule.helper — chose probe:MyModule.helper_correct (arbitrary tie-break); also tagged: probe:MyModule.helper_alt, probe:MyModule.helper_bounds
```

The text deliberately does **not** describe the pick as "alphabetically last" — see *Known limitations* below.

### Helper signature

```lean
/-- A target whose `primary-spec` was an arbitrary tie-break. -/
structure PrimarySpecCollision where
  target : String
  winner : String
  /-- Tagged candidates other than the winner: sorted, de-duplicated, non-empty. -/
  rejected : Array String
  deriving Repr, BEq

/-- Targets whose `primary-spec` was an arbitrary tie-break: two or more
    `@[primary_spec]`-tagged theorems resolve to the same target. One record per
    target name, sorted by target name, candidate names de-duplicated.

    Only targets with `primarySpec` set are considered. Derived from the same
    `specs` / `isPrimarySpec` data the artifact emits, so a warning cannot
    disagree with the emitted JSON when published names are unique; under
    duplicate names it follows the pre-serialization array and is the more
    correct of the two. -/
def ambiguousPrimarySpecs (atoms : Array Atom) : Array PrimarySpecCollision

/-- Render one collision as its stderr warning line. Pure, so the exact text is
    testable without capturing stderr. Takes the record rather than positional
    strings so `target` and `winner` bind by name. -/
def formatPrimarySpecWarning (c : PrimarySpecCollision) : String
```

Both live in `ProbeLean/Extract.lean` next to `duplicateAtomNames`.

## Behavior

### Normal operation

`computeSpecs` runs unchanged. After it, `runExtractInProject` calls `ambiguousPrimarySpecs` on the resulting array and prints one `formatPrimarySpecWarning` line per record.

`ambiguousPrimarySpecs` first builds the tagged set: the names of atoms with `kind == theorem && isPrimarySpec`, unioned so a duplicated name is tagged if any of its atoms is. It then walks the atoms keyed by target name, so each name is considered once however many atoms publish it, and for each name with `primarySpec = some w`:

- filter `specs` to the tagged set and de-duplicate — these are the tagged candidates
- fewer than two candidates: no record, no warning (the common case)
- two or more: emit `⟨name, w, (candidates.filter (· != w)).qsort (· < ·)⟩`

Results are sorted by target name before returning.

Two invariants make this exact rather than approximate, both consequences of `specs` and `attrPrimarySpecMap` sharing `specTargets`:

1. Every tagged theorem resolving to a target appears in that target's `specs` — including generated theorems, which re-enter via the `isGeneratedTheorem` escape hatch.
2. The winner is always among the candidates, so `rejected` is exactly the candidate set minus one and is never empty when a record is emitted.

A target can only reach the two-or-more branch if a tagged theorem targets it, and in that case `attrPrimarySpecMap` already holds an entry, so the heuristic signals never ran for it. There is no path where a heuristic-chosen `primary-spec` is reported as a tie-break.

### Edge cases

- **One tagged theorem targeting several definitions** (fan-out, not collision): each target has exactly one candidate; no warning.
- **Heuristic ambiguity** (two `@[progress]` specs, no explicit tag): no `primary-spec` is set at all, so no record; the target is not reported. Unchanged from today.
- **A tagged theorem flagged generated** (`is-lean-generated` / `is-aeneas-generated`): re-enters `specs` via the escape hatch and counts as a candidate like any other tagged theorem.
- **A tagged theorem whose statement names no specifiable constant**: the union-dependency fallback in `specTargets` applies unchanged; if it lands on a target another tagged theorem also claims, it participates in the collision normally.
- **Two private theorems publishing the same `probe:` name**: three separate hazards, each closed by its own requirement. De-duplication collapses them to one candidate, so no false collision is reported. Keying results by target name stops one duplicated *target* from emitting the same warning twice. Union semantics for the tagged set stop an untagged namesake from masking a tagged theorem. If the declarations genuinely differ, the existing `duplicateAtomNames` warning is the signal for that, not this one.
- **Namesakes claimed by different targets** (accepted false positive): a tagged `private theorem X` in module A targeting `U`, plus an untagged `private theorem X` in module B that appears in `T.specs` alongside a tagged `Y`. Union semantics mark the *name* `probe:X` tagged, so `T` sees two candidates and is reported even though only `Y` is tagged for it. Only the warning is wrong: `attrPrimarySpecMap` inserts `target → theorem` from each tagged theorem's own `specTargets` (`ProbeLean/Atomize.lean:175-180`), so the tagged `X` contributes `U → probe:X` and never `T → probe:X`, and `T` still emits `primary-spec: probe:Y`. This is the deliberate cost of union semantics: a `name → Bool` map would suppress the spurious warning but would let an untagged namesake clobber a tagged one and *silently* drop a real candidate, so over-reporting is the better failure. The precondition is duplicate published names, which `duplicateAtomNames` already warns about in the same run.
- **A tagged non-theorem** (`@[primary_spec] def foo`): accepted by the attribute, serializes `is-primary-spec: true`, but never enters any `specs` list, so it is never a candidate and never a winner. The `kind == theorem` gate on the tagged set keeps it out even when its published name collides with a theorem's.
- **`attributes` contains `primary_spec` but `isPrimarySpec` is false**: possible when the target project registers its own `primary_spec` attribute without importing `ProbeLean.Attrs`, because `attributes` also comes from source-level `@[...]` scanning (`ProbeLean/Analysis.lean:571-577`; the handle-based push is `:564-570`). `computeSpecs` keys off `isPrimarySpec`, and so does this warning, so the two agree. Emitting `is-primary-spec` lets consumers key off the same bit instead of the looser `attributes` list. Reconciling the two detection paths is out of scope and has no spec of its own yet.

### Error handling

Ambiguity is a warning, never an error. `extract` exit codes are unaffected, matching how duplicate atom names are handled.

### Known limitations (recorded, not fixed here)

**Downstream recovery degrades under duplicate published names.** The derivation `{ s ∈ target.specs : atoms[s]["is-primary-spec"] }` is exact only when published names are unique. Both output types key atoms by name (`ProbeLean/Types.lean:299-307` for `AtomsOutput`, `:561-566` for the `UnifiedAtomsOutput` that `extract` actually writes), so two declarations publishing the same `probe:` name collapse to a single JSON entry and `atoms[s]` resolves to whichever was emitted last. In that case the candidate set recovered from the artifact is best-effort; the stderr warning, which sees the pre-serialization array, remains correct. `duplicateAtomNames` already flags the underlying condition, so a consumer that needs an exact candidate set can gate on that warning.

**The winner is arbitrary and keyed on internal names.** The winner is deterministic but arbitrary, and it is keyed on the **internal Lean declaration name**, not the published `probe:` name. Atoms are sorted at `ProbeLean/Analysis.lean:451` by `a.name.toString` — the raw declaration name — while `atom.name` is `probeRef info.name`, which rewrites `_private.Mod.0.Foo.bar` to `probe:Foo.bar`. For public declarations the two orders coincide; for private ones they diverge, so "last inserted" is not "alphabetically last published name". Stabilising the pick on published names would change which theorem wins for private candidates, which is a behavior change this spec does not make. The warning is worded to avoid asserting any ordering rationale.

## Non-Goals

- Does NOT add `primary-spec-candidates` or any other new field — the candidate set is derivable from `specs` + `is-primary-spec`
- Does NOT change which theorem wins, nor stabilise the pick on published names
- Does NOT change which declarations carry `is-primary-spec`: the flag stays *tagged*, not *won*, so heuristic winners keep `false` and tagged non-theorems keep `true`. Aligning the flag with the winner (as `specs/done/primary-spec-heuristic.md:42` reads) would be a behavior change requiring its own spec
- Does NOT add a config option or CLI flag to pick a winner
- Does NOT introduce a semantic tie-break (`_spec` suffix or known-attribute preference among tagged candidates)
- Does NOT report heuristic-signal ambiguity, where no `primary-spec` is emitted at all
- Does NOT change `specs` list computation or verification-status assignment
- Does NOT reconcile `isPrimarySpec` (attribute handle) with `attributes` (source scan)
- Does NOT bump `schema-version`, and does NOT surface anything new through `viewify`

## Acceptance Criteria

### Serialization

- [ ] `Atom.toJson` and `UnifiedAtom.toJson` both emit `is-primary-spec`; a tagged theorem serializes `true`, an untagged atom serializes `false`
- [ ] Round-trip: `fromJson (toJson a)` preserves `isPrimarySpec` in both directions for `true` and `false`
- [ ] Legacy input: JSON with no `is-primary-spec` key still parses, defaulting to `false`, in the style of the existing legacy test at `Tests/Main.lean:1459-1478`
- [ ] Tagged, not won: a target whose `primary-spec` was chosen by a heuristic signal serializes that winner's atom with `is-primary-spec: false`
- [ ] `Constants.schemaVersion` is still `"3.0"`

### Ambiguity detection

**Fixture protocol.** The helper only considers names where `primarySpec = some w`, and analysis atoms start with `primarySpec := none` and no `specs` (`ProbeLean/Analysis.lean:580-600` sets neither; `computeSpecs` does, at `ProbeLean/Atomize.lean:207-212`). A fixture that hand-fills `specs` and `isPrimarySpec` but leaves `primarySpec` unset therefore yields no record, which would let several criteria below pass for the wrong reason. So: collision fixtures run `computeSpecs` first and feed its output to the helper, with theorems carrying `typeDependencies` and `isPrimarySpec` rather than a hand-built `specs` list — `computeSpecs` overwrites `specs` from `typeDependencies` anyway. The synthetic duplicate-name criteria are the exception, since `computeSpecs` cannot produce them; those must set `primarySpec := some …` on the target explicitly, so that "no record" can only mean de-duplication worked.

- [ ] Two tagged theorems on one def: one record, winner equals the atom's `primarySpec`, `rejected` is the other theorem
- [ ] Three tagged theorems: `rejected` has the two non-winners, sorted
- [ ] One tagged theorem: no record
- [ ] Untagged heuristic ambiguity (two `@[progress]`): no `primary-spec`, no record — existing test still passes
- [ ] Fan-out (one tagged theorem, two targets): no record for either target
- [ ] Duplicate published names: two atoms named `probe:X`, both `isPrimarySpec`, both in a target's `specs` — no record (de-duplication)
- [ ] Duplicate target names: two atoms both named `probe:T`, both carrying the same `primarySpec` and `specs` from `computeSpecs` — exactly one record, not two
- [ ] Untagged namesake does not mask a tagged theorem: atoms `probe:X` with `isPrimarySpec := true` and `probe:X` with `isPrimarySpec := false` still put `probe:X` in the tagged set, whatever their array order
- [ ] A tagged non-theorem (`kind := .def`, `isPrimarySpec := true`) sharing a target's spec name is not counted as a candidate
- [ ] No winner, no record: a target with two tagged names in `specs` but `primarySpec = none` produces no record. This pins the `primarySpec` gate, which the duplicate-name criteria above would otherwise satisfy accidentally
- [ ] Invariant 2 holds, not merely that `rejected` looks plausible: for every record, `rejected ∪ {winner}` equals the de-duplicated intersection of the target's `specs` with the tagged set, and `rejected = that set \ {winner}`. Asserting only "winner ∉ rejected and rejected non-empty" is too weak — a heuristic winner `W` with tagged candidates `{A, B}` satisfies it while the record would claim `W` was a tag tie-break, and would make the warning's `rejected.size + 1` count wrong
- [ ] Output is sorted by target name; `rejected` is sorted; both are independent of input array order — assert by running the helper on a shuffled copy of the same atoms and comparing results (`PrimarySpecCollision` derives `BEq` for this). The shuffled run must **not** re-run `computeSpecs`, whose last-write-wins insert would legitimately pick a different winner
- [ ] Collision fixtures are built in the order production feeds them, i.e. sorted as `ProbeLean/Analysis.lean:451` sorts, so the asserted winner reflects the real tie-break rather than an arbitrary test-array order. Note that `:451` sorts `DeclInfo.name.toString` — the raw Lean name — not `Atom.name`; for public names sorting fixtures by `atom.name` coincides, but production order is not reconstructible from an `Atom` array once `probeRef` has been applied, so private-name fixtures cannot pin a winner this way

### Warning

- [ ] `formatPrimarySpecWarning` produces the exact text in *API / Interface Design* for both the two-candidate and three-candidate cases, comma-separating rejected names
- [ ] The leading count is `rejected.size + 1`, verified by a three-candidate case printing `3` rather than `2`
- [ ] Warning contents agree with the emitted atom **when published names are unique**: the target's `primary-spec` equals the warning's winner, and every rejected name is in the target's `specs` with `is-primary-spec: true`. Assert this on a unique-name fixture only — under duplicate published names it is jointly unsatisfiable with the union-semantics criterion above, because the keyed JSON keeps only the last-emitted atom for a name while the tagged set unions over all of them
- [ ] The warning is actually wired in, not just implementable: `runExtractInProject` calls `ambiguousPrimarySpecs` on the post-`computeSpecs` array and prints `formatPrimarySpecWarning` for each record on stderr. Without this the pure helper and formatter can pass every criterion above while `extract` prints nothing — the failure mode `duplicateAtomNames` already has, since it is called at `ProbeLean/Extract.lean:289-290` but appears nowhere in `Tests/Main.lean`. Cover it by extracting the loop into a small `IO` helper and testing that, or by a review checkbox on the call site; a full extract integration test is not required
- [ ] `computeSpecs` remains `IO`-free and all existing `computeSpecs` / primary-spec tests pass unchanged

### Housekeeping

- [ ] New tests live in their own `testPrimarySpecAmbiguity*` function(s) called from `main`, **split across several small functions** as the bind count approaches ~30, per the elaboration-depth rules in `CLAUDE.md`. The criteria above enumerate roughly fifteen cases, which will not fit one `do` block; the existing primary-spec tests are already split five ways (`testPrimarySpecHeuristic`, `testPrimarySpecKnownAttribute`, `testPrimarySpecSoleSpec`, `testPrimarySpecProofOnlyFallback`, `testComputeSpecs*`), so a single function would regress the convention this rule exists to enforce. Serialization criteria belong in the existing JSON test functions rather than a new one
- [ ] `docs/SCHEMA.md`: `is-primary-spec` row added to the *Lean-Specific Atom Fields* table, the *Field Computation Methods* table (marked **AUTO** — set from the `@[primary_spec]` attribute handle), and the `probe-lean/extract` table. Each description states that the field means *tagged*, not *won*: a heuristic winner carries `false`, and a tagged non-theorem carries `true`. The `primary-spec` row is qualified to note the tie-break and that it may name a theorem whose own `is-primary-spec` is `false`. Envelope examples updated. (Section names, not line numbers — the previously cited `:247` / `:263` / `:284` are headings, with the tables a few lines below.)
- [ ] `docs/USAGE.md`: the extract walkthrough mentions the warning. The `primary-spec` example is deliberately **not** extended with the new field. That example is already an illustrative subset rather than a faithful rendering — it omits `is-in-package` and both `codomain-*` booleans, all three of which `ProbeLean/Types.lean:495-520` emits unconditionally — and it shows only the *def*, with no atom for the `helper_spec` it names. Adding `is-primary-spec: false` there would stamp the flag on the atom that *has* a primary spec and read as the opposite of what the field means. If the field is worth a mention in USAGE at all, mention it in prose, following the `codomain-*` precedent at `docs/USAGE.md:82`. The field's JSON shape belongs in `docs/SCHEMA.md`, whose envelope example already carries a theorem with `attributes: ["primary_spec"]` to hang `is-primary-spec: true` on
- [ ] `README.md`: step 4 of the pipeline mentions the tie-break and warning. The *Example Output* block at `README.md:186-221` is left alone for the same reason as USAGE — it omits the same three unconditional fields and is an illustrative subset, not a golden artifact
- [ ] The example fixture is regenerated, never hand-edited: run `./tools/gen-fixture.sh` and commit `examples/lean_ExampleProject_0.1.0.json`. It is real probe-lean output, and the `test` job regenerates it and fails on any diff, so skipping this breaks CI. `is-primary-spec` will appear on all eight atoms, reading `true` on `helper_bounds` and `helper_correct` — the two `@[primary_spec]`-tagged theorems the fixture already carries, which also make it a live example of the tie-break this feature reports
- [ ] `specs/done/primary-spec-heuristic.md:42` gets a one-line erratum. It shows `"is-primary-spec": true` under *On the matched theorem*, i.e. on the heuristic winner. That was harmless while the field never serialized, but once it is emitted the done spec describes behavior the tool does not implement. A pointer to this spec is enough; done specs are reference-only and are not otherwise edited
- [ ] `CHANGELOG.md` entry under Unreleased noting that **every** atom gains an always-present boolean, so extract artifacts show a whole-file diff even for projects with no ambiguity; `lakefile.toml` bumped to `0.13.0` with `./tools/gen-version.sh` re-run (output format change ⇒ minor bump)

---
Status: done
