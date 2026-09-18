# Verification status: how the kernel walk decides

Companion to [SCHEMA.md](SCHEMA.md#verification-status-and-the-trusted-base), which defines the
five `verification-status` values and the three `trusted-reason` rules. This document holds what a
reader needs when auditing one verdict: where a `sorry` is attributed, what the walk follows and
does not follow, which modules it covers, how duplicated names are treated, and the exact scope of
each trust rule. The CLI output that accompanies these cases is in
[USAGE.md](USAGE.md#extract).

## The walk

`sorry` elaborates to the `sorryAx` axiom. `extract` and `check-axioms` walk the constant graph of
*every* constant of *every* built project module (the set P), regardless of `--module`/`--library`
and including constants never emitted as atoms: auxiliaries, constructors, range-less
`addDecl`/`impl_def` constants. The walk is memoized and stops at two boundaries:

- **The project boundary.** Lean and every dependency package are trusted wholesale: everything
  `lake-manifest.json` lists, a second Lake package holding the project's own code included (move
  code into the main package to have it analysed). Both commands name the boundary once per run on
  stderr.
- **The trusted base T** inside the project, defined by the three rules below.

A trusted declaration is a leaf: a `sorry` inside or below it does not taint its callers, because
a human vouched for it. One whose *statement* names `sorryAx` directly is still reported with
`Warning: trusted declaration <n> names \`sorry\` directly in its statement`; a statement that
reaches `sorry` only through another constant is not detected.

Generated companions (`X.mvcgen_spec`) receive their own status. A companion of a trusted theorem
is `"transitively-verified"`, not `"trusted"`.

## Attribution is per kernel constant

The elaborator decides where a `sorry` lands, and the toolchain changes the answer for
definitions.

On Lean ≤ 4.28 a `def`'s sorried proof obligation (`def f : Fin 5 := ⟨3, by sorry⟩`) is
abstracted into `f._proof_1`. That auxiliary is the direct carrier (`[direct] [not emitted]` in
`check-axioms`), `f` itself reads `"verified"`, and since the emitted graph has no node for the
auxiliary, the graph cross-check prints a `Divergence(graph)` line for `f`. From Lean 4.29 the
`sorry` stays inline and `f` reads `"unverified"`. On every toolchain `f` is tainted and never
`"transitively-verified"`.

Theorems are never abstracted, and a data-typed `sorry` (`def n : Nat := sorry`) stays inline on
every toolchain. `tools/audit/compare-extract.py --status-policy taint` accepts the resulting
`unverified → verified` move against a build-log artifact.

## Cross-checks, never reconciled

Two older heuristics still run and are compared against the walk. Where they disagree, `extract`
prints a line on stderr and keeps the walk's verdict:

- the reverse-BFS over the emitted graph: `Divergence(graph): <atom> graph says clean, oracle says
  tainted` (or the reverse). A graph divergence localises a node or edge the emitted graph is
  missing, typically a carrier with no declaration range;
- the build log's `sorry` warnings: `Divergence(log): …`, trusted atoms skipped.

## Kernel dependencies, not executable bodies

The walk follows what the kernel constant references, which is not always what runs.

- A `partial def`'s body compiles to `X._unsafe_rec`, and the kernel constant `X` is an opaque
  inhabitant with no edge to it. So `loopy` in `partial def loopy … sorry …` reads
  `"transitively-verified"` while `loopy._unsafe_rec` is a direct carrier, listed `[direct] [not
  emitted]` by `check-axioms`. The build-log cross-check prints a `Note(log)` line naming the
  compiled body instead of a divergence.
- An `@[implemented_by target]` host has no edge to `target`. The target is a constant of its own
  and gets its own status; nothing links the host to it.
- `unsafe def` bodies *are* walked.

Since Lean 4.31 a `native_decide` proof rests on a generated project **axiom**
(`X._native.native_decide.ax_N`) instead of referencing `Lean.ofReduceBool`. The name is internal,
so it is never an atom, although it carries the theorem's declaration range. Rule 1 trusts it, the
caller reads `"transitively-verified"`, and both commands print one `Note(axiom)` line per run
naming the generated axioms (capped at 10; the `check-axioms` T listing names every one). Generated
axioms stay trusted by decision (#109): Lean's compiler is part of the trusted base, as
`Lean.ofReduceBool` was before 4.31. Known gap: a project `@[implemented_by]`/`@[extern]` body is
kernel-unchecked code that evaluation runs, so a wrong one can make `native_decide` prove a false
statement, and probe-lean does not detect it.

## Coverage of P

`extract` first tries to import all built project modules. If the full set cannot be co-imported,
the walk runs over the selected modules **and every project module they import transitively**, so
every emitted atom's dependency closure is still inside P. The modules left out are outside that
closure; only the `check-axioms` audit misses them, and a `Warning: <n> project module(s) not
imported (full import failed); …` line says so.

An atom whose Lean name is not in P is a bug signal, not "clean": it gets **no** status and
`Warning: atom <name> is not a project constant the kernel walk covered; no verification-status
assigned` is printed.

Two conditions abort the extraction because they would silently move project code outside P:

- a module-system olean whose split parts are missing (Lean's import would fail on it);
- a stale `.olean` with no `.lean` source that a kept module still imports. It would otherwise sit
  outside P and be trusted like a dependency. Run `lake clean` in the target project and rebuild.

## Merged declarations

Lean's importer accepts two project modules restating the same theorem (same name and statement)
and keeps *one* proof without comparing bodies, so after co-import that name no longer identifies
one project proof. The walk fails closed for such a name:

- it follows the union of every version's dependencies. A `sorry` in any version makes the name
  `"unverified"` and every caller `"verified"`, including callers built against the proved
  version;
- no `@[externally_verified]` on it is honoured;
- `Warning: <n> declaration name(s) are declared by more than one project module with the same
  statement, and Lean kept one proof: …` is printed. Give each variant its own namespace if the
  proved version's callers should read clean.

The versions come from the imported environment itself. Lean's importer collapses only the constant
lookup map, while the environment header keeps every module's own constants (module-system modules
included, since the import is at the private level), so the walk follows every project version
kept in the imported environment.

A restatement of a **dependency's** theorem, meaning a name a project module declares that a
non-project module declares too, or that the environment attributes outside the project, is walked
the same way from the **project's own version(s)**: a `sorry` in any of them gives `"unverified"`
if emitted, else `[not emitted]` in `check-axioms`, and every caller `"verified"`, whichever body
the environment kept. A proved restatement of a proved dependency theorem stays clean, the other
body being a dependency's and already trusted. Only rules 1 and 3 apply to such a name. Announced
with `Note: <n> declaration name(s) are declared by a project module and by a module outside the
project …`.

Lean's on-demand realisations (`f.eq_1`, `f.congr_simp`, `f.hcongr_N`, `match_1.congr_eq_N`) that
several modules realised independently are walked the same way and announced separately with
`Note: <n> Lean-realised equational/congruence theorem(s) were realised in more than one module:
…`, since nothing was written twice by hand.

Remaining limitation: a name whose *every* declaring module is outside P is never examined. That
is the trusted-base decision, not a gap.

## The trusted base T in full

One shared rule set (`ProbeLean/Trust.lean`) is used by `trusted-reason`, by the walk and by
`check-axioms`, in precedence order.

### Rule 1: `"axiom"`

The Lean `axiom` keyword, the generated `native_decide` axioms included. Generated axioms are never
atoms; the `Note(axiom)` line and the `check-axioms` T listing name them.

### Rule 2: `"externally_verified"`

The declaration is in the attribute's **tag set** (proof discharged outside Lean), read from the
environment, not from source text. `registerTagAttribute` stores the tagged names in the olean
under the registering constant's name; probe-lean finds that constant, reads the attribute name and
extension name off its `initialize` body, and reads the entries. probe-lean's own handle is a second
source for targets that import `ProbeLean.Attrs`.

A tag is a tag, whatever syntax attached it (`@[…]` on the declaration or an after-the-fact
`attribute [externally_verified] foo` command) and whatever the constant is, a range-less
`impl_def` included.

What is **not** in the set: anything that merely shares a tagged declaration's source range (a
`deriving` instance, a projection, a generated `.mvcgen_spec` companion, a Lean-generated
`instX.field` helper) and anything the source scan could be fooled by (a tag in a docstring, a
comment, a string or an interpolated string, a neighbouring command on the same line, a syntax
quotation).

Limits, all under-trust: a tag attribute registered with an explicit `ref` other than its
constant's name, through a wrapper, or as a `ParametricAttribute` is not read. `Divergence(tag)`
lines say so per declaration for tags written `@[…]` on a declaration, while a tag such a
registration attaches with no header to scan (an `attribute` command, a range-less constant) is
untrusted without a line.

The `attributes` array lists `externally_verified` when the tag set contains the declaration or
when a separate header scan finds the tag, so it can show the entry on a constant that is not in
the set. Where the scan and the set disagree, `extract` prints
`Divergence(tag): …` (header shows the tag, set does not contain it) or `Note(tag): …` (set contains
it, header does not show it). Both report set membership; `trusted-reason` has the final status.

### Rule 3: `"external"`

A declaration in a module whose name ends with `External` (e.g. `Pkg.FunsExternal`) that is not a
**proof**. Theorems, and any `def`/`opaque`/instance whose *type is a proposition* (`def admitted :
False := sorry`), get their normal status there. Every other declaration in a `*External` module is
trusted as a model, whatever its type: a Prop-*valued* `def p : Prop`, and also `def e : Empty :=
sorry` or a subtype carrying a sorried proof field, since no inhabitedness test is made.

The `check-axioms` listing of T (`N trusted constant(s) (T):`, one `<name> [<reason>] <module>[ :
<type>]` line each, the statement shown for rule-3 entries) is where a reviewer sees them.
