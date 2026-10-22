# Verification status: how the kernel walk decides

Companion to [schema.md](schema.md#verification-status-and-the-trusted-base), which defines the
five `verification-status` values and the three `trusted-reason` rules. This document helps a reader
audit one verdict. It covers where a `sorry` is attributed, what the walk follows, and which
modules it covers. It also covers duplicated names and the scope and limits of each trust rule.
The CLI output for these cases is in [usage.md](usage.md#extract).

## Notation

- P: every constant of every project module of the import closure, atoms or not. The import
  closure is the set of modules that the import of the target modules loads. With `--module`,
  the import is the project modules of that closure under the prefix, and the closure is theirs. A project module is a module of the closure whose `.olean` is in `.lake/build/lib/lean`
  of the project. See [Coverage of P](#coverage-of-p).
- T: the trusted base, the constants of P that one of the three trust rules matches. See
  [The trusted base T in full](#the-trusted-base-t-in-full).
- S: the standard axioms `propext`, `Classical.choice` and `Quot.sound`.
- `As(c)`: the assumption set of the constant `c`. See [Assumption sets](#assumption-sets).

## The walk

`sorry` elaborates to the `sorryAx` axiom. `extract` and `check-axioms` walk the constant graph of
every constant of every project module of the import closure (the set P). The walk includes the
modules that `--library` does not emit, and constants that are never atoms: auxiliaries, constructors, and range-less
`addDecl`/`impl_def` constants. The walk is memoized and stops at two boundaries:

- The project boundary. Lean and every dependency package are trusted wholesale. This is
  everything `lake-manifest.json` lists, including a second Lake package that holds the project's
  own code. Move such code into the main package to have it analysed. Both commands name the
  boundary once per run on stderr.
- The proof of each member of the trusted base T inside the project, see
  [The trusted base T in full](#the-trusted-base-t-in-full). The walk still follows the statement
  of a member of T.

Trust excuses a declaration's proof, not its statement. For a trusted declaration the walk follows
the constants of its type and not those of its value. For a trusted inductive type or structure, the
statement also includes its constructors, because their types hold the field types. A `sorry` in its
proof, or below it, does not taint its callers. A project `sorry` behind its statement does. In the example below, `t` reads
`"verified"` with `"status-origin": "kernel-taint"`, and so do `a` and `c`:

```lean
def p : Prop := sorry
axiom a : p
axiom c : p → True
theorem t : True := c a
```

A trusted declaration whose statement rests on a project `sorry` loses its trust. If its statement
names `sorryAx` itself, it reads `"unverified"`. Otherwise it reads `"verified"` with
`"status-origin": "kernel-taint"`. In both cases it has no `trusted-reason`. It stays in T by the
rules, and the `check-axioms` T listing marks it `[statement tainted]`.

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
auxiliary, so `tools/audit/check-graph.py` prints a `Divergence(graph)` line for `f`. `f` also carries
`"status-origin": "kernel-taint"`. From Lean 4.29 the `sorry` stays inline and `f` reads
`"unverified"`. On every toolchain `f` is tainted and never `"transitively-verified"`.

Theorems are never abstracted. A data-typed `sorry` (`def n : Nat := sorry`) stays inline on
every toolchain. `tools/audit/compare-extract.py --status-policy taint` accepts the resulting
`unverified → verified` move against a build-log artifact.

## Graph check

`extract` uses neither the build log nor the emitted graph for the status. Up to 0.20.0 it also
ran two cross-checks against the walk and printed their disagreements on stderr. Version 0.21.0
removed both. The build-log check is gone. The graph check is the script
`tools/audit/check-graph.py` in the probe-lean repository (not in the release assets), which
reads an artifact. `<probe-lean>` is a probe-lean checkout and `<project>` is the target project:

```bash
python3 <probe-lean>/tools/audit/check-graph.py --fail-on-divergence <project>/.verilib/probes/lean_<pkg>_<ver>.json
```

The script runs a reverse BFS over the emitted `dependencies`. The seeds are the atoms that read
`"unverified"` or `"failed"`. Taint goes from a dependency to its callers through atoms that read
`"verified"` or `"transitively-verified"`. Trusted atoms, atoms without a status and missing
dependencies stop it. The script then prints `Divergence(graph): <atom> graph says clean, oracle
says tainted` (or the reverse) for each atom where the BFS and the walk disagree. Such a line
points to a node or edge that the emitted graph is missing, typically a carrier with no
declaration range. The `status-origin` marker makes the same gap visible in the output, see
[Re-deriving statuses](schema.md#re-deriving-statuses). The script also prints a `Warning:` line
for each dependency name that is not an atom.

With `--fail-on-divergence`, exit 0 means that the emitted graph and the walk agree on every atom
with a status. Without the flag, the script exits 0 also on a divergence. Exit 0 does not prove
that every edge was emitted: a missing edge that does not change taint is invisible, and missing
dependencies never fail the run. The script reads enveloped artifacts from 0.16.0 on. It rejects
input whose version it cannot read, because before 0.16.0 a tainted atom that reads `"verified"`
has no `status-origin` marker and looks clean. If `extract`
printed the duplicate-name warning (two raw names that print as the same string), the artifact
keeps one of the colliding atoms, and the report lacks the other one and its edges.

## Kernel dependencies, not executable bodies

The walk follows what the kernel constant references. This is not always the code that runs.

- A `partial def`'s body compiles to `X._unsafe_rec`, and the kernel constant `X` is an opaque
  inhabitant with no edge to it. So `loopy` in `partial def loopy … sorry …` reads
  `"transitively-verified"`, while `loopy._unsafe_rec` is a direct carrier that `check-axioms`
  lists as `[direct] [not emitted]`. Against a build-log artifact this moves the host from
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

`extract` imports the target modules, or with `--module` the project modules of their closure under
the prefix. P is the set of project modules that this import loads. A constant can only reference constants of its own module's import closure, so
every emitted atom's dependency closure is inside P.

probe-lean builds the targets in the same run and requires that a `lean_lib` of the root package
owns every module of P. For such a module, Lake records each import in the importer's trace, so
the target build rechecked every module of P. A module of P that breaks the rule fails the run
before the import, with one message that lists every such module and its reason:

- No `lean_lib` of the root package owns it, for example after its `[[lean_lib]]` entry was
  removed. Lake then reads its `.olean` without a check.
- Only a `lean_exe` owns it, and another module of P imports it. Lake does not recheck such an
  import.
- A `lean_lib` module and a `lean_exe` root have its name.

The root module of a target `lean_exe` that no module imports is accepted. See
[usage.md](usage.md#stale-build-outputs).

An atom whose Lean name is not in P is a bug signal, not "clean". It gets no status, and `extract`
prints `Warning: atom <name> is not a project constant the kernel walk covered; no
verification-status assigned`.

A module-system olean whose split parts are missing aborts the extraction, because Lean's import
fails on it.

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

These rules apply only if the import loads more than one version of the name. Then probe-lean
takes the union of the versions. If the import set loads one version, for example under
`--module`, probe-lean reports that version alone.

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

Kernel theorems (a `theorem` or a Prop-valued projection, which reads `kind: "projection"`) and
any declaration whose type is a proposition (`def admitted : False := sorry`) get their normal
status in a `*External` module. Every other declaration there is trusted as a model,
whatever its type. This includes a Prop-valued `def p : Prop`, and also `def e : Empty := sorry`
or a subtype that carries a sorried proof field. No inhabitedness test is made.

The `check-axioms` listing of T (`N trusted constant(s) (T):`, one
`<name> [<reason>] <module>[ : <type>]` line each) shows the statement for rule-3 entries. A
reviewer checks rule-3 models there. A member of T whose statement rests on a project `sorry` has
the suffix ` [statement tainted]`. It is also in the tainted list above T, and its atom does not
read `"trusted"`.

## Assumption sets

`verification-status` looks only for `sorry`. probe-lean trusts axioms and does not test them. An
axiom such as `axiom bad : False` leaves its callers `"transitively-verified"`. A human reviews
each project axiom once, in the `check-axioms` listing of T. No tool can replace that review:
whether a set of axioms is consistent is undecidable, so no test finds every false axiom.

The `assumptions` field shows what each proof trusts. It does not change the status. The
assumption set `As(c)` of a constant `c` holds every axiom and trusted constant that `c` rests on,
other than the standard axioms S (`propext`, `Classical.choice`, `Quot.sound`). The first
matching rule applies:

| Constant `c` | `As(c)` |
|---|---|
| `sorryAx` | `{sorryAx}` |
| in S and outside P (see [Notation](#notation)) | `{}` |
| any other axiom, in a project or a dependency | `{c}` ∪ `As` of the constants of its type |
| outside P | the union of `As` over the constants of its type and value (and constructors, for an inductive). Trust rules do not apply outside P. |
| in T, not an axiom | see below |
| any other constant of P | the union of `As` over its walk edges |

Lean's importer keeps one version of a name that several modules declare with the same
statement. The set walk does not rely on that version alone:

- If any version is an axiom, in a project module or a dependency, the name adds `{c}`, whichever
  version the environment kept.
- The walk also follows the edges of every version that a module outside P declares: the
  constants of its type and value. It does so for every rule above except `sorryAx` and S, which
  stay leaves. Trust rules do not apply to those edges, so a `sorry` there gives `sorryAx`.

Without this, two dependency modules that swap an axiom and a theorem hide both axioms. Take
`axiom a : False` and `theorem b : False := a` in one module, and `axiom b : False` and
`theorem a : False := b` in the other. Lean keeps both theorems, which only call each other. A
project theorem that uses `a` then reads `"transitively-verified"`, and its set holds `a` and
`b`. The status walk does not search dependency packages, so the status stays as it is.

Trust excuses only `sorry`. For a member `c` of T whose version in the environment is not an
axiom:

```
As(c) = own(c) ∪ As(stmt(c)) ∪ As(outside(c)) ∪ (As(proof(c)) \ {sorryAx}) ∪ ({c} if sorryAx ∈ As(proof(c)))
```

The last two terms replace `sorryAx` with `c`. A `sorry` in the proof of a trusted constant is
excused, and its callers list the constant that they trust instead. Other axioms of the proof flow
through. If the proof is complete, `c` is not in the set, because trusting it costs nothing. For a
lemma `add_spec` in T:

| Proof of `add_spec` | `As(add_spec)` |
|---|---|
| `sorry` | `{add_spec}` |
| `native_decide`, no `sorry` | `{add_spec._native.native_decide.ax_1_1}` |
| complete, no axioms | `{}` |

`own(c)` adds `c` for another reason: it is `{c}` if any version of `c` is an axiom (see above),
whatever the proof contains, else `{}`. `stmt(c)` is the statement the status walk follows: the
type, and the constructors of an inductive. `outside(c)` is the edges of the versions outside P (see
above). It is not excused, so a project axiom merged with a dependency theorem that uses `sorry`
lists `sorryAx`. `proof(c)` is the constants of the value of a `def`, `theorem` or `opaque`, the
union over the project versions for a merged name. Other kinds have no proof edges. So the leaves of
a set are axioms and the trusted constants that cut off a `sorry`. If a vouched lemma has a full
proof through another vouched lemma that has a `sorry`, both the lemma and the axioms of the other
lemma's statement flow through. A value can name the constants of its statement (a type argument, an
`rfl` term), so a member of T whose statement rests on a `sorry` can list its own name next to
`sorryAx`.

The graph has cycles, for example an inductive and its constructors. `As` is the least fixpoint
of the rules. The rules are monotone, so this fixpoint is unique and does not depend on the visit
order. The walk solves each strongly connected component on its own: every member starts at its
own names, and the walk evaluates the members again until no set changes. Each member keeps its
own set.

`sorryAx` is in the set of every atom that reads `"unverified"`, or `"verified"` with
`"status-origin": "kernel-taint"`. Both walks use the same project test, trust set and edges, and
a tainted path keeps `sorryAx` at each trusted node because it uses a statement edge there. The
converse does not hold. A `sorry` in a dependency package puts `sorryAx` in the set of a
`"transitively-verified"` atom.

The `check-axioms` listing ends with the names of all sets over P, with a category and the
number of constants of P whose set holds each name (see [usage.md](usage.md#check-axioms)).

The walk does not use the axiom table that Lean 4.30 and later stores in each olean. Lean's
exporter caches an empty placeholder for a constant while it walks the children of that
constant, and it does not repair cycles. So an entry can be too small: a constructor can get `[]`
although it reaches `sorryAx` through its inductive. The table also covers only the version of a
merged name that the caller was compiled against.
