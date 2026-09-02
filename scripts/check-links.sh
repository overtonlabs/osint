#!/usr/bin/env bash
#
# check-links.sh -- verify every outbound link in the OSINT Connect site.
#
# Purpose
#   This repository is, in substance, a curated list of links. A dead or
#   silently redirected link is therefore the project's primary defect class.
#   HTTP 200 alone is NOT sufficient evidence that a link is healthy, so this
#   script dispatches each URL to a host-specific verification strategy.
#
# Key responsibilities
#   - Extract every http(s) URL from the published HTML page and the README.
#   - Verify each URL using a strategy that is actually capable of failing for
#     that host.
#   - Emit a per-URL verdict and exit non-zero when any link is broken.
#
# Known host-specific behaviour (see AGENTS.md, "Verification boundary")
#   x.com        Returns HTTP 200 for handles that do NOT exist -- the page is
#                a JavaScript shell rendered client-side. Account existence is
#                only observable via the OpenGraph title served to crawler
#                user agents, which returns "User Profile Not Found" for a
#                missing account.
#   github.com   Silently redirects renamed or transferred repositories, so a
#                200 can hide a stale owner or name. The REST API reports the
#                canonical full_name and is used instead.
#   linkedin.com Returns HTTP 999 to all automation regardless of whether the
#                profile exists. Unverifiable here; reported as SKIP.
#
# Verdicts
#   OK        Verified reachable, and canonical where the host allows checking.
#   REDIRECT  Reachable, but the final URL differs -- the link should be updated.
#   MOVED     Resource exists under a different canonical name (GitHub rename).
#   DEAD      Verified absent.
#   UNKNOWN   The check could not reach a conclusion (rate limit, network).
#   SKIP      Host is known-unverifiable by automation.
#
# Exit status
#   0  no DEAD and no MOVED links
#   1  at least one DEAD or MOVED link
#   2  usage error or missing dependency
#
# Related files
#   .claude/skills/verify-links/SKILL.md  agent-facing wrapper for triage
#   .github/workflows/check-links.yml     scheduled execution
#
set -uo pipefail

# Scratch files are global rather than local to main() so the EXIT trap can
# still see them once main() has returned.
urls_file=''
results_file=''

readonly UA_BROWSER='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
readonly UA_CRAWLER='Twitterbot/1.0'
readonly TIMEOUT=25
readonly PARALLEL=4

# Default sources scanned when no file arguments are supplied.
readonly DEFAULT_SOURCES=('public/index.html' 'README.md')

# Usage text, per the repository convention that any script taking arguments
# must explain itself.
usage() {
  cat <<'USAGE'
Usage: scripts/check-links.sh [OPTIONS] [FILE...]

Verify every outbound http(s) link found in FILEs. With no FILE arguments,
scans public/index.html and README.md.

Options:
  -h, --help     Show this help text and exit.
  -q, --quiet    Print only failures and the final summary.
      --strict   Treat REDIRECT as a failure (exit 1) in addition to
                 DEAD and MOVED.

Environment:
  GH_TOKEN / GITHUB_TOKEN
                 Optional. Raises the GitHub REST API rate limit from 60 to
                 5000 requests/hour. Not required for a single run.

Exit status:
  0  no DEAD and no MOVED links
  1  at least one DEAD or MOVED link
  2  usage error or missing dependency
USAGE
}

# Timestamped progress line, kept on stderr so stdout stays parseable.
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Extracts http(s) URLs from HTML href attributes and Markdown link targets.
# Both forms are handled because the same link set is duplicated across
# public/index.html and README.md and must stay in sync.
extract_urls() {
  local file
  for file in "$@"; do
    [ -f "${file}" ] || { log "WARN: no such file: ${file}"; continue; }
    grep -oE 'href="https?://[^"]+"' "${file}" 2>/dev/null | sed 's/^href="//; s/"$//'
    grep -oE '\]\(https?://[^)]+\)' "${file}" 2>/dev/null | sed 's/^](//; s/)$//'
  done | sort -u
}

# Verifies an X/Twitter profile. A plain request is useless here: the server
# answers 200 for any handle. The crawler user agent receives a server-rendered
# OpenGraph title instead, which does distinguish a real account from a missing
# one -- this is control-tested in the test suite.
verify_x() {
  local url="$1" handle title=""
  handle="${url##*/}"
  handle="${handle%%\?*}"

  # x.com throttles bursts of crawler traffic by returning an empty body. Retry
  # with backoff so throttling degrades into a slower check rather than into an
  # inconclusive one.
  local attempt
  for attempt in 1 2 3; do
    title=$(curl -sS -A "${UA_CRAWLER}" --max-time "${TIMEOUT}" "${url}" 2>/dev/null \
            | grep -oE '<title>[^<]*</title>' | head -1 | sed 's/<[^>]*>//g')
    [ -n "${title}" ] && break
    sleep $((attempt * 3))
  done

  if [ -z "${title}" ]; then
    printf 'UNKNOWN\t%s\tno OpenGraph title returned (rate limited?)\n' "${url}"
  elif printf '%s' "${title}" | grep -qi 'not found'; then
    printf 'DEAD\t%s\t%s\n' "${url}" "${title}"
  elif printf '%s' "${title}" | grep -qiF "(@${handle})"; then
    printf 'OK\t%s\t%s\n' "${url}" "${title}"
  else
    # The account resolved but under different capitalisation. X treats handles
    # case-insensitively, so the link works; only the displayed text is stale.
    printf 'OK\t%s\tresolved, canonical casing differs: %s\n' "${url}" "${title}"
  fi
}

# Verifies a GitHub user, organisation or repository through the REST API.
# The API is used rather than the web UI because github.com transparently
# redirects renamed and transferred repositories, hiding staleness behind 200.
verify_github() {
  local url="$1" path owner repo auth=() body full_name
  path="${url#*github.com/}"
  path="${path%%\?*}"
  path="${path%%#*}"
  path="${path%/}"

  [ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ] &&
    auth=(-H "Authorization: Bearer ${GH_TOKEN:-${GITHUB_TOKEN}}")

  if [ -z "${path}" ]; then
    verify_generic "${url}"
    return
  fi

  # Only the first two path segments identify the resource. Deeper paths such
  # as /issues or /tree/main hang off the same repository and are validated by
  # validating that repository.
  owner="${path%%/*}"
  repo="${path#"${owner}"}"
  repo="${repo#/}"
  repo="${repo%%/*}"

  if [ -z "${repo}" ]; then
    # Single path segment: a user or organisation profile.
    if curl -sSL "${auth[@]}" --max-time "${TIMEOUT}" \
         -o /dev/null -w '%{http_code}' \
         "https://api.github.com/users/${owner}" 2>/dev/null | grep -q '^200$'; then
      printf 'OK\t%s\taccount exists\n' "${url}"
    else
      printf 'DEAD\t%s\tno such GitHub account: %s\n' "${url}" "${owner}"
    fi
    return
  fi

  # -L is required here. The API answers 301 for a renamed or transferred
  # repository and the redirect target carries the canonical full_name, which
  # is what makes the MOVED verdict reachable. A repository that genuinely
  # does not exist still answers 404, so following redirects does not weaken
  # the DEAD verdict.
  body=$(curl -sSL "${auth[@]}" --max-time "${TIMEOUT}" \
         "https://api.github.com/repos/${owner}/${repo}" 2>/dev/null)
  full_name=$(printf '%s' "${body}" | sed -n 's/.*"full_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

  if [ -z "${full_name}" ]; then
    if printf '%s' "${body}" | grep -q 'rate limit'; then
      printf 'UNKNOWN\t%s\tGitHub API rate limit reached; set GH_TOKEN\n' "${url}"
    else
      printf 'DEAD\t%s\tno such repository: %s/%s\n' "${url}" "${owner}" "${repo}"
    fi
  elif [ "$(printf '%s' "${full_name}" | tr '[:upper:]' '[:lower:]')" \
      != "$(printf '%s' "${owner}/${repo}" | tr '[:upper:]' '[:lower:]')" ]; then
    printf 'MOVED\t%s\trenamed or transferred to %s\n' "${url}" "${full_name}"
  else
    printf 'OK\t%s\t%s\n' "${url}" "${full_name}"
  fi
}

# Verifies any other host by following redirects and comparing the final URL
# against the original. Differences that are purely cosmetic (a trailing slash,
# or an http -> https upgrade) are not reported as drift.
verify_generic() {
  local url="$1" result code effective norm_a norm_b

  result=$(curl -sS -L -A "${UA_BROWSER}" --max-time "${TIMEOUT}" \
           -o /dev/null -w '%{http_code}|%{url_effective}' "${url}" 2>/dev/null)
  code="${result%%|*}"
  effective="${result#*|}"

  # Some servers reject HEAD-like probes or hang up on an unknown client;
  # retry once requesting only the first bytes of the body.
  if [ "${code}" = "000" ] || [ "${code}" = "405" ] || [ "${code}" = "501" ]; then
    result=$(curl -sS -L -A "${UA_BROWSER}" --max-time "${TIMEOUT}" -r 0-2048 \
             -o /dev/null -w '%{http_code}|%{url_effective}' "${url}" 2>/dev/null)
    code="${result%%|*}"
    effective="${result#*|}"
  fi

  norm_a=$(printf '%s' "${url}"       | sed 's|^https\?://||; s|/$||')
  norm_b=$(printf '%s' "${effective}" | sed 's|^https\?://||; s|/$||')

  case "${code}" in
    2*)
      if [ "${norm_a}" != "${norm_b}" ]; then
        printf 'REDIRECT\t%s\tnow resolves to %s\n' "${url}" "${effective}"
      else
        printf 'OK\t%s\tHTTP %s\n' "${url}" "${code}"
      fi
      ;;
    000) printf 'UNKNOWN\t%s\tno response within %ss\n' "${url}" "${TIMEOUT}" ;;
    404|410) printf 'DEAD\t%s\tHTTP %s\n' "${url}" "${code}" ;;
    *)   printf 'UNKNOWN\t%s\tHTTP %s\n' "${url}" "${code}" ;;
  esac
}

# Routes one URL to the strategy capable of producing a real failure for its
# host. Hosts with no such strategy are skipped explicitly rather than being
# given a verdict the check cannot actually support.
verify_one() {
  local url="$1"
  case "${url}" in
    *linkedin.com/*)
      printf 'SKIP\t%s\tLinkedIn returns HTTP 999 to all automation; verify by hand\n' "${url}"
      ;;
    https://x.com/*|https://twitter.com/*)
      verify_x "${url}"
      ;;
    *github.com/*)
      verify_github "${url}"
      ;;
    *)
      verify_generic "${url}"
      ;;
  esac
}

main() {
  local quiet=0 strict=0 sources=()
  local total=0 ok=0 dead=0 moved=0 redirect=0 unknown=0 skip=0

  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)  usage; exit 0 ;;
      -q|--quiet) quiet=1; shift ;;
      --strict)   strict=1; shift ;;
      -*)         echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
      *)          sources+=("$1"); shift ;;
    esac
  done

  command -v curl >/dev/null 2>&1 || { echo "check-links: curl is required" >&2; exit 2; }

  [ ${#sources[@]} -eq 0 ] && sources=("${DEFAULT_SOURCES[@]}")

  urls_file=$(mktemp)
  results_file=$(mktemp)
  trap 'rm -f "${urls_file:-}" "${results_file:-}"' EXIT

  extract_urls "${sources[@]}" > "${urls_file}"
  total=$(wc -l < "${urls_file}" | tr -d ' ')

  if [ "${total}" -eq 0 ]; then
    echo "check-links: no URLs found in: ${sources[*]}" >&2
    exit 2
  fi

  log "checking ${total} unique URLs from: ${sources[*]}"

  export -f verify_one verify_x verify_github verify_generic
  export UA_BROWSER UA_CRAWLER TIMEOUT
  xargs -P "${PARALLEL}" -I{} bash -c 'verify_one "$@"' _ {} \
    < "${urls_file}" | sort -t"$(printf '\t')" -k2 > "${results_file}"

  ok=$(grep -c '^OK'       "${results_file}" || true)
  dead=$(grep -c '^DEAD'   "${results_file}" || true)
  moved=$(grep -c '^MOVED' "${results_file}" || true)
  redirect=$(grep -c '^REDIRECT' "${results_file}" || true)
  unknown=$(grep -c '^UNKNOWN'   "${results_file}" || true)
  skip=$(grep -c '^SKIP'   "${results_file}" || true)

  if [ "${quiet}" -eq 1 ]; then
    grep -vE '^OK' "${results_file}" || true
  else
    cat "${results_file}"
  fi

  echo
  log "total=${total} ok=${ok} redirect=${redirect} moved=${moved} dead=${dead} unknown=${unknown} skip=${skip}"

  if [ "${dead}" -gt 0 ] || [ "${moved}" -gt 0 ]; then
    log "FAIL: ${dead} dead, ${moved} moved"
    exit 1
  fi
  if [ "${strict}" -eq 1 ] && [ "${redirect}" -gt 0 ]; then
    log "FAIL (--strict): ${redirect} redirected"
    exit 1
  fi
  log "PASS"
}

main "$@"
