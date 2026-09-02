# AGENTS.md

Canonical guidance for contributors and AI coding agents working in this
repository. `CLAUDE.md` points here; this file is the single source.

## What this project is

OSINT Connect is a **curated list of links**, published as one static HTML page
at <https://osintconnect.com/>. It has no build step, no runtime, no
dependencies and no application code. `public/index.html` *is* the product.

Because the deliverable is a list of links, the project's primary defect class
is not a crash — it is a link that quietly stops pointing where its label says
it points. Everything below follows from that.

## Design rules that must not be violated

1. **No build step.** `public/` is uploaded to GitHub Pages verbatim. Do not
   introduce a bundler, a package manager, a templating system or a CSS
   framework. A contributor must be able to edit one file and see the result by
   opening it in a browser.
2. **No third-party runtime assets.** No CDN scripts, no web fonts, no
   analytics, no trackers. Visitors to an OSINT resource should not be
   broadcast to third parties by the act of reading the page.
3. **Every anchor keeps `target="_blank" rel="noopener noreferrer"`.** The
   `noreferrer` half is a privacy control, not boilerplate: without it every
   destination learns that its visitor arrived from `osintconnect.com`. Modern
   browsers imply `noopener` for `target="_blank"`, but `noreferrer` is never
   implied.
4. **`public/CNAME` must not be deleted.** See "Landmines" below.
5. **Labels must describe what a resource actually is.** A wrong label is a bug
   of the same severity as a dead link — see landmine 3.

## Layout

```
public/index.html            the entire site; every link lives here
public/CNAME                 pins the osintconnect.com custom domain
public/robots.txt            crawler directives
public/sitemap.xml           sitemap (single URL)
scripts/check-links.sh       link verification engine (curl only)
tests/test-site-invariants.sh      offline checks on the shipped artifact
tests/test-check-links.sh          control tests for the verification strategies
.github/workflows/static.yml       deploy public/ to Pages on push to main
.github/workflows/check-links.yml  link check on PRs and monthly
.claude/skills/verify-links/       agent-facing wrapper for link triage
CHANGELOG.md                       dated record of changes
```

## Interface contract: `scripts/check-links.sh`

Agents and CI depend on this exact behaviour. Do not change it silently.

* **Invocation:** `scripts/check-links.sh [-h|--help] [-q|--quiet] [--strict] [FILE...]`
  With no `FILE`, scans `public/index.html` and `README.md`.
* **Output:** one tab-separated record per URL on stdout —
  `VERDICT<TAB>URL<TAB>DETAIL` — sorted by URL. Progress and the summary go to
  **stderr**, so stdout stays parseable.
* **Verdicts:** `OK`, `REDIRECT`, `MOVED`, `DEAD`, `UNKNOWN`, `SKIP`.
* **Exit status:** `0` = no `DEAD` and no `MOVED`; `1` = at least one `DEAD` or
  `MOVED` (also any `REDIRECT` under `--strict`); `2` = usage error or `curl`
  missing.
* **Dependencies:** `curl` and coreutils. Nothing else. Keep it that way — CI
  relies on the script running on a bare runner.
* `GH_TOKEN` or `GITHUB_TOKEN`, if set, raises the GitHub API rate limit from
  60 to 5000 requests/hour. The script must keep working without either.

## Landmines

These exist because each one has already caused a real failure or a false
claim in this repository.

**1. `public/CNAME` is what keeps the custom domain attached.**
Before 2026-09-01 the `osintconnect.com` domain existed *only* as a repository
Pages setting, with no `CNAME` file in the deployed artifact. That setting is
not reliably preserved when a repository is transferred between owners.
Committing `CNAME` into `public/` makes each deploy re-assert the domain.
Deleting it re-creates the original fragility.

**2. Transferring the repository mid-workflow breaks the Pages deploy.**
`actions/deploy-pages` mints an OIDC token whose audience is the owner at
*queue* time. If ownership changes before the deploy step runs, it fails with
`Invalid actions OIDC token due to Invalid audience`. This is transient: simply
re-run the workflow after the transfer settles. It is not a permissions problem
and needs no configuration change.

**3. `x.com` returns HTTP 200 for accounts that do not exist.**
The profile page is a client-side JavaScript shell, so a plain status-code
check passes for *any* handle and is therefore worthless. Account existence is
only observable through the OpenGraph `<title>` served to crawler user agents,
which returns `User Profile Not Found` for a missing account. `verify_x()` in
`check-links.sh` relies on this, and `tests/test-check-links.sh` control-tests
it against a deliberately bogus handle so the check cannot silently degrade
into one that can never fail.

**4. `github.com` hides renames behind a 200.**
Browsing to a transferred repository silently redirects, so the web UI cannot
distinguish a current URL from a stale one. `verify_github()` therefore queries
`api.github.com` **with `-L`**: the API answers `301` for a renamed or
transferred repository and the redirect target carries the canonical
`full_name`, while a repository that genuinely does not exist still answers
`404`. Dropping `-L` collapses `MOVED` into `DEAD`.

**5. LinkedIn is permanently unverifiable.**
`www.linkedin.com` answers HTTP `999` to all automation regardless of whether
the profile exists. It is reported `SKIP`, deliberately. Do not "fix" this by
treating `999` as success — that would report a verdict the check cannot
support.

**6. A wrong label is a real bug.** `github.com/lanmaster53/recon-ng` was
labelled "Linux OS with OSINT Tools" from the repository's first commit until
2026-09-01. recon-ng is a Python reconnaissance framework, not a Linux
distribution. No automated check catches this class of error; it requires
reading what the destination actually is.

## How to make the common changes

**Add a link.** Add an `<li>` to the appropriate `<h2>` section of
`public/index.html`, matching the surrounding form:

```html
<li>Label: <a href="https://example.com/" target="_blank" rel="noopener noreferrer">https://example.com/</a></li>
```

Sections that list projects or accounts use the label as the anchor text
instead. Then run `./scripts/check-links.sh` and confirm the new URL reports
`OK`, not `REDIRECT`.

**Fix a `REDIRECT`.** Replace the URL with the destination the script reports,
in both the `href` and the visible text where the visible text is a URL.

**Add a new host-specific verification strategy.** Add a `verify_*` function,
route to it from `verify_one()`, export it in `main()` alongside the others
(the `xargs` workers run in subshells and need `export -f`), and add a
control test proving it can return a failing verdict for a resource that does
not exist. A check that cannot fail is worse than no check.

**Change the section structure.** `public/index.html` is the only source of
truth for the published list. The README intentionally does **not** mirror the
link list any more, because maintaining two copies guaranteed drift.

## Verification boundary

State this accurately; do not overclaim.

A green `check-links.sh` run proves:

* every URL resolves over HTTPS and returns a success status;
* each X account in the list currently exists;
* each GitHub repository and account in the list currently exists under the
  exact owner/name used in the link.

It does **not** prove:

* that a destination still does what its label claims. A `200` from a
  reverse-image-search tool means the server is up, not that it is still a
  reverse-image-search tool. Labels are reviewed by hand.
* anything about the LinkedIn profile (`SKIP`, see landmine 5);
* that the destination is safe, reputable, or worth using. The page says so:
  links are not endorsements.
* that the rendered page looks correct. There is no visual or HTML-validity
  test.

## Release process

There are no versions or releases. `main` is the deployed state.

1. Edit, then run all three gates locally:
   ```bash
   ./tests/test-site-invariants.sh   # offline, fast
   ./tests/test-check-links.sh       # network; control tests
   ./scripts/check-links.sh          # the actual link check
   ```
2. Open a PR. `.github/workflows/check-links.yml` runs the same three.
3. Merge to `main`. `.github/workflows/static.yml` uploads `public/` and
   deploys to <https://osintconnect.com/>.
4. Record the change under `## [Unreleased]` in `CHANGELOG.md`.

DNS is outside GitHub: `osintconnect.com` is registered through Squarespace
Domains, and its zone is served by Google Cloud DNS. The apex `A` records point
at GitHub's shared anycast addresses (`185.199.108–111.153`), which are the
same for every Pages site and encode nothing about the owning account — so a
repository transfer never requires a DNS change.
