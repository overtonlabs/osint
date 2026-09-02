#!/usr/bin/env bash
#
# test-site-invariants.sh -- offline checks on the published artifact.
#
# Purpose
#   Protects the design rules and landmines recorded in AGENTS.md that no
#   link checker can catch, because they concern the shape of the shipped
#   files rather than the reachability of their destinations.
#
# Key responsibilities
#   - Assert the custom domain is pinned into the deploy artifact.
#   - Assert every outbound anchor carries the referrer-suppressing rel.
#   - Assert no stale repository owner ships to visitors.
#   - Assert the domain agrees across CNAME, canonical, sitemap and robots.
#
# These tests require no network access and must stay that way; the
# network-dependent checks live in tests/test-check-links.sh.
#
# Related files
#   AGENTS.md                  the rules these tests enforce
#   tests/test-check-links.sh  network-dependent verification tests
#
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

pass=0
fail=0

# Records a single assertion result and keeps the tally.
assert() {
  local description="$1" condition="$2"
  if [ "${condition}" = "0" ]; then
    printf '  ok   %s\n' "${description}"
    pass=$((pass + 1))
  else
    printf '  FAIL %s\n' "${description}"
    fail=$((fail + 1))
  fi
}

echo "site invariants"

# Landmine 1: the custom domain must be re-asserted by every deploy, not left
# to a repository setting that a transfer can drop.
[ -f public/CNAME ]; assert "public/CNAME exists" $?
domain=$(tr -d '[:space:]' < public/CNAME 2>/dev/null || true)
[ "${domain}" = "osintconnect.com" ]; assert "public/CNAME pins osintconnect.com" $?

# Design rule 3: rel="noopener noreferrer" on every outbound anchor. Counted by
# occurrence rather than by line, because one line carries two anchors.
anchors=$(grep -o '<a href="http' public/index.html | wc -l | tr -d ' ')
protected=$(grep -o 'rel="noopener noreferrer"' public/index.html | wc -l | tr -d ' ')
[ "${anchors}" -gt 0 ] && [ "${anchors}" = "${protected}" ]
assert "all ${anchors} outbound anchors set rel=noopener noreferrer (found ${protected})" $?

# The repository moved to the overtonlabs organisation; nothing shipped to a
# visitor, and nothing in the README, may still name the previous owner.
! grep -rq 'Steve0verton' public/ README.md 2>/dev/null
assert "no stale Steve0verton reference in public/ or README.md" $?

# Design rule 2: no third-party runtime assets may be pulled by the page.
! grep -qE '<script[^>]+src=|<link[^>]+rel="stylesheet"[^>]+href="http' public/index.html
assert "no external scripts or stylesheets" $?

# The disclaimer must appear on the page itself, not only in the README.
grep -q 'not endorsements' public/index.html
assert "disclaimer present in public/index.html" $?

# The domain must agree everywhere it is written down.
grep -q "href=\"https://${domain}/\"" public/index.html
assert "canonical link matches ${domain}" $?
grep -q "https://${domain}/sitemap.xml" public/robots.txt
assert "robots.txt sitemap URL matches ${domain}" $?
grep -q "<loc>https://${domain}/</loc>" public/sitemap.xml
assert "sitemap loc matches ${domain}" $?

python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('public/sitemap.xml')" 2>/dev/null
assert "sitemap.xml is well-formed XML" $?

# The interface contract in AGENTS.md promises these.
[ -x scripts/check-links.sh ]; assert "check-links.sh is executable" $?
scripts/check-links.sh --help >/dev/null 2>&1; assert "check-links.sh --help exits 0" $?

echo
echo "  passed=${pass} failed=${fail}"
[ "${fail}" -eq 0 ]
