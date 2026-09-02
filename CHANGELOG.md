# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project has no
version numbers or releases: `main` is the deployed state, so changes are
recorded by date.

## [Unreleased]

## [2026-09-01]

### Added
- `public/CNAME`, pinning the `osintconnect.com` custom domain into the deploy
  artifact. The domain previously existed only as a repository Pages setting,
  which is not reliably preserved across a repository transfer.
- `scripts/check-links.sh`, a dependency-free link verification engine with
  host-specific strategies for X, GitHub and LinkedIn.
- `tests/test-site-invariants.sh` and `tests/test-check-links.sh`, the latter
  control-testing each verification strategy against a resource that does not
  exist so no strategy can silently decay into one that always passes.
- `.github/workflows/check-links.yml`, running both suites and the link check
  on pull requests, pushes and monthly.
- `AGENTS.md` as canonical contributor and agent guidance, with `CLAUDE.md`
  reduced to a pointer.
- `rel="noopener noreferrer"` on all 39 outbound anchors, so visiting an OSINT
  resource from this page no longer leaks `osintconnect.com` as the referrer.
- The "links are not endorsements" disclaimer on the published page. It had
  previously existed only in the README, where visitors do not see it.

### Changed
- Repository transferred from `Steve0verton/osint` to `overtonlabs/osint`. All
  in-repository URLs updated, including the two on the published page itself.
- `README.md` rewritten around a quick start, the `check-links.sh` contract and
  an explicit statement of what a passing run does and does not prove. It no
  longer duplicates the link list, which had to be kept in sync by hand.
- OSINT Combine link updated to its canonical URL
  `https://www.osintcombine.com/free-osint-tools`; the previous
  `osintcombine.com/tools` resolved only through two redirects.
- OSINT Framework source link now points at `lockfale/OSINT-Framework` rather
  than the `lockfale` organisation profile.
- `public/sitemap.xml` gained an XML declaration and dropped an image namespace
  that was declared but never used.

### Fixed
- **Corrects a false claim published since the first commit:**
  `github.com/lanmaster53/recon-ng` was labelled "Linux OS with OSINT Tools".
  recon-ng is a Python reconnaissance framework, not a Linux distribution. The
  entry is now labelled "Recon-ng reconnaissance framework".
- `<meta name="robots">` used the directive `archive`, which is not a valid
  robots value; replaced with `follow`.
- `public/robots.txt` contained `Disallow: /nogooglebot/`, copied verbatim from
  Google's example documentation. No such path has ever existed on this site.
- X handle casing corrected to match the accounts as they actually exist:
  `@FalconFeedsIO` to `@FalconFeedsio`, and `@H4ckManac` to `@H4ckmanac`
  (the link target was corrected as well).

### Verified
- All 44 automatically verifiable links resolve. Every X account and every
  GitHub repository on the page was confirmed to exist by a method capable of
  returning a failure, rather than by status code alone.
- `https://www.linkedin.com/in/overton/` remains unverified by automation:
  LinkedIn answers HTTP 999 to all automated requests regardless of whether the
  profile exists.
