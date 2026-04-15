# Feature: Improved Primary Spec Detection

## Summary

Improve `computeSpecs` to detect primary specs through a multi-signal precedence chain, replacing the single `_spec` suffix heuristic. The new chain uses: (1) explicit `@[primary_spec]` attribute, (2) known verification-framework attributes (`@[progress]`, `@[pspec]`, `@[step]`), (3) `_spec` suffix naming convention, and (4) sole-spec inference. A centralized `primarySpecAttributes` constant keeps framework-specific knowledge in one place.

## Requirements

- [ ] Add a `primarySpecAttributes` constant listing known spec-indicating attributes: `["progress", "pspec", "step"]`
- [ ] For each non-theorem atom without an attribute-based `primary-spec`, apply the following precedence chain:
  1. **Known-attribute boost**: if exactly one theorem in `specs` carries an attribute from `primarySpecAttributes`, designate it as primary spec. If multiple match, skip this signal (ambiguous).
  2. **`_spec` suffix**: if a theorem named `<atom>_spec` exists in `specs`, designate it as primary spec.
  3. **Sole spec**: if the atom has exactly one theorem in its `specs` list, designate it as primary spec.
- [ ] `@[primary_spec]` always takes precedence over all heuristic signals
- [ ] Set `isPrimarySpec := true` on matched theorem atoms so consumers don't need to know the source
- [ ] The heuristic must not override an attribute-based `isPrimarySpec` on theorems
- [ ] Add tests covering each signal and the precedence interactions

## API / Interface Design

No new CLI flags or public API changes. The heuristic is applied automatically inside `computeSpecs` in `ProbeLean/Atomize.lean`.

### New constant in `ProbeLean/Atomize.lean`

```lean
/-- Attributes from verification frameworks that indicate a theorem is a
    primary specification. Used as a signal in primary-spec detection.
    Precedence: @[primary_spec] > known-attribute > _spec suffix > sole-spec. -/
def primarySpecAttributes : List String :=
  ["progress", "pspec", "step"]
```

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

Inside `computeSpecs`, after building `specsMap` and `attrPrimarySpecMap` (from `@[primary_spec]` attributes), for each non-theorem atom `a` that has specs but **no entry** in `primarySpecMap`:

1. **Known-attribute boost**: scan `specsMap[a.name]` for theorems whose `attributes` array contains any entry from `primarySpecAttributes`. If exactly one such theorem exists, set it as primary spec. If zero or more than one match, continue.
2. **`_spec` suffix**: check if `a.name ++ "_spec"` exists in `specsMap[a.name]`. If yes, set it as primary spec.
3. **Sole spec**: if `specsMap[a.name]` contains exactly one theorem, set it as primary spec.

Each signal only fires if no earlier signal produced a result for that atom.

### Precedence Table

| Condition | Result |
|-----------|--------|
| `@[primary_spec]` attribute set on theorem T for atom A | `A.primary-spec = T` (attribute wins, always) |
| No attribute; exactly one spec has `@[progress]` | `A.primary-spec = that spec` (known-attribute boost) |
| No attribute; two specs have `@[progress]` | Ambiguous — fall through to `_spec` / sole-spec |
| No attribute; no known-attr match; `A_spec` exists in specs | `A.primary-spec = A_spec` (suffix heuristic) |
| No attribute; no known-attr match; no `_spec`; exactly one spec | `A.primary-spec = that spec` (sole-spec) |
| No attribute; no known-attr match; no `_spec`; 0 or 2+ specs | No `primary-spec` set |

### Edge Cases

- **Atom name already ends in `_spec`**: The suffix heuristic looks for `foo_spec_spec`. Unlikely to match, harmless — sole-spec may still fire.
- **Multiple `@[primary_spec]` attributes plus heuristics**: The attribute map is built first. Heuristics only fill gaps — never overwrite.
- **Theorem matched by heuristic is also tagged `@[primary_spec]`**: `isPrimarySpec` is already `true`; heuristic is a no-op.
- **Known-attribute theorem also matches `_spec` suffix**: Known-attribute fires first, `_spec` is skipped for that atom.
- **Sole spec theorem has `@[progress]`**: Known-attribute boost fires (it's exactly one match), sole-spec is never reached. Same result either way.
- **Attributes array needs to be available in `computeSpecs`**: The function already receives the full `Atom` array which includes `attributes`. No new data plumbing needed.

## Non-Goals

- Does NOT make `primarySpecAttributes` user-configurable (can be added later via `.verilib/probes/config.json` if needed)
- Does NOT change `specs` list computation (reverse dependency edges) — only `primary-spec` selection
- Does NOT address namespace-mismatch cases (e.g., `decompress.step_2` with spec `CompressedEdwardsY.step_2_spec`) — these require a different approach
- Does NOT change verification-status assignment for defs

## Acceptance Criteria

- [ ] `primarySpecAttributes` constant exists and is the single source of truth for known spec attributes
- [ ] Known-attribute boost: a def with one `@[progress]`-tagged spec gets `primary-spec` set
- [ ] Known-attribute ambiguity: a def with two `@[progress]`-tagged specs falls through to suffix/sole-spec
- [ ] `_spec` suffix: still works as before (existing tests pass)
- [ ] Sole-spec: a def with exactly one spec (no attribute match, no suffix match) gets `primary-spec` set
- [ ] `@[primary_spec]` attribute overrides all heuristics
- [ ] Atoms without any spec remain unchanged
- [ ] Tests in `Tests/Main.lean` cover: each signal individually, precedence between signals, ambiguity fallthrough, interaction with `@[primary_spec]`

---
Status: ready
