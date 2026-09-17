# Publishing ttyglass

The `publish.yml` workflow builds and verifies four native packages on their own architectures:

- `@maxiedev/ttyglass-win32-x64`
- `@maxiedev/ttyglass-linux-x64-gnu`
- `@maxiedev/ttyglass-darwin-x64`
- `@maxiedev/ttyglass-darwin-arm64`

It publishes only when a GitHub Release tag exactly matches `v<package.json version>`. Native packages and the root `ttyglass` package are first published under the `candidate` dist-tag through npm Trusted Publishing. The workflow waits for all five exact packages, verifies their required files, installs the release through a fresh consumer and npm cache, exercises its CLI, native terminal session, diagnostics, and TypeScript exports, and only then promotes all five packages to `latest`.

If npm accepts the packages but registry propagation interrupts verification, run the same workflow manually with the existing release tag. Manual recovery skips builds and publication, verifies the already published version, and promotes its dist-tags only after the package check passes.

## Manual registry verification

Run registry checks from a directory outside the ttyglass source checkout:

```sh
cd ..
npx --yes ttyglass@latest --open -- lazygit
```

Inside this repository, npm can treat `npx ttyglass` and even an explicitly versioned invocation as self-execution of the local root package because its package name and binary match the command. Neither proves that npm downloaded the published package. The automated published-package check uses a new isolated consumer package and npm cache for every attempt.

## Trusted publishing

Before publishing another version, configure a GitHub Actions trusted publisher for every package:

- Organization or user: `MrMaxie`
- Repository: `ttyglass`
- Workflow filename: `publish.yml`
- Environment: leave empty

The workflow has `id-token: write`, so npm obtains short-lived OIDC credentials for `npm publish` and attaches provenance without a publication token.

Trusted Publishing does not authorize `npm dist-tag add`. Create a granular npm token with read and write access limited to the five ttyglass packages, give it the shortest practical expiration, and store it as the `NPM_DIST_TAG_TOKEN` Actions secret. It is used only after exact-version verification succeeds to promote the package set to `latest`.

Remove the legacy `NPM_TOKEN` secret after `NPM_DIST_TAG_TOKEN` is configured. Configure npm publishing access to disallow token-based package publication only after a successful trusted publication confirms the OIDC setup.

Keep the version identical in the root and all four native package manifests, and publish a GitHub Release using the matching `v<version>` tag.

Do not retry a partially published immutable version. Inspect the registry state, increment the version if needed, and publish a new matching GitHub Release.
