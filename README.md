# OSINT Connect

[![Deploy](https://github.com/overtonlabs/osint/actions/workflows/static.yml/badge.svg)](https://github.com/overtonlabs/osint/actions/workflows/static.yml)
[![Link check](https://github.com/overtonlabs/osint/actions/workflows/check-links.yml/badge.svg)](https://github.com/overtonlabs/osint/actions/workflows/check-links.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

A curated collection of open source intelligence (OSINT) bookmarks, tools and
references, published as a single static page at **<https://osintconnect.com/>**.

**Links are not endorsements or recommendations. Use at your own risk and discretion.**

## Quick start

There is no build step, no dependency to install and no server to run. The site
is one self-contained HTML file.

```bash
git clone https://github.com/overtonlabs/osint.git
cd osint
open public/index.html          # macOS; use xdg-open on Linux
```

To verify that every link on the page still resolves:

```bash
./scripts/check-links.sh
```

The full set of gates, all of which CI also runs:

```bash
./tests/test-site-invariants.sh   # offline: domain pinning, rel attributes, disclaimer
./tests/test-check-links.sh       # network: proves each link strategy can still fail
./scripts/check-links.sh          # the actual link check
```

They need nothing but `bash`, `curl` and `python3` — no package manager, no
install step.

## Repository layout

| Path | Purpose |
| --- | --- |
| `public/index.html` | The entire site. Every link lives here. |
| `public/CNAME` | Pins the `osintconnect.com` custom domain into the deploy artifact. |
| `public/robots.txt`, `public/sitemap.xml` | Crawler directives. |
| `scripts/check-links.sh` | Link verification engine, zero dependencies. |
| `tests/` | Offline artifact invariants, and control tests for the link strategies. |
| `.github/workflows/static.yml` | Deploys `public/` to GitHub Pages on push to `main`. |
| `.github/workflows/check-links.yml` | Runs the link check on pull requests and monthly. |
| `AGENTS.md` | Contributor and AI-agent guidance. Read this before editing. |

## Adding or changing a link

`public/index.html` is the source of truth for the published site. Add the entry
to the appropriate `<h2>` section, then run `./scripts/check-links.sh` before
opening a pull request. Every anchor carries
`target="_blank" rel="noopener noreferrer"` — the `noreferrer` is deliberate and
must not be dropped; see [AGENTS.md](./AGENTS.md).

## `check-links.sh` reference

```
Usage: scripts/check-links.sh [OPTIONS] [FILE...]

  -h, --help    Show help and exit.
  -q, --quiet   Print only failures and the summary.
      --strict  Treat REDIRECT as a failure as well as DEAD and MOVED.

Environment:
  GH_TOKEN / GITHUB_TOKEN   Optional; raises the GitHub API rate limit.

Exit status:
  0  no DEAD and no MOVED links
  1  at least one DEAD or MOVED link
  2  usage error or missing dependency
```

| Verdict | Meaning |
| --- | --- |
| `OK` | Verified reachable, and canonical where the host permits checking. |
| `REDIRECT` | Reachable, but the final URL differs — the entry should be updated. |
| `MOVED` | The GitHub repository was renamed or transferred. |
| `DEAD` | Verified absent. |
| `UNKNOWN` | No conclusion reached (rate limit, timeout). |
| `SKIP` | Host cannot be verified by automation. |

### What a passing run does and does not prove

A green run proves each URL resolves and, for X and GitHub, that the specific
account or repository still exists. It does **not** prove a site still does what
its label claims — a `200` from a reverse-image-search tool means the server is
up, not that it is still a reverse-image-search tool. Those labels are reviewed
by hand.

`https://www.linkedin.com/in/overton/` is reported `SKIP`: LinkedIn answers
HTTP `999` to all automated requests whether or not the profile exists, so no
automated verdict for it would be honest.

## Deployment

Pushing to `main` triggers `.github/workflows/static.yml`, which uploads
`public/` as a Pages artifact and deploys it to <https://osintconnect.com/>.

DNS is **not** managed by GitHub: `osintconnect.com` is registered through
Squarespace Domains and its zone is hosted on Google Cloud DNS. The apex `A`
records point at GitHub's shared anycast addresses
(`185.199.108–111.153`), which are identical for every Pages site.

## Contributing

Open an issue or pull request at
<https://github.com/overtonlabs/osint/issues>. Read [AGENTS.md](./AGENTS.md)
first — it documents the constraints that are not obvious from the source.

## License

[MIT](./LICENSE) © Steve Overton
