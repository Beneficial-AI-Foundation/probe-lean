#!/usr/bin/env bash
# TEMPORARY (issue #141, removed in the next commit): compare the graph cross-check
# that `extract` prints on stderr with the report of tools/audit/check-graph.py on
# the same run's artifact. Both sides go through `sort`, not `sort -u`.
#
# usage: parity-check-graph.sh STDERR ARTIFACT [STDERR ARTIFACT ...]
set -u
here=$(cd "$(dirname "$0")" && pwd)
fail=0
while [ $# -ge 2 ]; do
  err=$1 art=$2; shift 2
  echo "== $err vs check-graph.py $art"
  if grep -q "duplicate atom name" "$err"; then
    echo "   duplicate-name warning: the artifact lacks colliding atoms, no exact comparison"
    continue
  fi
  rep=$(python3 "$here/check-graph.py" "$art") || { echo "   check-graph.py failed"; fail=1; continue; }
  compare() {
    if diff <(printf '%s\n' "$2") <(printf '%s\n' "$3") >/dev/null; then
      echo "   $1: equal"
    else
      echo "   $1: DIFFERENT"; diff <(printf '%s\n' "$2") <(printf '%s\n' "$3"); fail=1
    fi
  }
  compare "Divergence(graph) lines" \
    "$(grep '^Divergence(graph):' "$err" | sort)" \
    "$(printf '%s\n' "$rep" | grep '^Divergence(graph):' | sort)"
  compare "missing dependency names" \
    "$(sed -n 's/^Warning: dependency "\(.*\)" not found in atom map.*/\1/p' "$err" | sort)" \
    "$(printf '%s\n' "$rep" | sed -n 's/^Warning: dependency "\(.*\)" not found in atom map$/\1/p' | sort)"
  compare "type-member Note count" \
    "$(sed -n 's/^Note: \([0-9]*\) reference(s) to constructors.*/\1/p' "$err")" \
    "$(printf '%s\n' "$rep" | sed -n 's/^Note: \([0-9]*\) reference(s) to constructors.*/\1/p')"
done
exit $fail
