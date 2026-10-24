#!/usr/bin/env bash
# docs-pin-report.sh — REPORT the DOCS_REF pin's state.
#
# The pin this repo holds is the docs repo's commit, and the `check-docs` bed clones the
# published site at that commit. The bed proves the IMAGE holds the pin; nothing in the
# org proved the pin is the docs repo's CURRENT head, and nothing proved the two
# occurrences of the sha in charly.yml agree. A control that FAILS on a pin that is
# merely behind cannot live in a gate — it is red for every docs merge that has not been
# re-pinned here — so this REPORTS:
#
#   * BEHIND  — DOCS_REF is not the docs repo's current main head. That is a STATE, not a
#               defect: the advance is available NOW in opencharly/docs, and this repo's
#               pin moves when someone takes it. Reported; the exit status is 0.
#   * DISAGREE — the two occurrences of the sha in charly.yml do not agree. That is the
#               tree contradicting ITSELF, and the `docs-site-pinned-commit` check's
#               literal would assert a commit the image never builds. A defect; the
#               exit status is 1.
#   * UNJUDGEABLE — the docs repo's main head could not be fetched, so the pin's currency
#               cannot be judged at all. The org pin contract makes that a FAILURE and
#               not a pass: a gate that cannot judge is not a gate.
#
# The exit status is therefore 0 for every state a healthy tree can be in, and 1 only for
# the two that are not.
#
# Usage:
#   bash scripts/docs-pin-report.sh              # report the pin's state
#   bash scripts/docs-pin-report.sh --self-test  # prove the report discriminates
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$here/.." && pwd)

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
    echo "docs-pin: no DOCS_REF is declared in $(basename "$file") — the pin is UNJUDGEABLE" >&2
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
    echo "docs-pin: the pinned sha appears $occurrences time(s) in $(basename "$file"); expected at least 2" >&2
    echo "  (DOCS_REF plus the docs-site-pinned-commit check's stdout matcher)" >&2
    echo "  A stale literal means the anti-staleness check asserts the WRONG commit." >&2
    return 1
  fi

  if [ -z "$live" ]; then
    echo "docs-pin: could not fetch $repo main HEAD — the pin's currency is UNJUDGEABLE" >&2
    echo "  A pin the workflow cannot judge is a failure, not a pass (the org pin contract)." >&2
    return 1
  fi

  if [ "$declared" != "$live" ]; then
    echo "docs-pin: DOCS_REF is BEHIND the docs repo's main head."
    echo "  DOCS_REF: $declared"
    echo "  docs main: $live"
    echo "  Reported, not failed: a pin that is behind is a state, not a defect. The advance"
    echo "  is available NOW in opencharly/docs — re-pin BOTH occurrences in charly.yml to take it."
    return 0
  fi

  echo "docs-pin: DOCS_REF ($declared) IS the docs repo's current main head; both occurrences present."
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

  local current=aaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbb
  local behind=dddddddddddddddddddddddddddddddddddddddd

  # 1. The healthy state: the pin IS the head, both occurrences present -> 0.
  docs_pin_report "$tmp/ok.yml" "https://example.invalid/docs.git" "$current" >/dev/null
  if [ $? -ne 0 ]; then
    echo "self-test FAIL: the healthy state must report green" >&2
    rc=1
  fi

  # 2. The pin is BEHIND -> still green, because a pin that is behind is a state.
  docs_pin_report "$tmp/ok.yml" "https://example.invalid/docs.git" "$behind" >/dev/null
  if [ $? -ne 0 ]; then
    echo "self-test FAIL: a pin that is behind must be REPORTED, not failed" >&2
    rc=1
  fi

  # 3. The two occurrences disagree -> red.
  docs_pin_report "$tmp/disagree.yml" "https://example.invalid/docs.git" "$current" >/dev/null
  if [ $? -eq 0 ]; then
    echo "self-test FAIL: a manifest whose two occurrences disagree must FAIL" >&2
    rc=1
  fi

  # 4. The head could not be fetched -> the pin cannot be judged -> red.
  docs_pin_report "$tmp/ok.yml" "https://example.invalid/docs.git" "" >/dev/null
  if [ $? -eq 0 ]; then
    echo "self-test FAIL: an unjudgeable pin must FAIL, not pass" >&2
    rc=1
  fi

  # 5. No DOCS_REF at all -> unjudgeable -> red.
  printf 'defaults:\n    tag: auto\n' >"$tmp/none.yml"
  docs_pin_report "$tmp/none.yml" "https://example.invalid/docs.git" "$current" >/dev/null
  if [ $? -eq 0 ]; then
    echo "self-test FAIL: a manifest with no DOCS_REF must FAIL" >&2
    rc=1
  fi

  rm -rf "$tmp"
  trap - RETURN
  if [ $rc -eq 0 ]; then
    echo "docs-pin self-test: OK — 5 cases, each discriminating."
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
