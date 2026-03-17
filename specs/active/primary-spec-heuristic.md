# Feature: Primary Spec Heuristic

## Summary

Add a naming-convention heuristic to `computeSpecs` so that non-theorem atoms receive a `primary-spec` even when the target project does not use the `@[primary_spec]` attribute. If a non-theorem atom `f` has a theorem `f_spec` in its `specs` list, that theorem is automatically designated as the primary spec. The `@[primary_spec]` attribute always takes precedence over the heuristic.

## Requirements

- [ ] For each non-theorem atom `f` that has no attribute-based `primary-spec`, check if any entry in its `specs` list equals `f.name ++ "_spec"`
- [ ] If a match is found, set `primarySpec := some matchedName` on the non-theorem atom
- [ ] Also set `isPrimarySpec := true` on the matched theorem atom, so consumers of the JSON don't need to know the source
- [ ] The `@[primary_spec]` attribute always takes precedence: if an attribute-based primary-spec exists for an atom, the heuristic must not override it
- [ ] The heuristic must not override an attribute-based `isPrimarySpec` on theorems (a theorem tagged `@[primary_spec]` stays tagged regardless)
- [ ] Add tests covering the heuristic behavior

## API / Interface Design

No new CLI flags or public API changes. The heuristic is applied automatically inside `computeSpecs` in `ProbeLean/Atomize.lean`.

### JSON output (unchanged schema)

On non-theorem atoms:
```json
{ "primary-spec": "probe:foo_spec" }
```

On the matched theorem:
```json
{ "is-primary-spec": true }
```

## Behavior

### Normal Operation

Inside `computeSpecs`, after building `specsMap` and `primarySpecMap` (from `@[primary_spec]` attributes):

1. For each non-theorem atom `a` that has specs but **no entry** in `primarySpecMap`:
   - Check if `a.name ++ "_spec"` exists in `specsMap[a.name]`
   - If yes, set `primarySpecMap[a.name] := a.name ++ "_spec"`
   - Track the matched theorem name in a set (`heuristicPrimarySpecs`)
2. When producing the final atoms array, for each theorem whose name is in `heuristicPrimarySpecs` and whose `isPrimarySpec` is not already `true`, set `isPrimarySpec := true`

### Precedence

| Condition | Result |
|-----------|--------|
| `@[primary_spec]` attribute set on theorem T for atom A | `A.primary-spec = T`, `T.is-primary-spec = true` (attribute wins) |
| No attribute, but `A_spec` exists in `A.specs` | `A.primary-spec = A_spec`, `A_spec.is-primary-spec = true` (heuristic) |
| No attribute, no `_spec` match | No `primary-spec` set |

### Edge Cases

- **Atom name already ends in `_spec`**: The heuristic would look for `foo_spec_spec`. This is unlikely to match and is harmless — no special handling needed.
- **Multiple `@[primary_spec]` attributes plus heuristic**: The attribute map is built first. The heuristic only fills gaps — it never overwrites an existing `primarySpecMap` entry.
- **Theorem matched by heuristic is also tagged `@[primary_spec]`**: `isPrimarySpec` is already `true` from the attribute; the heuristic is a no-op for that theorem.

## Non-Goals

- Does NOT add new naming conventions beyond `_spec` (e.g., `_correct`, `_lemma`)
- Does NOT make the heuristic configurable or disableable via CLI flags (can be added later if needed)
- Does NOT change the namespace-mismatch cases (e.g., `decompress.step_2` with spec `CompressedEdwardsY.step_2_spec`) — these require a different approach

## Acceptance Criteria

- [ ] A non-theorem atom with a `_spec`-named theorem in its specs gets `primary-spec` set automatically
- [ ] The matched theorem gets `is-primary-spec: true`
- [ ] An explicit `@[primary_spec]` attribute overrides the heuristic
- [ ] Atoms without a `_spec` match remain unchanged
- [ ] Theorem atoms already tagged `@[primary_spec]` are not affected
- [ ] Tests in `Tests/Main.lean` cover: heuristic match, attribute precedence, no match, already-tagged theorem

---
Status: draft
