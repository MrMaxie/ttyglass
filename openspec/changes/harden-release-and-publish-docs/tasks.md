## 1. Specification

- [x] 1.1 Specify the public documentation site, deployment gate, and repository discovery link.
- [x] 1.2 Specify registry propagation checks, isolated consumer verification, and split npm authentication.

## 2. Documentation publishing

- [x] 2.1 Configure Astro and package metadata for `https://maxie.dev/ttyglass/`.
- [x] 2.2 Add a pinned GitHub Pages workflow that checks pull requests and deploys `docs/` from `master`.
- [x] 2.3 Regenerate the tracked documentation output.
- [x] 2.4 Align the rendered browser preview, CLI and MCP reference, lifecycle guidance, and narrow layout with 1.1.0.

## 3. Release hardening

- [x] 3.1 Preflight the exact root and four native packages before consumer verification.
- [x] 3.2 Use isolated npm caches for published-package installation and extend the registry propagation retry window.
- [x] 3.3 Move immutable publication to npm Trusted Publishing and reserve a narrowly scoped token for dist-tag promotion.

## 4. Verification and activation

- [x] 4.1 Run formatting, static checks, tests, documentation checks and build, package verification, workflow validation, and `git diff --check`.
- [ ] 4.2 Push the reviewed change and confirm the documentation workflow succeeds on all required events.
- [ ] 4.3 Configure GitHub Pages and the repository homepage, then verify the public documentation URL.
- [ ] 4.4 Configure npm trusted publishers for all five packages and replace the promotion secret before the next release.
