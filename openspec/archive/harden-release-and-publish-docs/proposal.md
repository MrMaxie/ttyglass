## Why

ttyglass generates a complete Astro documentation site, but the repository does not deploy it and does not advertise a documentation URL. The npm release workflow also retries exact-version verification before all five registry packages are necessarily visible, and it uses one long-lived token for both immutable publication and mutable dist-tag promotion.

## What Changes

- Publish the generated documentation through GitHub Pages at `https://maxie.dev/ttyglass/` after changes reach `master`.
- Advertise the documentation URL from the package metadata, README, and GitHub repository homepage.
- Align the public site, browser preview, CLI reference, MCP reference, and responsive layout with the shipped 1.1.0 behavior.
- Verify that every exact root and native package is available before exercising the isolated consumer installation.
- Give every published-package verification attempt a fresh npm cache and a longer propagation window.
- Use npm Trusted Publishing for immutable package publication while retaining a narrowly scoped token only for final dist-tag promotion, which npm OIDC does not support.

## Non-goals

- Redesigning or rewriting the documentation site.
- Adding a new custom domain, subdomain, or DNS record.
- Publishing a package release as part of this change.
- Replacing the existing release-gated candidate, verification, and promotion model.

## Impact

- A new GitHub Pages workflow checks documentation pull requests and deploys the generated `docs/` directory from `master`.
- Release verification distinguishes registry propagation from consumer behavior and avoids stale npm cache state between attempts.
- Future immutable npm publication no longer depends on a long-lived automation token after trusted publishers are configured for all five packages.
- `NPM_DIST_TAG_TOKEN` remains required for the final `latest` promotion until npm supports dist-tag operations through trusted publishing.

---

## Archive Information

**Archived:** 2026-09-17 13:13
**Duration:** 0 days
**Outcome:** Successfully implemented

### Implementation

- Merged as commit `9404a21147a32e56596f1eeffb6d2cbcfc80993a`.
- Published and verified the GitHub Pages documentation site.
- Configured npm Trusted Publishing for the root package and all four native packages.
- Replaced the legacy GitHub Actions npm secret with the package-scoped `NPM_DIST_TAG_TOKEN` promotion secret.

### Specs Updated

- `openspec/specs/documentation-publishing/spec.md`
- `openspec/specs/tui-observation/spec.md`
