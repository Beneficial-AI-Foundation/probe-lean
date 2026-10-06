# Verification status: how the kernel walk decides

Companion to [schema.md](schema.md#verification-status-and-the-trusted-base), which defines the
five `verification-status` values and the three `trusted-reason` rules. This document helps a reader
audit one verdict. It covers where a `sorry` is attributed, what the walk follows, and which
modules it covers. It also covers duplicated names and the scope and limits of each trust rule.
The CLI output for these cases is in [usage.md](usage.md#extract).

## The walk

`sorry` elaborates to the `sorryAx` axiom. `extract` and `check-axioms` walk the constant graph of
every constant of every built project module (the set P). The walk ignores `--module`/`--library`
and includes constants that are never atoms: auxiliaries, constructors, and range-less
`addDecl`/`impl_def` constants. The walk is memoized and stops at two boundaries:

- The project boundary. Lean and every dependency package are trusted wholesale. This is
  everything `lake-manifest.json` lists, including a second Lake package that holds the project's
  own code. Move such code into the main package to have it analysed. Both commands name the
  boundary once per run on stderr.
- The trusted base T inside the project, see [The trusted base T in full](#the-trusted-base-t-in-full).

A trusted declaration is a leaf: a `sorry` inside or below it does not taint its callers. If its
statement names `sorryAx` directly, both commands print
`Warning: trusted declaration <n> names \`sorry\` directly in its statement`. A statement that
reaches `sorry` only through another constant is not detected.

The edges are every constant that a declaration's type and value name, including the structure
behind a projection node (`x.1`). The walk collects that structure itself on every toolchain.

Generated companions (`X.mvcgen_spec`) receive their own status. A companion of a trusted theorem
is `"transitively-verified"`, not `"trusted"`.

## Attribution is per kernel constant

The elaborator decides where a `sorry` lands, and the toolchain changes the answer for
definitions.

On Lean ≤ 4.28 a `def`'s sorried proof obligation (`def f : Fin 5 := ⟨3, by sorry⟩`) is
abstracted into `f._proof_1`. That auxiliary is the direct carrier (`[direct] [not emitted]` in
`check-axioms`), and `f` itself reads `"verified"`. The emitted graph has no node for the
auxiliary, so the graph cross-check prints a `Divergence(graph)` line for `f`. `f` also carries
`"status-origin": "kernel-taint"`. From Lean 4.29 the `sorry` stays inline and `f` reads
`"unverified"`. On every toolchain `f` is tainted and never `"transitively-verified"`.

Theorems are never abstracted. A data-typed `sorry` (`def n : Nat := sorry`) stays inline on
every toolchain. `tools/audit/compare-extract.py --status-policy taint` accepts the resulting
`unverified → verified` move against a build-log artifact.

## Cross-checks, never reconciled

Two older heuristics still run and are compared against the walk. When they disagree, `extract`
prints a line on stderr and keeps the walk's verdict:

- The reverse-BFS over the emitted graph prints `Divergence(graph): <atom> graph says clean,
  oracle says tainted` (or the reverse). Such a line points to a node or edge that the emitted
  graph is missing, typically a carrier with no declaration range. The `status-origin` marker
  makes the same gap visible in the output, see
  [Re-deriving statuses](schema.md#re-deriving-statuses).
- The build log's `sorry` warnings produce `Divergence(log): …` lines. Trusted atoms are skipped.

## Kernel dependencies, not executable bodies

The walk follows what the kernel constant references. This is not always the code that runs.

- A `partial def`'s body compiles to `X._unsafe_rec`, and the kernel constant `X` is an opaque
  inhabitant with no edge to it. So `loopy` in `partial def loopy … sorry …` reads
  `"transitively-verified"`, while `loopy._unsafe_rec` is a direct carrier that `check-axioms`
  lists as `[direct] [not emitted]`. The build-log cross-check prints a `Note(log)` line that names
  the compiled body, not a divergence. Against a build-log artifact this moves the host from
  `unverified` to `transitively-verified` and its callers from `verified` to
  `transitively-verified`. `compare-extract.py --status-policy taint` accepts the move only for
  hosts named with `--exec-hosts`.
- An `@[implemented_by target]` host has no edge to `target`. The target is a constant of its own
  and gets its own status. Nothing links the host to it.
- `unsafe def` bodies are walked.

Since Lean 4.31 a `native_decide` proof rests on a generated project axiom
(`X._native.native_decide.ax_N`), not on `Lean.ofReduceBool`. The name is internal, so it is never
an atom, although it carries the theorem's declaration range. Rule 1 trusts it, and the caller
reads `"transitively-verified"`. Both commands print one `Note(axiom)` line per run that names the
generated axioms (at most 10). The `check-axioms` T listing names every one. Generated axioms stay
trusted by decision (#109): Lean's compiler is part of the trusted base, as `Lean.ofReduceBool` was
before 4.31. Known gap: a project `@[implemented_by]`/`@[extern]` body is kernel-unchecked code
that evaluation runs. A wrong one can make `native_decide` prove a false statement, and probe-lean
does not detect it.

## Coverage of P

`extract` first tries to import all built project modules. If the full set cannot be co-imported,
the walk runs over the selected modules and every project module they import transitively. Every
emitted atom's dependency closure is then still inside P. The modules left out are outside that
closure. Only the `check-axioms` audit misses them, and a `Warning: <n> project module(s) not
imported (full import failed); …` line says so.

An atom whose Lean name is not in P is a bug signal, not "clean". It gets no status, and `extract`
prints `Warning: atom <name> is not a project constant the kernel walk covered; no
verification-status assigned`.

Two conditions abort the extraction, because each one silently moves project code outside P:

- a module-system olean whose split parts are missing (Lean's import fails on it).
- a stale `.olean` with no `.lean` source that a kept module still imports. Otherwise it sits
  outside P and is trusted like a dependency. Run `lake clean` in the target project and rebuild.

## Merged declarations

Lean's importer accepts two project modules that restate the same theorem (same name and
statement). It keeps one proof and does not compare bodies. After co-import that name no longer
identifies one project proof. The walk fails closed for such a name:

- It follows the union of the dependencies of every version. A `sorry` in any version makes the
  name `"unverified"` and every caller `"verified"`, including callers built against the proved
  version.
- No `@[externally_verified]` on it is honoured.
- `extract` prints `Warning: <n> declaration name(s) are declared by more than one project module
  with the same statement, and Lean kept one proof: …`. To make the callers of the proved version
  read clean, give each variant its own namespace.

The atom follows the same versions, not the one body the importer kept. Its four split dependency
arrays are the union of the edges of every version, so the `sorryAx` edge behind its
`"unverified"` status is always listed. Under `--module`/`--library`, if any declaring
module that registers a declaration range for the name is selected, the atom is emitted. For the choice of
`code-module`, `code-path` and `code-text`, see
[Dependency arrays](schema.md#dependency-arrays). `attributes` and `rust-source` still come from
the declaration in the attributed module. The emitted atom also counts as a project atom for the
dependency partition of its callers. A selected caller lists it in `term-dependencies` or
`type-dependencies`, not in the `*-external` arrays. The walk reads the versions from the module
headers of the imported environment.

A project module can restate a dependency's theorem: a non-project module declares the same name,
or the environment attributes the name outside the project. The walk then follows only the
project's own versions. A `sorry` in any of them makes the name `"unverified"` and every caller
`"verified"`. If the name is emitted, its dependency arrays hold the project version's edges. A name the
dependency owns is not an atom. A proved restatement of a proved dependency theorem stays clean.
Only rules 1 and 3 apply to such a name.
`extract` announces these names with `Note: <n> declaration name(s) are declared by a project
module and by a module outside the project …`.

Lean's on-demand realisations (`f.eq_1`, `f.congr_simp`, `f.hcongr_N`, `match_1.congr_eq_N`) that
several modules realised independently are walked the same way. A separate line announces them:
`Note: <n> Lean-realised equational/congruence theorem(s) were realised in more than one module:
…`. Nothing was written twice by hand.

Remaining limitation: a name whose every declaring module is outside P is never examined. That is
the trusted-base decision, not a gap.

## The trusted base T in full

[schema.md](schema.md#verification-status-and-the-trusted-base) states the three rules.
`trusted-reason`, the walk and `check-axioms` all use the one rule set in `ProbeLean/Trust.lean`.
This section gives the scope and limits of each rule.

### Rule 1: `"axiom"`

Rule 1 covers generated `native_decide` axioms too. These are never atoms. The `Note(axiom)` line
and the `check-axioms` T listing name them.

### Rule 2: `"externally_verified"`

probe-lean reads the attribute's tag set from the environment, not from source text. It reads the
entries that the target's own `registerTagAttribute` stored in the olean. probe-lean's own handle
is a second source for targets that import `ProbeLean.Attrs`. Any syntax that attaches the tag
counts: `@[…]` on the declaration or an `attribute [externally_verified] foo` command. Any kind of
constant counts, including a range-less `impl_def`.

The set does not contain anything that only shares a tagged declaration's source range: a
`deriving` instance, a projection, a generated `.mvcgen_spec` companion, or a Lean-generated
`instX.field` helper. A tag in a docstring, comment, string, interpolated string, neighbouring
command or syntax quotation does not count either.

Limits, all on the side of under-trust: probe-lean does not read a tag attribute registered with
an explicit `ref` other than its constant's name, through a wrapper, or as a
`ParametricAttribute`. For a tag written `@[…]` on a declaration, a `Divergence(tag)` line reports
this. A tag that such a registration attaches without a header to scan (an `attribute` command, a
range-less constant) is untrusted without a line.

The header scan and the tag set can disagree. If the header shows the tag and the set does not
contain it, `extract` prints `Divergence(tag): …`. In the opposite case it prints `Note(tag): …`. `trusted-reason` has the final status.

### Rule 3: `"external"`

Theorems and any declaration whose type is a proposition (`def admitted : False := sorry`) get
their normal status in a `*External` module. Every other declaration there is trusted as a model,
whatever its type. This includes a Prop-valued `def p : Prop`, and also `def e : Empty := sorry`
or a subtype that carries a sorried proof field. No inhabitedness test is made.

The `check-axioms` listing of T (`N trusted constant(s) (T):`, one
`<name> [<reason>] <module>[ : <type>]` line each) shows the statement for rule-3 entries. A
reviewer checks rule-3 models there.
