# Feature: Typed Dependencies (Type vs Term)

## Summary

Differentiate between **type dependencies** and **term dependencies** in the dependency graph produced by `probe-lean extract`. Type dependencies are Lean constructs referenced in a declaration's *type signature* (the specification surface), while term dependencies are constructs referenced in the declaration's *value/proof body* (the implementation mechanism). This distinction enables richer analysis: understanding what a theorem *states about* vs what its proof *relies on*, and tracking specification-level vs implementation-level impact of changes.

## Motivation

Currently, `getDependencies` in `Analysis.lean` already computes type-level and value-level constants separately (`typeConsts` and `valueConsts`) but merges them into a single flat `dependencies` array before output. This loses information that is valuable for:

1. **Verification tracking** — A change to a term dependency may break a proof; a change to a type dependency changes what is being stated (usually more significant).
2. **Dependency graph visualization** — Two distinct graphs: a "specification graph" (type deps) showing conceptual relationships, and a "proof graph" (term deps) showing proof structure.
3. **Impact analysis** — If a lemma changes, only constructs with it as a term dependency need proofs rechecked. Constructs with it as a type dependency need their statements rechecked.
4. **Spec coverage** — Type dependencies of theorems reveal which definitions a spec *talks about*, independent of how it's proven.

## Requirements

- [ ] `getDependencies` returns type and term dependency arrays separately (not merged)
- [ ] `DeclInfo` carries both `typeDependencies` and `termDependencies` fields
- [ ] `Atom` and `UnifiedAtom` gain `type-dependencies` and `term-dependencies` JSON fields
- [ ] The existing `dependencies` field is preserved as the union (backward compatibility)
- [ ] Dependencies appearing in both type and term are present in both arrays (no deduplication across categories)
- [ ] `computeSpecs` continues to work correctly (using the union `dependencies`)
- [ ] All existing tests pass without modification (the `dependencies` field is unchanged)
- [ ] New tests validate that type and term dependencies are correctly separated
- [ ] README is updated to document the new fields

## API / Interface Design

### Internal Types

```lean
-- Analysis.lean: return a named pair instead of a single array
structure DependencyInfo where
  typeDeps : Array Name
  termDeps : Array Name

def getDependencies (info : ConstantInfo) : DependencyInfo :=
  let type := info.type
  let value := info.value?
  let typeConsts := type.getUsedConstants
  let valueConsts := match value with
    | some v => v.getUsedConstants
    | none => #[]
  { typeDeps := typeConsts, termDeps := valueConsts }
```

```lean
-- Analysis.lean: extend DeclInfo
structure DeclInfo where
  name : Name
  displayName : String
  moduleName : Name
  kind : DeclKind
  dependencies : Array Name        -- union, for backward compat
  typeDependencies : Array Name     -- from the type/signature
  termDependencies : Array Name     -- from the value/proof body
  sourceInfo : Option CodeTextInfo
```

```lean
-- Types.lean: extend Atom
structure Atom where
  name : String
  displayName : String
  dependencies : Array String        -- union (backward compat)
  typeDependencies : Array String    -- new
  termDependencies : Array String    -- new
  -- ... rest unchanged
```

### JSON Output

```json
{
  "probe:MyProject.run_mul": {
    "display-name": "run_mul",
    "dependencies": [
      "probe:L", "probe:instFactPrimeL", "probe:R",
      "probe:Scalar52", "probe:IsMont", "probe:Scalar52_as_Nat",
      "probe:isMont_mul"
    ],
    "type-dependencies": [
      "probe:L", "probe:R", "probe:Scalar52",
      "probe:IsMont", "probe:Scalar52_as_Nat"
    ],
    "term-dependencies": [
      "probe:isMont_mul", "probe:instFactPrimeL"
    ],
    "kind": "theorem"
  }
}
```

Note: A constant may appear in both `type-dependencies` and `term-dependencies` (e.g., if a function is mentioned in the signature and also `unfold`ed in the proof). The `dependencies` field remains the deduplicated union of both.

## Behavior

### Normal Operation

1. For each declaration in the environment, `getDependencies` extracts two separate arrays:
   - `typeDeps` — constants from `info.type.getUsedConstants`
   - `termDeps` — constants from `info.value?.getUsedConstants`
2. Both arrays are independently filtered to project-only, non-internal declarations (same rules as today).
3. The `dependencies` field is computed as the deduplicated union of both (identical to current behavior).
4. Both `type-dependencies` and `term-dependencies` are serialized to JSON.

### Edge Cases

- **Declaration with no value** (axioms, opaque): `term-dependencies` is empty; `type-dependencies` contains all dependencies. `dependencies` equals `type-dependencies`.
- **Constant appears in both type and value**: Present in both `type-dependencies` and `term-dependencies`. Present once in `dependencies` (deduplicated).
- **Constructors/recursors**: Skipped as before — no change.
- **Instance declarations**: Type dependencies include the class being instantiated; term dependencies include methods/definitions used in the implementation body.
- **`abbrev` declarations**: Type has the abbreviated type; value has the definition body. Both produce dependencies.

### Downstream Impact

- **`computeSpecs`**: Uses `dependencies` (the union), so no change needed. Could optionally be refined later to only consider term dependencies of theorems, but that is out of scope.
- **`viewify`**: Passes through atom fields. Will automatically include the new fields if Atom serialization includes them.
- **Schema version**: This is an additive change (new optional fields). No schema version bump required, but the schema docs should be updated.

## Non-Goals

- Finer-grained categorization within type or term dependencies (e.g., distinguishing implicit vs explicit arguments, typeclass vs direct usage)
- Transitive dependency analysis (only direct references, same as today)
- Changing the existing `dependencies` field semantics
- Changing `computeSpecs` logic to use only term dependencies
- Differentiating between dependencies from different parts of the type (e.g., hypotheses vs conclusion)

## Acceptance Criteria

- [ ] `getDependencies` returns a `DependencyInfo` with separate `typeDeps` and `termDeps`
- [ ] JSON output includes `type-dependencies` and `term-dependencies` fields for every atom
- [ ] `dependencies` field remains identical to current output (union of both, deduplicated)
- [ ] For an axiom (no value), `term-dependencies` is `[]`
- [ ] For a theorem like `horner_natCast`, type deps include `p` (from `ZMod p` in signature) and term deps include proof-body references
- [ ] A constant appearing in both type and value appears in both arrays
- [ ] All existing tests pass unchanged
- [ ] New test: a declaration with known type-only, term-only, and shared dependencies is verified
- [ ] README documents the new `type-dependencies` and `term-dependencies` fields
- [ ] Schema documentation (`docs/SCHEMA.md`) is updated

---
Status: in-progress
