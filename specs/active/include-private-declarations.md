# Feature: Stop Filtering Human-Written Private Declarations

## Summary

`isInternalName` (`ProbeLean/Analysis.lean:36`) drops every `private` declaration
because Lean stores `private def Bar.foo` in module `M` as `_private.M.0.Bar.foo`
(`Lean/PrivateName.lean`, `mkPrivateNameCore`), which trips the `str.startsWith "_"`
rule. Private lemmas/defs are human-written proof artifacts: they can carry `sorry`s
and spec attributes, and public theorems depend on them. Filtering them removes real
atoms and drops dependency edges, which corrupts the `transitively-verified` BFS.

Fix: un-mangle private names with `Lean.privateToUserName` *before* the heuristics,
so real private lemmas survive (`Bar.foo`) while private compiler helpers are still
filtered (`_private.M.0.Bar.foo.match_1` → `Bar.foo.match_1`). Publish private atoms
and their edges under the recovered name.

## Requirements

- [ ] `isInternalName` judges a private name by its `privateToUserName` form, not the mangled name.
- [ ] Private compiler helpers (`match_`, `proof_`, eqn/struct suffixes) are still filtered.
- [ ] Private atoms and every edge pointing at them use the recovered user name in the `name` and `probe:` id — applied consistently at `getProjectDecls` (line 359) and `isProjectDep` (line 461).
- [ ] `transitively-verified` propagates contamination through restored private helpers (verify, no change expected in `Transitive.lean`).
- [ ] `Tests/Main.lean` covers: private name recovered (not filtered), private helper still filtered, naming round-trip.

## API / Interface Design

No CLI or schema changes. Apply one helper at both sites:

```lean
def isInternalName (name : Name) : Bool :=
  let name := Lean.privateToUserName name  -- recover user name first
  let str := name.toString
  str.startsWith "_" || ...
```

Private decls then appear as ordinary atoms, e.g. `{ "name": "Bar.foo", "ref": "probe:Bar.foo" }`.

## Behavior

- `getProjectDecls` no longer skips private decls; atom `name` is the recovered name.
- `isProjectDep` keeps edges to private decls, targeting the recovered name.
- Private constructors/recursors stay filtered via the existing `.ctorInfo`/`.recInfo` match.

## Non-Goals

- No `private: true` marker field on atoms (consider in planning).
- No change to `protected` decls (never mangled, never filtered).
- Heuristics stay non-configurable.

## Acceptance Criteria

- [ ] A human-written private decl appears as an atom under its user-facing name.
- [ ] A public theorem proved via a private helper lists that helper in its dependencies.
- [ ] Private compiler helpers are still filtered.
- [ ] A `sorry` in a private helper contaminates its public dependents' `transitively-verified` status.
- [ ] Tests pass; README/SCHEMA noted if observable output changes.

## Open Questions

1. Cross-module collisions: two private decls recovering to the same user name — qualify by module, or accept?
2. Expose `private` on atoms, or is the recovered name enough?

---
Status: draft
