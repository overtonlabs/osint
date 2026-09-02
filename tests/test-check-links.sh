#!/usr/bin/env bash
#
# test-check-links.sh -- prove each verification strategy can actually fail.
#
# Purpose
#   check-links.sh exists because HTTP 200 is not evidence of a healthy link on
#   several of the hosts this site points at. A strategy that silently degrades
#   into one that always passes would be worse than no check at all, because it
#   would report confidence it does not have. Every strategy therefore gets a
#   control case: a resource that genuinely does not exist, which must produce
#   a failing verdict.
#
# Key responsibilities
#   - Control-test verify_x against a handle that does not exist.
#   - Control-test verify_github against a repository that does not exist.
#   - Assert renamed repositories are reported MOVED, not DEAD or OK.
#   - Assert deep repository paths are attributed to their repository.
#   - Assert the documented exit-status contract.
#
# Requires network access. The offline checks live in
# tests/test-site-invariants.sh.
#
# Related files
#   scripts/check-links.sh  the code under test
#   AGENTS.md               "Landmines", which these tests pin down
#
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

readonly CHECKER='scripts/check-links.sh'
pass=0
fail=0
fixture=$(mktemp -d)
trap 'rm -rf "${fixture}"' EXIT

# Runs the checker over a single URL and returns the verdict column.
verdict_for() {
  local url="$1" file="${fixture}/one.html"
  printf '<a href="%s">x</a>\n' "${url}" > "${file}"
  "${CHECKER}" "${file}" 2>/dev/null | awk -F'\t' 'NR==1{print $1}'
}

# Asserts the verdict for a URL, printing the actual value when it differs.
assert_verdict() {
  local description="$1" url="$2" expected="$3" actual
  actual=$(verdict_for "${url}")
  if [ "${actual}" = "${expected}" ]; then
    printf '  ok   %s\n' "${description}"
    pass=$((pass + 1))
  else
    printf '  FAIL %s (expected %s, got %s)\n' "${description}" "${expected}" "${actual:-<none>}"
    fail=$((fail + 1))
  fi
}

assert_exit() {
  local description="$1" url="$2" expected="$3" file="${fixture}/one.html" actual
  printf '<a href="%s">x</a>\n' "${url}" > "${file}"
  "${CHECKER}" "${file}" >/dev/null 2>&1
  actual=$?
  if [ "${actual}" = "${expected}" ]; then
    printf '  ok   %s\n' "${description}"
    pass=$((pass + 1))
  else
    printf '  FAIL %s (expected exit %s, got %s)\n' "${description}" "${expected}" "${actual}"
    fail=$((fail + 1))
  fi
}

echo "check-links strategies (requires network)"

# Landmine 3: x.com answers 200 for any handle, so this control case is the
# only thing standing between the X strategy and a check that cannot fail.
assert_verdict "X: nonexistent handle is DEAD" \
  "https://x.com/zzz_definitely_not_a_real_handle_9910" "DEAD"
assert_verdict "X: real handle is OK" \
  "https://x.com/bellingcat" "OK"

# Landmine 4: github.com hides renames behind a redirect, so the API is queried
# with -L. These two cases pin both halves of that behaviour.
assert_verdict "GitHub: nonexistent repository is DEAD" \
  "https://github.com/overtonlabs/definitely-not-a-real-repo-9910" "DEAD"
assert_verdict "GitHub: live repository is OK" \
  "https://github.com/sherlock-project/sherlock" "OK"
assert_verdict "GitHub: transferred repository is MOVED, not DEAD" \
  "https://github.com/Steve0verton/osint" "MOVED"
assert_verdict "GitHub: deep path is attributed to its repository" \
  "https://github.com/Steve0verton/osint/issues" "MOVED"
assert_verdict "GitHub: nonexistent account is DEAD" \
  "https://github.com/zz-no-such-account-9910" "DEAD"

# Landmine 5: LinkedIn cannot be verified, and must say so rather than guess.
assert_verdict "LinkedIn is SKIP, never OK" \
  "https://www.linkedin.com/in/overton/" "SKIP"

# Interface contract: exit status.
assert_exit "exit 1 when a link is DEAD" \
  "https://x.com/zzz_definitely_not_a_real_handle_9910" 1
assert_exit "exit 0 when all links are OK" \
  "https://github.com/sherlock-project/sherlock" 0

echo
echo "  passed=${pass} failed=${fail}"
[ "${fail}" -eq 0 ]
