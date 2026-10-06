# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.16.0] - 2026-10-06

### Added

- **`"status-origin": "kernel-taint"` on tainted atoms** (#117, hub ADR-006). Every atom that reads `verified` because the kernel walk reaches an unexcused project `sorry` from it now carries this marker. The emitted graph can lack the path, for example through a range-less carrier or a `def`'s abstracted `f._proof_1`. A consumer that re-derived statuses from the graph then promoted such atoms or their callers.
- The marker is also emitted under `--skip-enrich`. There it is the only field that separates a tainted `verified` from a capped clean one.
- Hub probe accepts probe-lean extracts for re-enrichment from this version. Re-extract artifacts made by older versions.
- The `UnifiedAtom` reader rejects a `status-origin` value other than `"kernel-taint"` instead of reading it as absent.
- The example fixture now has a marked atom, and its clean atoms read `transitively-verified` as in a default-mode extract.

### Changed

- `tools/audit/check-status-consistency.py` checks the `status-origin` marker against the `check-axioms` report. If the report has no tainted header, or lists a different number of lines than the header states, the check fails.
- `docs/schema.md` is a field reference again (about 260 lines, from 625), with one atom-field table. The audit-level detail moved to `docs/verification-status.md`: sorry attribution per toolchain, cross-checks, executable bodies, coverage of P, merged declarations and the trust rules. The fold detail moved to a companion document, now the "Auxiliary-dependency folding" section of `docs/schema.md`. The Schema 1.x change list, the package version survey and the Verus kind comparison went to an archive that is no longer in the tree. No output format change.
- Docs now match the code: `is-relevant` is `true` for every atom unless `relevant-crate` is configured, `package-version` reads `lakefile.toml` only, and the `viewify` molecule `rust-*`/`spec-*` fields are placeholders. `externally_verified` appears in `attributes` from the tag set or the header scan. The `*-external` arrays hold direct edges only. `--skip-verify` withholds statuses but the kernel walk still runs, and the walk costs about a second on dalek.

### Fixed

- **The walk counts the structure behind a projection as an edge.** On Lean ≤ 4.33, `Expr.getUsedConstants` drops a projection's structure name. With a trusted operand the walk never expanded the operand, so `theorem t : P := x.1` with `axiom x : S` and `S`'s constructor resting on `sorry` read `transitively-verified`. The dependency arrays do not change. The tainted sets of dalek (112) and SPQR (146) do not change.
- **`kind` reports classes and instances from Lean's registries** (#111). Every class was emitted as `structure`. `instance` came from an `inst` name prefix, so `instance fooNat` or an `attribute [instance]` promotion read `def`, and `def instLike` read `instance`. Remaining limit: an `attribute [instance]` issued from a different module than the declaration is not seen.
- **Merged declarations no longer take their atom from the kept body.** Before, `--module Merge.Good` emitted nothing for a `shared` theorem the importer attributed to `Merge.Bad`. Also, `shared` read `unverified` while its edges showed only the proved body.
  - A merged name's dependency arrays are the union of every version's edges.
  - If any selected declaring module registers a declaration range for the name, the atom is emitted. It is located in the first such module.
  - A selected caller's edge to it is a project edge (`term-dependencies`, not `term-dependencies-external`).
  - For a name shared with a dependency that the project owns, the arrays are the project version's. A name the dependency owns is still not an atom.
  - On dalek and SPQR the atom sets and dependency arrays are identical to `main`. Three SPQR atoms lose a `primary-spec` that the old scan read from a docstring.
- `docs/schema.md` described the `*-dependencies-external` arrays as non-project names. They are names outside the module filter, which under `--module`/`--library` includes the project's own unselected modules.
- If the import fallback's selection import also fails, the error now includes the full import's diagnosis (collision list or part-less module). Under `--module`/`--library`, the fallback absorbs a part-less or stale module of an unselected library outside the selection's import closure instead of aborting. The docs now say so.
- `check-status-consistency.py` read an escaped name with a space (`«bad name»`) as `«bad` and failed. It now matches the `[direct]` and `[not emitted]` flags from the end of the line.

## [0.15.0] - 2026-10-06

### Fixed

- **`verification-status` is decided by the kernel and is sound with respect to the project's own `sorry`s** (#87, #103). Before, build-log `sorry` warnings seeded `unverified` and a reverse BFS over the emitted `dependencies` upgraded the rest. That trusted every dependency missing from the atom map, so a range-less carrier (SPQR's `Map.Insts…Iterator` instance) made everything above it read clean.
- `extract` now runs a reachability walk to `sorryAx` over every constant of every built project module, whatever `--module`/`--library` selects, non-atoms included. The walk stops at the project boundary (Lean and every dependency package are trusted) and at trusted project declarations.
- Statuses: `trusted` if trusted. `unverified` if the declaration's own type or value names `sorryAx`. `verified` if an unexcused project `sorry` is reachable. `transitively-verified` otherwise.
- One rule set in `ProbeLean/Trust.lean` decides trust for `trusted-reason`, the walk and `check-axioms`. The precedence is `axiom`, then membership in the `externally_verified` tag set, then a non-proof in a `*External` module.
- Attribution follows the kernel constant. On Lean ≤ 4.28 a `def`'s sorried proof obligation sits in `X._proof_N`, so `X` reads `verified`. From Lean 4.29 the `sorry` stays inline and `X` reads `unverified`. Against a 0.14 artifact this is an `unverified → verified` move.
- Companions such as `X.mvcgen_spec` get their own status. A companion of a trusted theorem reads `transitively-verified`, not `trusted`.
- Statuses join atoms by Lean `Name` before names become `probe:…`, so private-name collisions no longer swap statuses (partially addresses #88).
- The old graph BFS and the build-log parser stay as cross-checks and never change a status. They print `Divergence(graph): …`, a `Graph cross-check: <n> atom(s) …` summary and `Divergence(log): …` lines on stderr. The log check skips trusted atoms.
- `--skip-verify` emits no status except `trusted`. `--skip-enrich` caps clean atoms at `verified`.
- If the full module set cannot be co-imported under a selection, the walk covers the selected modules and every project module they import. `extract` prints `Warning: <n> project module(s) not imported (full import failed); …`.
- A trusted declaration whose statement names `sorry` directly is reported. An atom the walk never saw gets no status and a `Warning: atom … not a project constant the kernel walk covered` line.
- **`@[externally_verified]` is read from the olean tag set, not from source text** (`ProbeLean/TagSet.lean`). The reader runs no target initializer. An `attribute [externally_verified] foo` command and a tag on a range-less constant now count. A declaration that only shares a tagged declaration's range (a derived instance, a companion) is no longer trusted.
- The source scan still fills `attributes`. It now strips comments, strings and `«…»` identifiers, reads only the header, and no longer looks at the two lines above a declaration's range. Some atoms lose attributes that came from docstrings or string arguments.
- A tag audit prints `Divergence(tag): …` for a header that shows the tag while the tag set lacks it. It prints `Note(tag): …` for a tag the header does not show. It also prints `externally_verified tag set: <n> name(s) from <extension>`. A registration the reader does not understand leads to under-trust, never over-trust.
- **The `*External` rule excludes proofs, not only theorems.** Theorems and Prop-typed declarations in a `*External` module get their normal status. Every other declaration there is trusted as a model, whatever its type, including `def e : Empty := sorry`.
- **The trusted base is visible.** `check-axioms` lists T after the tainted list: each trusted constant with its reason, its module and, for a rule-3 model, its statement.
- Both commands print one `Note(axiom): <n> generated project axiom(s) trusted by rule 1 …` line. It names the generated axioms that are not source-visible, for example the `X._native.native_decide.ax_N` axioms that `native_decide` adds since Lean 4.31. These stay trusted (#109): Lean's compiler is part of the trusted base. Known gap: a project `@[implemented_by]`/`@[extern]` body is unchecked code, so a wrong one can make `native_decide` prove a false statement.
- Both commands print `Note: <n> imported module root(s) outside the project are trusted wholesale …`. This includes a second Lake package that holds project code. Move such code into the main package to have it analysed.
- **Merged declarations fail closed.** If two project modules restate a theorem, Lean's importer keeps one proof. The walk now follows the union of all versions from the environment header. A `sorry` in any version makes the name `unverified` and every caller `verified`, and rule 2 never applies. `extract` and `check-axioms` print `Warning: <n> declaration name(s) are declared by more than one project module …`. Lean-realised equation and congruence theorems get a `Note:` line instead.
- A module-system olean with a missing `.olean.server` or `.olean.private` part aborts the extraction before the import. A def/def collision between module-system modules is found at import time and goes to the fallback, not the preflight message.
- **Kernel dependencies, not executable bodies.** A `sorry` in a `partial def` body (`X._unsafe_rec`) or in an `@[implemented_by]` target does not taint the host. The log cross-check prints `Note(log): …` for it. `docs/verification-status.md` describes this.
- A project theorem that restates a dependency's theorem was still fail-open. The walk now follows the project's own versions, so a sorried restatement makes the name `unverified` and its callers `verified`. `@[externally_verified]` on such names is not honoured. They are reported as `Note: <n> declaration name(s) are declared by a project module and by a module outside the project …`.
- **A stale orphan olean that the import loads aborts the extraction.** Such a module was outside P and shielded a `sorry`. `extract` and `check-axioms` abort with `<n> stale module(s) with no .lean source were imported by a live module: …; run \`lake clean\` in the target project and rebuild`.
- The reachability core no longer misses a `sorry` depending on root order (#103).
- Rule 3's Prop test catches heartbeat and recursion-limit exceptions per candidate, so it fails closed instead of aborting `extract`.
- Measured against 0.14.0 on Lean 4.31. curve25519-dalek-lean-verify: atom set and dependency arrays identical, 3 atoms move `trusted → transitively-verified` (two `.mvcgen_spec` companions and `externallyVerifiedAttr`), 15 atoms lose attributes, `extract` 24% faster. SparsePostQuantumRatchet-verify: the 146 tainted constants match SPQR's own `sorry-manifest.txt`, 31 atoms move `transitively-verified → verified`, 10 atoms lose attributes, `extract` 11% faster.
- A narrow `--module` selection is slower (+1.2 s on dalek), because the walk imports every built project module.

### Changed

- **`check-axioms`** runs the same pass as `extract`. It lists every project constant that rests on an unexcused project `sorry`, marks `[direct]` carriers and `[not emitted]` constants, then lists T. It no longer walks dependency packages and takes under a second. `-m`/`-l` only decide the `[not emitted]` marker.
- The `*External` trust rule keys on the module name (`Pkg.FunsExternal`) instead of the source path.
- The orphan-dependency warning reads `… not found in atom map (graph cross-check only; status comes from the kernel walk)`.
- `extract` prints `Project constants: … | trusted: … | direct sorry carriers: … | tainted: …` and `Direct sorry carriers (kernel): n of m atoms`. The `Verified: n/m declarations` line is gone.
- `docs/schema.md` gained a "Verification status and the trusted base" section.
- `tools/audit/compare-extract.py --status-policy taint` accepts this release's status moves and reports each move by kind. `--exec-hosts NAME,...` excuses the clean-ward move of executable-body hosts and of atoms whose old `dependencies` reached one.
- New `tools/audit/check-status-consistency.py ARTIFACT check-axioms.out` asserts that the artifact and the report agree in both directions on every emitted atom. CI runs it on the fixtures.
- The per-constant passes are faster. Module names are fetched once and the walk no longer copies its memo on each SCC. `mkProjectFilter` uses a hash lookup, and `projectConstants` reads only the project modules' constants. The whole pass stays under a second on dalek.

### Removed

- The dead `proofs` vocabulary: `VerifyStatus`, `ProofEntry`, `ProofsOutput` and `atomToProofEntry`. `SorryInfo` and the log parser stay for the build-log cross-check.
- Dead code: `Analysis.readFileLines`, `getModuleName`, `getProjectDecls`, `AxiomCheck.sorryReachingNames`, `dependsOnSorryAxIn`, `isDirectSorryCarrier`.

## [0.14.0] - 2026-09-15

### Fixed

- **Dependency edges hidden under auxiliary constants are now recovered** (#99). Lean
  abstracts non-atomic embedded proofs and match arms into constants probe-lean filters out
  of its output (`X._proof_N`, `X.match_N`, tactic-generated helpers), and nothing folded
  their dependencies back into the declaration that referenced them — so every edge
  underneath an auxiliary was lost. A `sorry`-carrying lemma discharged inside a `by` block
  left its caller with no edge to it and a clean `transitively-verified` status; a reporter
  who trusted an in-degree of 0 to prune unreferenced `Math` declarations from a bundle
  broke `lake build`. Measured on a freshly built curve25519-dalek-lean-verify (2354 atoms):
  191 atoms lost at least one project-internal edge, 565 project edges were dropped, 62
  project theorems looked unreferenced while being used, and 6 atoms carried a wrong clean
  `verification-status`.

  `extract` now traverses each non-emitted auxiliary and appends the project constants it
  reaches to the referencing declaration's `term-dependencies`. The pass is strictly
  **additive**: it never adds to `type-dependencies`, never removes an entry from any of the
  four dependency arrays, never adds to the `*-external` arrays, and never changes the atom
  set. Edges to emitted project axioms, inductives, structures and classes, and direct
  external anchors, are therefore untouched by construction. `dependencies` is now derived as
  the union of the two arrays, which is what keeps its documented contract true.
  `docs/schema.md#auxiliary-dependency-folding` is the single statement of the contract.

  Every recovered edge lands in **`term-dependencies`**, including one found under an
  auxiliary named in the declaration's *type*. `type-dependencies` is left exactly as it
  was, so *type-driven* spec selection cannot move: `specs` / `primary-spec` are normally
  computed from `type-dependencies`, and a constant reached only through an instance's
  implementation is not something a statement specifies. (An earlier revision routed
  type-position reach into the type bucket; on dalek it pushed 14 implementation constants
  into four theorems' `type-dependencies` and detached one atom's `primary-spec`.) It is not
  a blanket "`specs` cannot change" guarantee: the `@[primary_spec]` fallback for a theorem
  whose statement names nothing specifiable walks the union `dependencies`, so a folded term
  edge can still detach such a tag — covered by a unit regression. Since `dependencies` is
  the union of the two buckets, verification-status propagation sees every recovered edge.
  The trade-off, stated in `docs/schema.md`: a folded entry in `term-dependencies` is
  *indirect* — the array holds what the declaration reaches through eligible auxiliaries in
  either the type or the body, not only what the body names.

  Deliberately out of scope, each a follow-up: structural members of a type (`.mk`,
  `.injEq`, `.casesOn`, and the equation lemmas `.eq_1`–`.eq_3`/`.eq_def` the suffix list
  actually names) are not folded through; external targets are not folded
  (a single `by omega` drags in ~50 `Lean.Omega.*` constants, and folding all external
  targets would add ~49k entries on a dalek-sized project), which makes the `*-external`
  arrays abstraction-sensitive — `host → anchor` is listed, `host → aux → anchor` is not.

  This fixes **edges, not status soundness**: propagation still has no "unknown" state, so a
  dependency the graph is missing for any other reason is still treated as trusted. And it
  is compiled-environment reachability only — a zero in-degree remains no licence to delete
  a declaration, since notation, macros and elaboration-time instances leave no surviving
  constant reference. See `docs/schema.md#auxiliary-dependency-folding`.

  **Output impact**, measured on curve25519-dalek-lean-verify (2354 atoms, Lean 4.31.0)
  against the immediately preceding build:

  - 575 dependency edges recovered across 157 atoms, all in `term-dependencies`. This is
    **not** comparable with the 565 above: that baseline traverses only name-filtered
    auxiliaries, while the shipped fold excludes structural members but additionally folds
    through project members with no declaration range (Aeneas's `*_loop.mutual` helpers, for
    instance), which the baseline never visited. Neither number is a subset of the other —
    see `tools/audit/README.md`;
  - 65 atoms went from in-degree 0 to non-zero — the class the reporter pruned;
  - 6 atoms moved from `transitively-verified` to `verified`, and they are exactly the 6
    the independent taint audit (`tools/audit/Audit2.lean`) names, by identity: the
    `select_loop_spec`, `from_loop_spec` and `mul_loop_spec` trio plus their
    `.mvcgen_spec` companions;
  - **zero** `specs` / `primary-spec` changes, and `type-dependencies` byte-identical on
    every atom. The type bucket is unchanged by construction; the absence of `specs` changes
    is a property of this corpus, because the `@[primary_spec]` fallback walks the union
    `dependencies` and can detach a tag on a project that relies on it — there is a unit
    regression for that path, and `tools/audit/compare-extract.py` now asserts the
    type-bucket invariant rather than only reporting it.

  Cost on the same project: extract wall-clock 8.87 s → 8.69 s (steady-state means of three
  runs — within noise; the agreed gate was ≤5% or ≤2 s), peak RSS +0.03%, clean `lake build`
  23.8 s → 25.5 s. The traversal made 4653 node expansions, scanned 349k edges, and cached
  4653 closures holding 6208 names — and **0 cycle suppressions**, i.e. this corpus never
  exercised the cycle rules, which are covered by unit tests only. The `Auxiliary fold:`
  line reports that counter so a future target project shows whether the cyclic path is
  live.

### Added

- **`tools/audit/`** — the measurement scripts behind the #99 numbers, with a README
  covering what each one measures, how to run it against a target project, and the baseline
  figures it produced. They run under the *target* project's toolchain, duplicate five
  helpers on purpose so the oracle stays independent of the code it checks, and are reusable
  on any project.

- **`tests/fixtures/aux-fold/`** and a CI step that extracts it. The check asserts the
  *precondition* — that the auxiliary exists and the edge really is hidden behind it —
  because whether Lean abstracts a proof obligation is elaborator-dependent, and without
  that assertion the test silently degrades into checking a direct dependency that was never
  lost.

## [0.13.0] - 2026-09-10

### Added

- **`is-primary-spec` is now emitted on every atom, and `extract` warns about ambiguous
  `@[primary_spec]` tags.** Both `fromJson` implementations already read the field and
  neither `toJson` wrote it, so it silently round-tripped to `false`. It records whether a
  declaration is *tagged*, not whether it *won*: a theorem the heuristic signals pick as
  some target's `primary-spec` reads `false` unless it is tagged too, and a tagged
  non-theorem reads `true`. Intersecting a target's `specs` with the flag recovers the
  tagged candidates. When two or more tagged theorems resolve to the same target, the
  winner is an arbitrary tie-break; `extract` now prints one stderr warning per affected
  target naming the winner and the rejected candidates. Exit codes and `schema-version`
  are unchanged, and no declaration changed which flags it carries. Because the boolean is
  always present, every atom gains a key — extract artifacts will show a whole-file diff
  against an older run even for projects with no ambiguity.

- **Pinned extra Lean versions in the release matrix** (`tools/lean-version-extras.txt`).
  The derived version policy stops shipping an RC once its stable lands, but real target
  projects sit on superseded RC toolchains for months (Mathlib cuts releases against RCs),
  and for such a toolchain the installer would silently serve the *old* probe-lean release
  that last shipped the RC asset — on teorth/analysis (`v4.29.0-rc8`) that meant v0.9.4,
  which predates the #94 fix. Versions listed in the extras file are now built and released
  alongside the derived set. A pin is a promise to ship an asset, so every bad entry is a
  hard error rather than a silent drop: malformed or non-canonical spelling, below the
  version floor, not a published (non-draft) Lean release, or no compatible lean4-cli tag.
  Ships `v4.29.0-rc8` as the first pin. The version-policy and installer-helper test
  suites now run in CI and gate auto-tagging, and the lean-watch coverage loops abort
  loudly when version derivation fails instead of reporting an empty (or fully covered)
  set.

### Fixed

- **The example extract artifact is now generated and guarded against staleness.**
  `examples/lean_Curve25519Dalek_0.1.0.json` was a 2.6 MB real artifact from tool version
  `0.4.5` that had been hand-patched rather than regenerated ever since — the codomain
  facts were added with 8 inserted lines, leaving `codomain-is-prop` on 3 of 1539 atoms
  where the serializer emits it for every atom. Nothing caught the drift: five test
  functions read the file but skipped silently when it was absent, and the
  `probe-extract-check` CI job tolerates missing optional fields. It is replaced by
  `examples/lean_ExampleProject_0.1.0.json`, an 8 KB fixture written by
  `tools/gen-fixture.sh` through probe-lean's own `Envelope` / `UnifiedAtomsOutput`
  serializers, so the committed file stays genuine tool output. CI regenerates it and
  fails on any diff, and a missing fixture is now a test failure rather than a skip. Any
  output-format change must be accompanied by re-running the script.

- **P14 determinism assertion no longer passes vacuously.** Regenerating the fixture
  revealed that emitted JSON object keys are *descending*, not ascending: `Json.mkObj`
  is `Std.TreeMap.Raw.ofList`, which orders by key regardless of insertion order, and
  `Json.pretty` then renders that map reversed. The old fixture predated this behaviour,
  so the test asserting ascending `data` keys was only green because the artifact was
  stale. Output remains byte-deterministic across runs, which is what P14 requires, so
  the assertion now checks that key order is a consistent function of the keys rather
  than a particular direction. The `qsort` in `AtomsOutput.toJson` and
  `UnifiedAtomsOutput.toJson` was dead code with respect to the emitted JSON and has
  been removed — verified by regenerating the fixture byte-identically without it.

## [0.12.1] - 2026-08-17

### Fixed

- **`extract` no longer aborts on modules whose file name needs guillemets** (#94).
  Module names were derived from olean paths with `String.toName`, which mangles
  any non-identifier segment: segments with hyphens or spaces collapse the whole
  name to `.anonymous`, and digit-only segments become numeric components — both
  invalid as module names. `importModules` then rejected the import list with
  `import failed, trying to import module with anonymous name`. This crashed the
  flagless invocation (the one VeriLib's atomizer uses) on e.g. teorth/analysis,
  whose `Analysis.Misc.«Real-EReal-ENNReal»` is a legal Lake module. With
  `--library` the anonymous name was silently dropped from the import list instead,
  so such a module's atoms survived only if another module imported it. Names are
  now built one atomic component per path segment (`pathToModuleName`) — the same
  construction Lean core's `moduleNameOfFileName` uses — which represents guillemet
  components exactly in both modes.
- **Declarations in guillemet-named modules regain source locations and
  verification status** (#94). `getModuleSourcePath` rebuilt the source path by
  string-replacing dots in `Name.toString`, producing guillemet-quoted paths
  (`Misc/«Real-EReal-ENNReal».lean`) that never exist on disk. Every declaration
  in such a module therefore lost its `code-path`/`code-text`, its source-level
  attributes, and — because sorry matching needs the location — was conservatively
  reported `unverified` even when fully proved (17 such atoms on teorth/analysis).
  The path is now rebuilt component-wise (`moduleNameToRelPath`, the exact inverse
  of `pathToModuleName`).

## [0.12.0] - 2026-08-07

### Fixed

- **Theorem `term-dependencies` are populated again on Lean ≥ 4.30.** `getDependencies`
  read a constant's value through `ConstantInfo.value?`, which in Lean 4.30 started
  gating theorem proofs behind `allowOpaque := true`. Because the flag has a default,
  the change was source-compatible: probe-lean kept compiling, and every release built
  against Lean 4.30 or later silently emitted `"term-dependencies": []` for **every**
  theorem. The proof graph was absent from the artifact and from the web UI, and
  because `verification-status` is propagated over that graph, theorems resting on a
  `sorry` were upgraded to `transitively-verified`. Restoring the proof edges removes
  a class of these false upgrades (those whose `sorry` path runs through an emitted
  declaration); the residual case is the known limitation under Changed below.
  `valueOf` now reads `.defnInfo`/`.thmInfo`/`.opaqueInfo` values by direct field
  match, so no future default change can empty them again, and a regression test built
  on hand-made `ConstantInfo`s fails if they ever come back empty.
  Repos pinned to Lean ≤ 4.29 (this one included) were unaffected locally, which is
  why CI stayed green while released binaries were broken.
- **`opaque` bodies now contribute dependencies.** `valueOf` reads the same value
  fields (`.defnInfo`/`.thmInfo`/`.opaqueInfo`) that `AxiomCheck.constChildren` and
  `Lean.collectAxioms` read; previously `value?` dropped `opaque` bodies on every Lean
  version. Note this restores a better *syntactic* edge set (`Expr.getUsedConstants`),
  not a kernel-closure taint proof — see the known limitation under Changed below.
- **`specs` no longer includes theorems that merely mention an atom in their proof.**
  Reverse spec edges are now derived from `type-dependencies` rather than the
  `dependencies` union: a theorem specifies what its *statement* is about. Without
  this, restoring proof edges would have attached a spurious spec to most definitions
  in a project and defeated primary-spec detection, whose known-attribute and
  sole-spec signals both require exactly one candidate. Exception: a theorem
  explicitly tagged `@[primary_spec]` whose statement names no specifiable constant
  falls back to the union when that leaves exactly one candidate, so the user's
  override still attaches. Several candidates make the tag ambiguous (it marks the
  theorem, not a target): nothing attaches, same as an untagged abstract theorem.
- **The environment import level is pinned.** `importModules` relied on the
  defaulted `level`, whose current value (`.private`) loads all olean data, theorem
  proofs included; the exported level can present module-system theorems without
  proofs, which downstream status propagation would silently trust. That is the
  same defaulted-upstream-flag failure shape as `value?`, so the level is now
  spelled out at the call site.
- **The test suite now runs where the original bug shipped from.** CI gains a job
  that runs the tests on the newest supported Lean toolchain (the pinned dev
  toolchain alone could never catch a Lean-version-dependent regression), and the
  release and lean-watch matrices run the suite before packaging — a toolchain row
  with failing tests produces no artifact.

### Changed

- **`dependencies` (the type+term union) changes contents, not shape.** Because
  `valueOf` restores theorem proof-term edges (empty on Lean ≥ 4.30 releases) and adds
  `opaque` bodies on all versions, a declaration's `dependencies` now covers more of
  the reachability graph. Consumers that walk this field see additional edges; the
  field is still the deduplicated union of `type-dependencies` and `term-dependencies`.
- **`extract` is substantially faster** on large projects, so restoring the proof
  graph is a net speedup despite the extra edges. Project
  membership was decided by resolving a constant's module name and building a
  `"Module."` string per candidate module — run over every constant in the
  environment, Mathlib included. It is now a precomputed set of module indices behind
  `ProjectFilter`, and each dependency list is partitioned into project/external in
  one pass instead of being filtered five times.
- Note the speedup is runtime only: restoring per-theorem proof edges (and their
  `*-external` counterparts) grows the emitted artifact, since every theorem now
  carries its proof-term dependencies. Runtime and artifact size move in opposite
  directions here.
- Known limitation: some declarations can still be reported `transitively-verified` while resting on a
  `sorry`. The known instance in SPQR is downstream of the `Map.Insts…Iterator` trait
  instance whose `next` field SPQR's `aeneas-config.yml` replaces with `sorry` (a
  workaround for aeneas#1043). Aeneas declares it with its `impl_def` command, whose
  elaborator never calls `addDeclarationRanges`, so it has no source range, so
  probe-lean drops it and then treats the missing dependency as trusted. A node that
  is never emitted cannot contaminate anything, however complete the edges are.
  Closing this has two tracks: aeneas emitting declaration ranges for `impl_def`
  (AeneasVerif/aeneas#1247), and probe-lean deciding status from the kernel closure
  rather than the emitted dependency graph. Tracked in #87.

## [0.11.1] - 2026-08-06

### Fixed

- **Attribute-macro companion theorems no longer defeat primary-spec detection.**
  Aeneas's `@[step]` elaborates a tagged `theorem X` into an extra machine-generated
  `X.mvcgen_spec` whose declaration range points back at `X`'s own syntax. probe-lean
  treated the companion as a first-class spec: it appeared next to the real spec in
  every dependency's `specs` list and (via the source-scan attribute fallback) carried
  the parent's `@[step]`, so the known-attribute and sole-spec signals — which require
  exactly one candidate — both failed, and fully proved functions ended up with no
  `primary-spec` (downstream, probe-aeneas then colors their Rust implementations
  "unverified"). `extract` now detects such companions — name shape
  `<parent>.mvcgen_spec` with a parent that is a project theorem or external
  (axiom-parented wrappers stay visible: axioms are never collected into `specs`,
  so the wrapper is the axiom's only spec proxy) — flags them `is-aeneas-generated`
  (they exist only because of Aeneas's attribute machinery) + `is-hidden`, and
  excludes generated theorems (`is-lean-generated` or `is-aeneas-generated`) from
  `specs` lists and the heuristic primary-spec signals. The explicit
  `@[primary_spec]` tag remains the escape hatch: it wins primary-spec selection
  even on a generated theorem and re-admits that theorem into `specs`, so
  `primary-spec` never points outside `specs`. Companions stay in the dependency
  graph, so transitive verification is unchanged. New
  `generatedCompanionTheoremNames` in `ProbeLean/Analysis.lean`.

### Changed

- The post-enrichment "unhide contaminated generated atoms" pass now covers
  `is-aeneas-generated` atoms as well as `is-lean-generated` ones, so a hidden
  companion (or config-flagged Aeneas scaffolding) that is not transitively
  verified is surfaced for tracing instead of staying hidden. The pass is now
  skipped under `--skip-enrich`, where contamination is not computable (every
  proved atom still reads `verified`) and all clean generated atoms would have
  been unhidden.

## [0.11.0] - 2026-08-03

### Added

- `check-axioms` command: audits a project and reports every declaration (of those
  `extract` emits as atoms) whose transitive closure reaches the `sorryAx` axiom —
  the kernel ground truth for "rests on a `sorry`", independent of the extract
  dependency graph. Supports `-m`/`-l` scoping. New `ProbeLean/AxiomCheck.lean`.
- Neutral per-atom codomain facts, emitted for every atom: `codomain-head`
  (result-type head constant), `codomain-is-prop`, `codomain-last-arg-is-bool`.
  A downstream tool reconstructs the codomain shape from these plus its own catalogue.
- Neutral per-atom `type-dependencies-external` / `term-dependencies-external`
  fields (non-project deps, absent when empty). The existing `type-dependencies` /
  `term-dependencies` are project-filtered; these carry the external edges a
  downstream classifier needs to reconstruct the full reachability graph.

### Removed

- **Security-protocol (VCVio) classification moved out of probe-lean** into the
  standalone `probe-vcvio` tool. Removed from the `extract` output: the per-atom
  `classification` object and the envelope `source.class` field. Removed from the
  CLI: the `--class` flag. Removed internally: `ProbeLean/Classify/` (the anchor
  catalogue + classifier), the `Classification`/`SecurityProtocolCategory`/`ClassVia`
  types, and project-class/manifest detection. These fields were never part of a
  released schema and had no consumers, so their removal is not a schema break (the
  schema-version stays 3.0). probe-vcvio consumes probe-lean's envelope and
  reproduces the same `classification` shape from the emitted `codomain-*` facts.

### Changed

- **Split `is-extraction-artifact` into `is-lean-generated` + `is-aeneas-generated`.**
  The old field conflated two distinct origins: Lean-generated code
  (derived instances, projections) and Aeneas-generated scaffolding (`_body`, `_loop`
  suffixes). Each now has its own field with accurate naming. No interchange break:
  no other probe consumes these fields (probe-aeneas computes its own
  `is-extraction-artifact` from a name heuristic), so this is an additive payload
  change, not an envelope-schema change.
- **Conditional `is-hidden` for lean-generated atoms.** After transitive enrichment,
  `is-hidden` is cleared on *contaminated* lean-generated atoms — those that are
  locally verified but not transitively verified, or are themselves unverified/failed —
  so consumers that read `extract` output directly (e.g. the web UI) can trace why
  downstream atoms aren't dark green (fully verified). Clean (`transitively-verified`)
  and `trusted` lean-generated atoms stay hidden. `viewify` molecules omit all generated
  atoms regardless of `is-hidden`.
- Schema-version stays 3.0: the envelope structure is unchanged. The
  `is-extraction-artifact` → `is-lean-generated`/`is-aeneas-generated` rename and the
  updated `is-hidden` semantics affect only probe-lean's own payload, which is absorbed
  by consumers' passthrough `extensions`, so no shared version bump is warranted.
- The config key `extraction-artifact-suffixes` in `.verilib/probes/config.json` now
  feeds the `is-aeneas-generated` field (backward compatible, no config migration).
- `extract` auto-flags Lean-generated code — `deriving`-generated instance clusters and
  structure/class projections — as `is-hidden` + `is-lean-generated`, so it is omitted
  from the presented graph (`viewify` drops all generated atoms; `extract` consumers honor
  `is-hidden`). These atoms remain in the dependency graph, so transitive-verification
  stays sound.
- `markAtomFlags` now ORs the `is-hidden` / `is-aeneas-generated` flags with any
  already set, so config-based flagging adds to (rather than overwrites) the automatic
  detection above.
- The four classification tag hooks (`@[scheme_def]`, `@[construction_def]`,
  `@[correctness_spec]`, `@[security_spec]`) remain **registered** in
  `ProbeLean.Attrs` (so target projects need no migration) but are no longer
  interpreted by probe-lean; probe-vcvio reads them from the emitted `attributes` array.

### Fixed

- **Support Lean patch releases when installing and releasing.** `lean4-cli` tags
  `major.minor` lines and RCs but not every patch, so probe-lean previously failed
  to build for a patch-release toolchain (e.g. `v4.32.2`): the source build pinned
  `lean4-cli` to the exact Lean version (`revision not found`) and no pre-built
  binary was published. Both paths now resolve `lean4-cli` to the highest
  compatible tag in the target's `major.minor` line (stable targets pair only with
  stable tags), matching what was previously done by hand. Newly supported:
  patch releases such as `v4.28.1`, `v4.29.1`, `v4.32.1`, `v4.32.2`. (#79)

## [0.10.2] - 2026-08-03

### Fixed

- **Revert extract envelope schema-version to 3.0.** v0.10.1 emitted `4.0` for a
  payload-only change (the `is-extraction-artifact` split and updated `is-hidden`
  semantics), but the shared probe crate gates envelopes on a schema-version starting
  with `3.`, so `4.0` output was rejected by consumers at load time (`probe-aeneas
  extract` failed). The field rename and `is-hidden` behavior are kept; only the
  envelope version marker returns to `3.0`. (#81)

## [0.10.1] - 2026-08-03

### Fixed

- **Support Lean patch releases when installing and releasing.** `lean4-cli` tags
  `major.minor` lines and RCs but not every patch, so probe-lean previously failed
  to build for a patch-release toolchain (e.g. `v4.32.2`): the source build pinned
  `lean4-cli` to the exact Lean version (`revision not found`) and no pre-built
  binary was published. Both paths now resolve `lean4-cli` to the highest
  compatible tag in the target's `major.minor` line (stable targets pair only with
  stable tags), matching what was previously done by hand. Newly supported:
  patch releases such as `v4.28.1`, `v4.29.1`, `v4.32.1`, `v4.32.2`. (#79)

## [0.10.0] - 2026-07-29

### Changed

- Bumped schema-version to 3.0 (breaking) to align with the ecosystem-wide major
  bump for the is-disabled→untracked atom field rename.

## [0.9.6] - 2026-07-17

### Changed

- `extract` enrichment now separates benign references to constructors/fields of
  extracted types (`inductive`/`structure`/`class`) from genuine orphan
  dependencies. Such type-member references are summarised in a single note
  instead of emitting one "not found in atom map" warning each, so real missing
  dependencies are no longer drowned out. Genuine orphans (e.g. instance
  projections, trait-impl references) are still reported individually. New
  `partitionMissingDeps` helper in `ProbeLean/Transitive.lean`.

## [0.9.5] - 2026-07-08

### Fixed

- **Duplicate-declaration failures are now caught by a preflight check with an
  accurate, actionable diagnostic** (issues #61, #62). Projects where two built
  modules declare the same fully-qualified name (e.g. parallel
  `problem.lean`/`solution.lean` files restating definitions without namespaces)
  build fine under Lake but cannot be imported into probe-lean's single analysis
  environment. Previously the mid-import abort blamed a stale orphan `.olean`
  and suggested `lake clean` — a dead end for this case. `extract` now reads each
  module's own declarations from its `.olean` header before importing and, on a
  collision, aborts with the duplicated names and their owning modules, the
  structural fixes, and the exact `--module` escape hatch for manual runs. The
  check replicates the importer's duplicate-tolerance rule (identical-statement
  theorem/axiom restatements are exempt), so it never rejects a project the
  importer would accept; collisions it cannot see (dependency modules,
  module-system split parts, unreadable oleans) still fail at import time with a
  hint that now covers both causes. Module discovery returns `ProjectModule`
  records (name + olean path) so filters preserve the pairing. The
  co-importability requirement is documented under README "Supported Projects".

## [0.9.4] - 2026-06-24

### Fixed

- **`extract` no longer crashes on orphan `.olean` files.** Module discovery scanned
  `.lake/build/lib/lean` for every `.olean` on disk and imported them all into one
  environment. Lake never garbage-collects oleans, so after a `.lean` file was renamed or
  deleted its stale "orphan" olean lingered and — when it re-declared a name now owned by
  the module that replaced it — made the import abort with `environment already contains
  '...'` (issue #51). `getProjectModules` now keeps only modules with a backing `.lean`
  source, resolving each module against `"."` plus every `srcDir` declared in
  `lakefile.toml`. The check is conservative (a module is dropped only when *no* source
  root has its source, so an unknown `srcDir` can't silently drop a live module) and any
  dropped orphans are reported. As a safety net, an `already contains` import failure now
  prints an actionable `lake clean` hint instead of a raw error.

## [0.9.3] - 2026-06-23

### Changed

- **Installer `--from-project` auto-detects the toolchain recursively.** When the given
  directory has no top-level `lean-toolchain` (common in monorepos where the Lean package
  lives in a subfolder, e.g. `cedar-spec/cedar-lean`), both `tools/bash/install.sh` and
  `tools/python/install.py` now search recursively (excluding `.lake`) and use the toolchain
  they find, so the installer works unattended when handed a repo root. If the found files
  disagree on the version, it errors and lists them rather than guessing. Bad paths
  (nonexistent, a file, or a directory with no toolchain anywhere) now give distinct,
  actionable errors instead of the previous terse `lean-toolchain not found`.

## [0.9.2] - 2026-06-22

### Fixed

- **`extract` no longer drops every module when `defaultTargets` names a non-library
  target.** The module filter was derived from auto-detected build targets, but
  `defaultTargets` may name a `lean_exe` and a `lean_lib` may declare custom `roots` that
  differ from its name. Treating those as module-name roots filtered out every built module,
  silently producing `0 atoms`. The library filter is now applied only when the user
  explicitly passes `--library`; otherwise all of the project's built modules (which is
  exactly what `.lake/build/lib/lean` contains) are analyzed. As a safety net, `extract` now
  exits with an actionable error — listing the available top-level module roots — if
  `--library`/`--module` filters out every built module, instead of writing an empty result.

## [0.9.1] - 2026-06-18

### Added

- **Pre-built binaries for Lean `v4.30.0` and `v4.31.0`** in the release matrix.

## [0.9.0] - 2026-06-18

### Fixed

- **Human-written private declarations are no longer filtered out.** Lean stores a
  `private def Bar.foo` as `_private.<module>.0.Bar.foo`, which the internal-name filter
  dropped along with compiler-generated noise. `extract` now recovers the user-facing name
  (`Bar.foo`) before filtering, so private lemmas/defs appear as atoms and dependency edges
  from public declarations to private helpers are preserved. This also fixes
  `transitively-verified` contamination silently skipping `sorry`s carried by private helpers.
  Private compiler-generated helpers (e.g. `...match_1`) remain filtered. Private declarations
  in different modules whose user-facing names coincide (e.g. two top-level `private theorem aux`)
  now emit a duplicate-name warning. (#43)

## [0.8.0] - 2026-06-16

### Added

- **Security-protocol classification**: for VCVio-based cryptographic projects, `extract` now
  classifies each declaration into a `scheme → construction → {correctness, security}` hierarchy
  so a consumer can render an accordion. Two additive, optional fields:
  - envelope **`source.class`** (`"security-protocol"`), resolved by precedence: `--class` override
    > Lake manifest (package-level VCVio dependency) > imported-module signal;
  - per-atom **`classification`** — `{ category, via, scheme?, construction? }`, where `category`
    is `scheme`/`construction`/`correctness`/`security`/`ambiguous`, `via` records the signal tier
    (`attribute`/`type`/`naming`), and the `scheme`/`construction` links are resolved fail-closed.
  Detection cascade is attribute > type > naming; project-own property definitions are promoted to
  anchors; theorems are classified by a bounded reachability walk. `ambiguous` flags a property
  whose correctness-vs-security axis is undecided (equal-depth tie or conflicting tags).
  See `docs/classification-security-protocol.md` (removed in 0.11.0).
- **Classification attributes** (`ProbeLean.Attrs`): `@[scheme_def]`, `@[construction_def]`,
  `@[correctness_spec]`, `@[security_spec]` — authoritative overrides for projects whose schemes or
  properties are not conventionally named.
- **`--class <name>` flag** on `extract`: override the detected project class for manual runs.
- Non-security-protocol projects are unchanged from 0.7.0 apart from `tool.version`/timestamp
  metadata (no class detected → neither `source.class` nor `classification` is emitted).

## [0.7.0] - 2026-05-22

### Added

- **`transitively-verified` status**: Verified atoms whose transitive dependencies
  are all verified or trusted are now upgraded to `"transitively-verified"` via
  reverse-BFS contamination (matching `probe-verus`/`probe-aeneas`). Atoms that
  are locally sorry-free but have at least one unverified or failed transitive
  dependency remain `"verified"`.
- **`--skip-enrich` flag**: Skip the transitive verification enrichment step.
  When passed, no atoms will be upgraded to `"transitively-verified"`.
- **`ProbeLean/Transitive.lean`**: New module implementing the enrichment algorithm
  using `Lean.RBMap` for deterministic iteration and an `Array`-backed BFS queue.

## [0.6.3] - 2026-04-30

### Fixed

- **Stale build cache hit after `lake clean`** ([#15](https://github.com/Beneficial-AI-Foundation/probe-lean/issues/15)):
  `isCacheValid` now requires at least one `.olean` file in the project's build
  directory, not just that the directory exists. Previously, after `lake clean`
  removed `.olean` artifacts (while the cache file at `.lake/probe-lean/build_output.txt`
  and the `.lake/build/lib/` directory survived), `probe-lean extract` would skip
  `lake build` and then fail with "No modules found in project". Added a
  `hasAnyOlean` helper that short-circuits on the first `.olean` found.

## [0.6.2] - 2026-04-16

### Fixed

- **`@[externally_verified]` attribute now recognized by trust-base classification**:
  The attribute was already registered in `ProbeLean/Attrs.lean` but was not wired
  into `trustedReason`, so theorems carrying `@[externally_verified]` (e.g., proofs
  discharged outside Lean in Verus) were reported as `"unverified"` when they
  contained the expected `sorry`. They now get `verification-status: "trusted"`
  with `trusted-reason: "externally_verified"`. Precedence when multiple signals
  apply: (1) `axiom`, (2) `externally_verified`, (3) `external`.

## [0.6.1] - 2026-04-15

### Fixed

- **Theorems in `*External.lean` no longer overridden to trusted**: Previously,
  all declarations in Aeneas `*External.lean` files were blanket-marked as
  `"trusted"` with `trusted-reason: "external"`. This was incorrect for theorems,
  which carry real Lean proofs checked by the kernel. Theorems in these files now
  receive their normal verification status from sorry detection (`"verified"`,
  `"unverified"`, or `"failed"`). Axioms and non-theorem declarations (defs,
  instances, etc.) remain `"trusted"` as before.

## [0.6.0] - 2026-04-15

### Added

- **Improved primary-spec detection**: `computeSpecs` now uses a multi-signal
  precedence chain instead of just the `_spec` suffix heuristic:
  1. `@[primary_spec]` attribute (always wins)
  2. Known verification-framework attributes (`@[progress]`, `@[pspec]`,
     `@[step]`) — if exactly one spec theorem carries one of these, it
     becomes primary spec
  3. `_spec` suffix naming convention (existing heuristic)
  4. Sole-spec inference — if a definition has exactly one spec theorem, it
     is used as primary spec

  A centralized `primarySpecAttributes` constant in `ProbeLean/Atomize.lean`
  lists the known spec-indicating attributes, making it easy to extend for
  future verification frameworks.

## [0.5.0] - 2026-04-13

### Added

- **Nix environment auto-detection**: When a target Lean project ships a
  `shell.nix` or `flake.nix`, probe-lean automatically wraps all `lake`
  invocations inside the Nix environment so that FFI system dependencies
  (zlib, OpenSSL, etc.) are available without manual installation. If the
  Nix file is present but `nix` / `nix-shell` is not installed, a warning
  is printed and `lake` runs directly.
  Fixes [#24](https://github.com/Beneficial-AI-Foundation/probe-lean/issues/24).

## [0.4.8] - 2026-04-10

### Added

- **`projection` declaration kind**: Structure field projections and class method
  projections are now classified as `kind: "projection"` instead of `"abbrev"`,
  using Lean's built-in `env.isProjectionFn` API. This distinguishes compiler-
  generated accessors (e.g., `EdwardsPoint.X`, `Add.add`) from genuine user-written
  abbreviations. Fixes [#19](https://github.com/Beneficial-AI-Foundation/probe-lean/issues/19).

### Changed

- **No-source declarations filtered entirely**: Declarations without source
  location (kernel-synthesized congruence lemmas, mutual recursion helpers, etc.)
  are now filtered from output entirely instead of being marked `"trusted"` with
  `trusted-reason: "auto-generated"`. The `"auto-generated"` trusted reason is
  removed from the schema. Refines the v0.4.6 fix for [#16](https://github.com/Beneficial-AI-Foundation/probe-lean/issues/16).

## [0.4.7] - 2026-04-10

### Fixed

- **Instance kind detection**: Auto-named type class instances (e.g.,
  `instAddNat`, `instDecidableValidLengths`) were incorrectly classified as
  `"def"` or `"abbrev"`. They are now reported as `"instance"` in the JSON
  output. Detection uses a naming heuristic (`inst` prefix) since Lean's
  instance extension state is not preserved in `.olean` files after
  `importModules`. User-named instances (without `inst` prefix) are not
  detected. Fixes [#17](https://github.com/Beneficial-AI-Foundation/probe-lean/issues/17).

## [0.4.6] - 2026-04-09

### Fixed

- **False "unverified" atoms for auto-generated declarations**: Declarations
  without source location (kernel-synthesized congruence lemmas, mutual recursion
  helpers, etc.) were incorrectly marked `"unverified"`. They are now marked
  `"trusted"` with `trusted-reason: "auto-generated"` since they are
  kernel-checked and guaranteed sound. Additionally, `.elim`, `.ctorIdx`, and
  `.toCtorIdx` suffixes are now filtered out as internal noise (like `.casesOn`,
  `.rec`, etc. already were). Fixes [#16](https://github.com/Beneficial-AI-Foundation/probe-lean/issues/16).

## [0.4.5] - 2026-04-07

### Added

- **`trusted-reason` field**: Each trusted atom now carries a `trusted-reason`
  field (`"axiom"` or `"external"`) so downstream tools can classify the trust
  base directly from the extract JSON without inspecting `kind` or `code-path`.

## [0.4.4] - 2026-04-07

### Added

- **Deterministic output (P14)**: `extract` now produces byte-identical JSON
  (ignoring `timestamp`) for the same project, commit, and toolchain.
  Declarations are sorted by name, dependency/specs/attributes arrays are
  sorted lexicographically, sorries are sorted by line number, and module
  discovery is sorted before import. Verified by running extract twice and
  confirming byte-identical output.

## [0.4.3] - 2026-04-07

### Added

- **`trusted` verification status**: Axiom declarations (`kind: "axiom"`) and
  all declarations in `*External.lean` files (Aeneas convention for hand-written
  external function/type models) are now marked `"trusted"` instead of
  `"verified"`. This distinguishes the trust base — definitions assumed correct
  without formal proof — from genuinely verified code. Previously these were
  indistinguishable from proven declarations.

## [0.4.2] - 2026-04-03

### Added

- **Toolchain version diagnostic**: `extract` now prints the Lean version
  probe-lean was built with and the target project's toolchain version at
  startup (e.g. `probe-lean built with Lean 4.28.0-rc1, target project uses v4.28.0`).
  Makes toolchain mismatches immediately visible in logs.

## [0.4.1] - 2026-04-02

### Fixed

- **Auto-download Mathlib cache**: `ensureMathlibCache` (formerly
  `warnIfMathlibCacheMissing`) now runs `lake exe cache get` automatically
  when a project depends on Mathlib but no pre-built `.olean` cache is
  found. Previously, probe-lean only printed a warning and then proceeded
  to build Mathlib from source, which takes hours. Falls back gracefully
  if the download fails.

## [0.4.0] - 2026-03-31

### Added

- Build cache now checks `lean-toolchain` and `lakefile.toml` mtimes, so
  changing the toolchain properly invalidates the cache without needing
  manual cleanup.
- `checkFilesNewerThan` skips dot-directories (`.lake/`, `.git/`), avoiding
  slow walks through dependency sources and false cache invalidations after
  `lake exe cache get`.
- `isCacheValid` verifies the build output directory (`.lake/build/lib/`)
  exists, catching `lake clean` scenarios where the cache file survives but
  build artifacts are gone.
- Smarter `incompatible header` error hint: when probe-lean and the target
  project use the same Lean version, suggests `lake clean` (stale oleans)
  instead of a misleading "toolchain mismatch" message.
- `parseToolchainVersion` helper extracted for reuse and testing.

### Fixed

- Bash installer (`tools/bash/install.sh`): replaced `trap cleanup EXIT`
  with inline restore after build, fixing `unbound variable` errors when
  building for a non-default Lean version.

## [0.3.0] - 2026-03-26

### Added

- Automated toolchain version detection: installer scripts read `lean-toolchain`
  from the target project and install the matching `probe-lean` binary.
- Hybrid installation: pre-built binary download from GitHub Releases with
  automatic source-build fallback.
- Per-version binary and `.olean` storage (`~/.local/bin/probe-lean-v<version>`,
  `~/.local/lib/probe-lean-v<version>/`) so multiple Lean versions can coexist.
- `probe-lean --version` CLI flag (also works on subcommands).
- Single source of truth versioning: version defined in `lakefile.toml`,
  propagated via `tools/gen-version.sh` to `ProbeLean/Version.lean`.
- GitHub composite action (`action/action.yml`) for downstream CI integration.
- GitHub release workflow (`.github/workflows/release.yml`) for publishing
  pre-built binaries on tag push.
- Multi-stage `Dockerfile` for containerized `probe-lean` usage.
- CI job to verify `Version.lean` stays in sync with `lakefile.toml`.
- Installer flags: `--from-project`, `--lean-version`, `--force`.

### Changed

- Installer scripts (`tools/bash/install.sh`, `tools/python/install.py`)
  rewritten with full feature parity: platform detection, version-aware
  installation, and `PATH` setup guidance.

### Fixed

- Python installer: added `filter="data"` to `tarfile.extractall` for security.
- GitHub Action: fixed cache ordering (restore before build) and ensured
  `elan`/`lake` are always available regardless of cache state.
- GitHub Action: replaced unsafe `eval $CMD` with direct command execution.

## [0.2.0] - 2026-03-16

### Added

- `specs` field on atoms: lists the code-names of theorem atoms whose
  dependencies include the atom. Computed as a reverse-edge pass on the
  call graph after atomization. The field is omitted from JSON output
  when the list is empty. ([#11](https://github.com/Beneficial-AI-Foundation/probe-lean/issues/11))

## [0.1.0] - 2025-01-01

Initial release.
