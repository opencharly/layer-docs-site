#!/usr/bin/env bash
# docs-pin-report.sh — REPORT the DOCS_REF pin's state.
#
# The pin this repo holds is the docs repo's commit, and the `check-docs` bed clones the
# published site at that commit. The bed proves the IMAGE holds the pin; nothing in the
# org proved the pin is the docs repo's CURRENT head, and nothing proved the two
# occurrences of the sha in charly.yml agree. A control that FAILS on a pin that is
# merely behind cannot live in a gate — it is red for every docs merge that has not been
# re-pinned here — so this REPORTS. It reports FOUR states, and every report NAMES the
# state it is in, so the state is greppable in the output and in the skill body that
# documents it:
#
#   * current  — DOCS_REF IS the docs repo's current main head and both occurrences are
#                present. The healthy state; the exit status is 0.
#   * BEHIND   — DOCS_REF is not the docs repo's current main head. That is a STATE, not a
#                defect: the advance is available NOW in opencharly/docs, and this repo's
#                pin moves when someone takes it. Reported; the exit status is 0.
#   * DISAGREE — the two occurrences of the sha in charly.yml do not agree. That is the
#                tree contradicting ITSELF, and the `docs-site-pinned-commit` check's
#                literal would assert a commit the image never builds. A defect; the
#                exit status is 1.
#   * UNJUDGEABLE — the docs repo's main head could not be fetched, or no DOCS_REF is
#                declared, so the pin's currency cannot be judged at all. The org pin
#                contract makes that a FAILURE and not a pass: a gate that cannot judge
#                is not a gate.
#
# The exit status is therefore 0 for every state a healthy tree can be in, and 1 only for
# the two that are not.
#
# DOCS_PIN_STATES below is the ONE list of those states. Every report goes through
# report_state, which REFUSES a state the list does not carry, and every state the list
# carries must be PROVEN by a case in the self-test — so the list cannot fall behind the
# branches, and the branches cannot run ahead of the list. The skill body
# (.agents/skills/docs-site/SKILL.md) MIRRORS the list, and the self-test proves the
# mirror exact: the count the prose claims, the table's rows, and this list must be the
# same states. That is what stops a fifth state from being added silently — in either
# direction, and in the prose as well as in the code.
#
# Usage:
#   bash scripts/docs-pin-report.sh              # report the pin's state
#   bash scripts/docs-pin-report.sh --self-test  # prove the report discriminates
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$here/.." && pwd)

# The states this script reports, ONE list. The skill body's table mirrors it, and the
# self-test proves the mirror exact.
DOCS_PIN_STATES=(current BEHIND DISAGREE UNJUDGEABLE)

# report_state <state> <message>
#
# EVERY report this script makes goes through here. The state must be one this script
# declares (DOCS_PIN_STATES), and the message must NAME the state it reports: the skill
# body's table names the states, so a reader who greps the output for the state the table
# names must find it. A state outside the list is REFUSED — a branch that reports a state
# the list does not carry is a branch the skill body does not describe.
report_state() {
  local state=$1; shift
  local s
  for s in "${DOCS_PIN_STATES[@]}"; do
    if [ "$s" = "$state" ]; then
      printf '%s\n' "$*"
      return 0
    fi
  done
  printf 'docs-pin: %s — REFUSED: this state is not one this script declares.\n' "$state" >&2
  return 1
}

# docs_pin_report <file> <repo> <live-head>
#
# <live-head> is the docs repo's current main head, or the empty string when it could not
# be fetched. The function takes it as an ARGUMENT so the self-test can drive every
# branch with a KNOWN value — the real path computes it from the remote, and nothing
# else is stubbed.
docs_pin_report() {
  local file=$1 repo=$2 live=$3
  local declared occurrences

  declared=$(grep -E '^[[:space:]]+DOCS_REF:' "$file" | awk '{print $2}')
  if [ -z "$declared" ]; then
    report_state UNJUDGEABLE \
      "docs-pin: no DOCS_REF is declared in $(basename "$file") — the pin is UNJUDGEABLE" >&2 || return 1
    echo "  The candy's clone step and its pinned-commit check both need the sha." >&2
    return 1
  fi

  # The sha appears TWICE on purpose: once as DOCS_REF (the clone layer's cache key) and
  # once as a literal in the docs-site-pinned-commit check's stdout matcher, because a
  # check step's substitution does not resolve a candy var: and would SKIP the step
  # instead of failing it. A re-pin that moved only one of them leaves the matcher
  # asserting a commit the image never builds.
  occurrences=$(grep -c -- "$declared" "$file" || true)
  if [ "$occurrences" -lt 2 ]; then
    report_state DISAGREE \
      "docs-pin: DISAGREE — the pinned sha appears $occurrences time(s) in $(basename "$file"); expected at least 2" >&2 || return 1
    echo "  (DOCS_REF plus the docs-site-pinned-commit check's stdout matcher)" >&2
    echo "  A stale literal means the anti-staleness check asserts the WRONG commit." >&2
    return 1
  fi

  if [ -z "$live" ]; then
    report_state UNJUDGEABLE \
      "docs-pin: could not fetch $repo main HEAD — the pin's currency is UNJUDGEABLE" >&2 || return 1
    echo "  A pin the workflow cannot judge is a failure, not a pass (the org pin contract)." >&2
    return 1
  fi

  if [ "$declared" != "$live" ]; then
    report_state BEHIND "docs-pin: DOCS_REF is BEHIND the docs repo's main head." || return 1
    echo "  DOCS_REF: $declared"
    echo "  docs main: $live"
    echo "  Reported, not failed: a pin that is behind is a state, not a defect. The advance"
    echo "  is available NOW in opencharly/docs — re-pin BOTH occurrences in charly.yml to take it."
    return 0
  fi

  report_state current \
    "docs-pin: DOCS_REF ($declared) IS the docs repo's current main head; both occurrences present." || return 1
  return 0
}

# The states the cases actually drove. Every state the script declares must appear here:
# a state nobody proves is a state the script must not claim.
DRIVEN_STATES=()

note_driven() {
  local s=$1 i
  for ((i = 0; i < ${#DRIVEN_STATES[@]}; i++)); do
    if [ "${DRIVEN_STATES[$i]}" = "$s" ]; then
      return 0
    fi
  done
  DRIVEN_STATES+=("$s")
}

# run_case <state> <label> <expected-exit> <expected-message> <file> <live-head>
#
# A case proves a STATE, so it asserts the state's own REPORT and not only the exit
# status: the current state and the BEHIND state both exit 0, so a case that asserted
# only the status would pass without ever reaching the branch it names. The expected
# message is what tells the two apart, and the state name must appear in the report too —
# the skill body's table names the states, so a report that does not name its own state
# cannot be found by the reader the table is written for.
run_case() {
  local state=$1 label=$2 want=$3 message=$4 file=$5 live=$6
  local out rc
  out=$(docs_pin_report "$file" "https://example.invalid/docs.git" "$live" 2>&1)
  rc=$?
  if [ "$rc" -ne "$want" ]; then
    echo "self-test FAIL: $label — expected exit $want, got $rc" >&2
    echo "  report: $out" >&2
    return 1
  fi
  if ! printf '%s' "$out" | grep -qF -- "$message"; then
    echo "self-test FAIL: $label — the report did not report the expected state" >&2
    echo "  expected in the report: $message" >&2
    echo "  report: $out" >&2
    return 1
  fi
  if ! printf '%s' "$out" | grep -qF -- "$state"; then
    echo "self-test FAIL: $label — the report did not NAME its state ($state)" >&2
    echo "  report: $out" >&2
    return 1
  fi
  note_driven "$state"
  return 0
}

# skill_count_sentences <file>
#
# How many times the skill body names a count of states. It must be exactly once: the
# count the prose claims is a hand-maintained claim over a table that can grow underneath
# it, and this check is what keeps the two true of each other.
skill_count_sentences() {
  grep -cE 'reports one of [A-Za-z]+ states' "$1" || true
}

# skill_count <file>
#
# The number the skill body claims. The count word must be one this script knows.
skill_count() {
  local word
  word=$(awk '/reports one of [A-Za-z]+ states/ { for (i = 1; i <= NF; i++) if ($i == "of") { print $(i + 1); exit } }' "$1")
  case "$word" in
    one) echo 1 ;; two) echo 2 ;; three) echo 3 ;; four) echo 4 ;; five) echo 5 ;;
    six) echo 6 ;; seven) echo 7 ;; eight) echo 8 ;; nine) echo 9 ;; ten) echo 10 ;;
    *) return 1 ;;
  esac
}

# skill_states <file>
#
# The states the skill body's table declares, one per line: the rows of the table the
# count sentence introduces, each row's first cell a bold state name.
skill_states() {
  awk '
    /reports one of [A-Za-z]+ states/ { seen = 1; next }
    seen && /^\|[[:space:]]*\*\*[A-Za-z]+\*\*[[:space:]]*\|/ {
      name = $0
      sub(/^\|[[:space:]]*\*\*/, "", name)
      sub(/\*\*[[:space:]]*\|.*$/, "", name)
      print name
      next
    }
    seen && /^\|/ { next }
    seen && NF { exit }
  ' "$1"
}

# states_agree <skill-file>
#
# The skill body and this script must describe the SAME states: the body names them in a
# table and says how many there are, and this script reports exactly those. A body whose
# count, table, or names disagree is REJECTED, with the reason.
states_agree() {
  local file=$1
  local sentences claimed row s found
  local -a rows=()

  if [ ! -f "$file" ]; then
    echo "the skill body is missing ($file) — the prose that names the states cannot be checked" >&2
    return 1
  fi

  sentences=$(skill_count_sentences "$file")
  if [ "$sentences" != "1" ]; then
    echo "the skill body names a count $sentences time(s); it must name it exactly once" >&2
    return 1
  fi

  if ! claimed=$(skill_count "$file"); then
    echo "the skill body's count word is not a number this script knows" >&2
    return 1
  fi

  while IFS= read -r row; do
    [ -n "$row" ] && rows+=("$row")
  done < <(skill_states "$file")

  if [ "${#rows[@]}" -ne "${#DOCS_PIN_STATES[@]}" ]; then
    echo "the skill body's table names ${#rows[@]} state(s); this script declares ${#DOCS_PIN_STATES[@]}" >&2
    return 1
  fi

  if [ "$claimed" -ne "${#rows[@]}" ]; then
    echo "the skill body claims $claimed state(s); its table names ${#rows[@]}" >&2
    return 1
  fi

  for s in "${DOCS_PIN_STATES[@]}"; do
    found=0
    for row in "${rows[@]}"; do
      if [ "$row" = "$s" ]; then
        found=1
        break
      fi
    done
    if [ "$found" -ne 1 ]; then
      echo "the skill body's table does not name the state '$s' this script declares" >&2
      return 1
    fi
  done

  for row in "${rows[@]}"; do
    found=0
    for s in "${DOCS_PIN_STATES[@]}"; do
      if [ "$row" = "$s" ]; then
        found=1
        break
      fi
    done
    if [ "$found" -ne 1 ]; then
      echo "the skill body's table names '$row', a state this script never declares" >&2
      return 1
    fi
  done

  return 0
}

# expect_rejected <name> <mutated-file> <original-file>
#
# A mutation must be REJECTED, and it must have APPLIED — a mutation that did not change
# the body proves nothing. The reason the body was rejected is printed, so the self-test's
# own output says WHY each mutation died.
expect_rejected() {
  local name=$1 mutated=$2 original=$3 reason accepted
  if cmp -s "$mutated" "$original"; then
    echo "self-test FAIL: the $name mutation did not change the skill body — it proves nothing" >&2
    return 1
  fi
  reason=$(states_agree "$mutated" 2>&1)
  accepted=$?
  if [ "$accepted" -eq 0 ]; then
    echo "self-test FAIL: a skill body with $name must be REJECTED" >&2
    return 1
  fi
  echo "  rejected ($name): $reason"
  return 0
}

self_test() {
  local tmp rc=0
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN

  # A fixture manifest in the shape this repo's own uses: the var, then the check's
  # literal matcher.
  cat >"$tmp/ok.yml" <<'YAML'
        var:
            DOCS_REPO: https://github.com/opencharly/docs.git
            DOCS_REF: aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbb
        plan:
            - check: the cloned site is the pinned commit
              stdout:
                - contains: aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbb
YAML

  # The same manifest with the matcher still carrying the OLD sha: the tree disagrees
  # with itself, and the report must say so and fail.
  cat >"$tmp/disagree.yml" <<'YAML'
        var:
            DOCS_REPO: https://github.com/opencharly/docs.git
            DOCS_REF: aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbb
        plan:
            - check: the cloned site is the pinned commit
              stdout:
                - contains: cccccccccccccccccccccccccccccccccccccccc
YAML

  # The head a healthy case drives is DERIVED from the healthy fixture, never typed
  # here: a hand-typed value that differs from the fixture's DOCS_REF silently takes
  # the BEHIND path, and the case then proves nothing about the branch it names.
  local current behind
  current=$(grep -E '^[[:space:]]+DOCS_REF:' "$tmp/ok.yml" | awk '{print $2}')
  behind=dddddddddddddddddddddddddddddddddddddddd

  # The BEHIND case only means anything if the head it drives really differs from the
  # pin; assert that, so a future edit cannot make the two cases identical.
  if [ "$current" = "$behind" ]; then
    echo "self-test FAIL: the BEHIND case must drive a head that differs from the pin" >&2
    rc=1
  fi

  # 1. The healthy state: the pin IS the head, both occurrences present -> 0, and the
  #    report says so. The message is the assertion that proves the CURRENT branch was
  #    reached: the BEHIND branch exits 0 as well.
  run_case current "the healthy state must report the pin IS the head" 0 \
    "IS the docs repo's current main head" "$tmp/ok.yml" "$current" || rc=1

  # 2. The pin is BEHIND -> still green, because a pin that is behind is a state, and
  #    the report says BEHIND.
  run_case BEHIND "a pin that is behind must be REPORTED, not failed" 0 \
    "DOCS_REF is BEHIND the docs repo's main head" "$tmp/ok.yml" "$behind" || rc=1

  # 3. The two occurrences disagree -> red, and the report NAMES the state.
  run_case DISAGREE "a manifest whose two occurrences disagree must FAIL" 1 \
    "expected at least 2" "$tmp/disagree.yml" "$current" || rc=1

  # 4. The head could not be fetched -> the pin cannot be judged -> red.
  run_case UNJUDGEABLE "an unjudgeable pin must FAIL, not pass" 1 \
    "the pin's currency is UNJUDGEABLE" "$tmp/ok.yml" "" || rc=1

  # 5. No DOCS_REF at all -> unjudgeable -> red.
  printf 'defaults:\n    tag: auto\n' >"$tmp/none.yml"
  run_case UNJUDGEABLE "a manifest with no DOCS_REF must FAIL" 1 \
    "no DOCS_REF is declared" "$tmp/none.yml" "$current" || rc=1

  # 6. Every state this script declares must be PROVEN by a case: a state nobody drives
  #    is a state the script must not claim.
  local s d found
  for s in "${DOCS_PIN_STATES[@]}"; do
    found=0
    for d in "${DRIVEN_STATES[@]}"; do
      if [ "$d" = "$s" ]; then
        found=1
        break
      fi
    done
    if [ "$found" -ne 1 ]; then
      echo "self-test FAIL: the state '$s' is declared but no case drives it" >&2
      rc=1
    fi
  done

  # 7. The skill body must AGREE with the states this script declares — the count it
  #    claims, the rows it lists, and this script's own list must be the same states.
  #    The four mutations below prove the check DISCRIMINATES: a body claiming the wrong
  #    count, a body missing a row, a body carrying a row this script never declares, and
  #    a state this script declares that the body does not name. A mutation that does not
  #    apply proves nothing, so each one is checked for having applied.
  local skill="$repo_root/.agents/skills/docs-site/SKILL.md"
  if ! states_agree "$skill"; then
    echo "self-test FAIL: the skill body does not agree with the states this script declares" >&2
    rc=1
  fi

  local m_count="$tmp/skill-wrong-count.md"
  local m_missing="$tmp/skill-missing-row.md"
  local m_extra="$tmp/skill-extra-row.md"
  local word wrong_word

  word=$(awk '/reports one of [A-Za-z]+ states/ { for (i = 1; i <= NF; i++) if ($i == "of") { print $(i + 1); exit } }' "$skill")
  for wrong_word in one two three four five six seven eight nine ten; do
    if [ "$wrong_word" != "$word" ]; then
      break
    fi
  done

  # The wrong count: the body claims a number its table does not have.
  awk -v w="$wrong_word" '
    { if ($0 ~ /reports one of [A-Za-z]+ states/) sub(/one of [A-Za-z]+ states/, "one of " w " states"); print }
  ' "$skill" >"$m_count"

  # A missing row: the body drops one of the states it lists.
  awk '
    /reports one of [A-Za-z]+ states/ { seen = 1; print; next }
    seen && !dropped && /^\|[[:space:]]*\*\*[A-Za-z]+\*\*[[:space:]]*\|/ { dropped = 1; next }
    { print }
  ' "$skill" >"$m_missing"

  # An extra row: the body lists a state this script never declares.
  awk '
    /reports one of [A-Za-z]+ states/ { seen = 1; print; next }
    seen && !added && /^\|[[:space:]]*\*\*[A-Za-z]+\*\*[[:space:]]*\|/ {
      print
      print "| **STALE** | a state this script never declares | 1 |"
      added = 1
      next
    }
    { print }
  ' "$skill" >"$m_extra"

  expect_rejected "the wrong count" "$m_count" "$skill" || rc=1
  expect_rejected "a missing row" "$m_missing" "$skill" || rc=1
  expect_rejected "a row this script never declares" "$m_extra" "$skill" || rc=1

  # The fifth state: the script declares one the body does not name — exactly what
  # happens when a state is added to the code and the prose is not updated. The body must
  # then be REJECTED, so the state cannot be added silently.
  local saved_states=("${DOCS_PIN_STATES[@]}")
  local reason accepted
  DOCS_PIN_STATES+=(FUTURE)
  reason=$(states_agree "$skill" 2>&1)
  accepted=$?
  DOCS_PIN_STATES=("${saved_states[@]}")
  if [ "$accepted" -eq 0 ]; then
    echo "self-test FAIL: a skill body that does not name a state this script declares must be REJECTED" >&2
    rc=1
  else
    echo "  rejected (a state this script declares and the body does not name): $reason"
  fi

  rm -rf "$tmp"
  trap - RETURN
  if [ "$rc" -eq 0 ]; then
    echo "docs-pin self-test: OK — 5 report cases (2 green, 3 red), ${#DOCS_PIN_STATES[@]} states each proven driven, the skill-body agreement arm, and 4 mutations each proven rejected."
  fi
  return $rc
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

file="$repo_root/charly.yml"
repo=$(grep -E '^[[:space:]]+DOCS_REPO:' "$file" | awk '{print $2}')
if [ -z "$repo" ]; then
  echo "docs-pin: no DOCS_REPO is declared in charly.yml — the pin is UNJUDGEABLE" >&2
  exit 1
fi

live=$(git ls-remote "$repo" refs/heads/main 2>/dev/null | awk '{print $1}')
docs_pin_report "$file" "$repo" "$live"
exit $?
