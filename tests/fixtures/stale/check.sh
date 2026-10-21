#!/usr/bin/env bash
# End-to-end checks for stale build outputs (issue #152).
#
# Usage: check.sh <probe-lean>
#
# Works on a fresh copy of this fixture in a temporary directory, so a run leaves
# the tree unchanged. The steps run in order on that one copy:
#   1. After all libraries are built, `f` in `Core` changes, so the built
#      `extra_thm : f = 1` is false. `extract .` builds `Core` only and must not
#      import the stale `Extra.olean`.
#   2. `--library` builds and emits the named libraries.
#   3. No run writes `.lake/probe-lean/build_output.txt`.
#   4. `--all-libraries` emits every library.
#   5. A broken proof in `Core` fails the build, although `Core` sets
#      `defaultFacets = []`.
#   6. `Core` imports the executable root `ExeOld`: rejected (R11 case 3).
#   7. `Shared` is also an executable root: rejected (R11 case 4).
#   8. The `[[lean_lib]]` entry of `Old` is removed and its proof breaks:
#      rejected (R11 case 5), and the output file stays unchanged.
set -u

PL=$(realpath "$1")
SRC=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp -r "$SRC" "$WORK/stale"
rm -rf "$WORK/stale/.lake" "$WORK/stale/.verilib" "$WORK/stale/lake-manifest.json"
cd "$WORK/stale" || exit 2

failures=0
check() {
  local name=$1; shift
  if "$@"; then echo "  ✓ $name"; else echo "  ✗ $name"; failures=$((failures + 1)); fi
}
# The atom names of an output file, one per line, without the `probe:` prefix.
atoms() {
  python3 -c 'import json,sys; [print(k.removeprefix("probe:")) for k in json.load(open(sys.argv[1]))["data"]]' "$1"
}
has() { atoms "$1" | grep -qx "$2"; }
lacks() { ! has "$1" "$2"; }
status_of() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["data"].get("probe:"+sys.argv[2],{}).get("verification-status"))' "$1" "$2"
}
status_is() { [ "$(status_of "$1" "$2")" = "$3" ]; }
no_build_output() { [ ! -e .lake/probe-lean/build_output.txt ]; }
# Run probe-lean, keep stdout and stderr in <tag>.out and <tag>.err.
run() { local tag=$1; shift; "$PL" "$@" >"$tag.out" 2>"$tag.err"; }
err_has() { grep -qF -- "$2" "$1.err"; }

echo "1. A stale .olean of a library that the targets do not import"
lake build Core:leanArts Shared:leanArts Extra:leanArts Old:leanArts +ExeOld >build.log 2>&1 \
  || { cat build.log; exit 1; }
sed -i 's/def f : Nat := 1/def f : Nat := 2/' Core.lean
check "extract . succeeds" run s1 extract . -o s1.json
for a in core_thm shared_thm hidden_thm old_thm; do
  check "$a is emitted" has s1.json "$a"
done
check "extra_thm (stale, false) is not emitted" lacks s1.json extra_thm
check "exe_thm (executable root, not a target) is not emitted" lacks s1.json exe_thm
check "build output not written" no_build_output
(cd .. && "$PL" extract stale -o "$WORK/parent.json" >/dev/null 2>"$WORK/parent.err")
check "extract from the parent directory succeeds" test -s "$WORK/parent.json"
[ -s "$WORK/parent.json" ] || cat "$WORK/parent.err"
check "same atoms from the parent directory" \
  test "$(atoms s1.json | sort)" = "$(atoms "$WORK/parent.json" | sort)"

echo "2. --library"
sed -i 's/theorem extra_thm : f = 1 := rfl/theorem extra_thm : f = 1 := sorry/' Extra.lean
check "extract . --library Core succeeds" run s2a extract . --library Core -o s2a.json
check "--library Core: no extra_thm" lacks s2a.json extra_thm
check "extract . --library Core,Extra succeeds" run s2b extract . --library Core,Extra -o s2b.json
check "--library Core,Extra: extra_thm is unverified" status_is s2b.json extra_thm unverified
check "--library Core,Extra: Shared atoms are not emitted" lacks s2b.json shared_thm

echo "3. No build cache file"
check "build output not written" no_build_output

echo "4. --all-libraries"
check "extract . --all-libraries succeeds" run s4 extract . --all-libraries -o s4.json
for a in core_thm shared_thm extra_thm old_thm; do
  check "--all-libraries: $a is emitted" has s4.json "$a"
done
check "--all-libraries: no executable root" lacks s4.json exe_thm

echo "5. A broken proof in Core fails the build"
cp Core.lean Core.lean.orig
echo 'theorem broken : (1 : Nat) = 2 := rfl' >>Core.lean
check "extract . fails" bash -c '! "$0" extract . -o s5.json >s5.out 2>s5.err' "$PL"
check "the error is the build error" err_has s5 "Lake build failed"
mv Core.lean.orig Core.lean

echo "6. Core imports the executable root ExeOld"
lake build +ExeOld >build.log 2>&1 || { cat build.log; exit 1; }
cp Core.lean Core.lean.orig
sed -i '1i import ExeOld' Core.lean
check "extract . fails" bash -c '! "$0" extract . -o s6.json >s6.out 2>s6.err' "$PL"
check "R11 case 3 names ExeOld" err_has s6 "  ExeOld: only a lean_exe owns this module, and another project module imports it."
mv Core.lean.orig Core.lean

echo "7. Shared is also an executable root"
cp lakefile.toml lakefile.toml.orig
printf '\n[[lean_exe]]\nname = "sharedexe"\nroot = "Shared"\n' >>lakefile.toml
check "extract . fails" bash -c '! "$0" extract . -o s7.json >s7.out 2>s7.err' "$PL"
check "R11 case 4 names Shared" err_has s7 "  Shared: the name is both a lean_lib module and a lean_exe root."
mv lakefile.toml.orig lakefile.toml

echo "8. The [[lean_lib]] entry of Old is removed"
echo marker >marker.json
python3 - <<'P'
s = open("lakefile.toml").read()
s = s.replace('[[lean_lib]]\nname = "Old"\n\n', "")
open("lakefile.toml", "w").write(s)
P
sed -i 's/def s : Nat := 2/def s : Nat := 3/' Shared.lean
check "extract . fails" bash -c '! "$0" extract . -o marker.json >s8.out 2>s8.err' "$PL"
check "R11 case 5 names Old" err_has s8 "  Old: no lean_lib of the root package owns this module"
check "the output file is unchanged" test "$(cat marker.json)" = marker
check "check-axioms . fails" bash -c '! "$0" check-axioms . >s8c.out 2>s8c.err' "$PL"
check "check-axioms: R11 case 5 names Old" err_has s8c "  Old: no lean_lib of the root package owns this module"
check "build output not written" no_build_output

echo
if [ "$failures" -gt 0 ]; then
  echo "stale end-to-end check: $failures assertion(s) failed"
  for f in s*.err; do echo "--- $f"; tail -20 "$f"; done
  exit 1
fi
echo "stale end-to-end check: all assertions passed"
