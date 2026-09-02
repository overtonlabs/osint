---
name: verify-links
description: Verify that every link on the OSINT Connect site still works and still points at what its label claims. Use when asked to check links, audit the bookmarks, find dead links, refresh the list, or before publishing a change to public/index.html. Also use when a link check has failed in CI and the results need triage.
---

# Verify links

Run and interpret the link check for this repository. The script decides
*reachability*; you decide *correctness*, which is the part no status code can
answer.

## Step 1 — run the check

```bash
./scripts/check-links.sh
```

Export `GH_TOKEN` first if many GitHub links are being checked; without it the
GitHub API allows 60 requests/hour and results degrade to `UNKNOWN`.

Output is `VERDICT<TAB>URL<TAB>DETAIL` on stdout, one row per URL. The summary
goes to stderr.

## Step 2 — act on each verdict

| Verdict | What it means | What to do |
| --- | --- | --- |
| `OK` | Reachable, and canonical where checkable | Nothing automatic. See step 3. |
| `REDIRECT` | Reachable, final URL differs | Update the `href` **and** the visible text if the visible text is a URL. Re-run. |
| `MOVED` | GitHub repo renamed or transferred | Update to the canonical `full_name` in the detail column. Confirm it is still the same project and not a squatted name. |
| `DEAD` | Verified absent | Find a maintained replacement, or remove the entry. Never leave a dead link in place. |
| `UNKNOWN` | No conclusion reached | Re-run that URL alone. If it persists, check it by hand and say plainly that it is unverified — do not report it as working. |
| `SKIP` | Unverifiable by automation | Only LinkedIn today. Check by hand if it matters; never convert to `OK`. |

## Step 3 — the part the script cannot do

A `200` proves the server answered. It does not prove the destination still
*is* what the page says it is. This is where real rot hides, and it needs a
human-style judgement:

* **Does the label still describe the destination?** `lanmaster53/recon-ng` sat
  on this page labelled "Linux OS with OSINT Tools" from the first commit until
  2026-09-01. It is a Python reconnaissance framework. The link was never
  broken — the claim was.
* **Is the project still alive?** For GitHub entries, check `pushed_at` and
  whether the repository is archived. A repository last touched four years ago
  is worth flagging even though it resolves.
* **Has the tool changed model?** A free tool that has become a paid-only
  product, or a service that now requires an account, deserves a note or
  removal.
* **Is it now parked or squatted?** A domain that lapsed and was re-registered
  answers `200` from a completely different owner. Read what actually came
  back.

Fetch and read anything that looks suspicious. Do not infer from the URL.

## Step 4 — report

Give a severity-ranked list: `DEAD` and `MOVED` first, then mislabelled
entries, then `REDIRECT`, then staleness observations. For each one state the
file and line, what is wrong, and the proposed replacement. Ask before removing
an entry — deciding a resource is no longer worth listing is the maintainer's
call, not yours.

## Constraints

* Never mark a link verified that you did not actually check.
* Never widen `check-links.sh` to treat an inconclusive response as success.
  If you add a host strategy, add a control test proving it can fail — see
  `tests/test-check-links.sh`.
* Edits to links happen in `public/index.html`, which is the source of truth
  for the published site.
* Run `./tests/test-site-invariants.sh` after editing the page; it enforces the
  `rel="noopener noreferrer"` rule and the custom-domain pinning described in
  `AGENTS.md`.
