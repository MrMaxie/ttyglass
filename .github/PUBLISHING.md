# Publishing ttyglass

The `publish.yml` workflow builds and verifies four native packages on their own architectures:

- `@maxiedev/ttyglass-win32-x64`
- `@maxiedev/ttyglass-linux-x64-gnu`
- `@maxiedev/ttyglass-darwin-x64`
- `@maxiedev/ttyglass-darwin-arm64`

It publishes only when a GitHub Release tag exactly matches `v<package.json version>`. Native packages and the root `ttyglass` package are first published under the `candidate` dist-tag. The workflow installs the exact registry version, exercises its CLI, native terminal session, diagnostics, and TypeScript exports, and only then promotes all five packages to `latest`.

## First publication

An unpublished npm package cannot have a trusted publisher configured yet. Bootstrap the first release with a short-lived granular npm token:

1. Create an npm granular access token that may create and publish the five package names above.
2. Add it to the `MrMaxie/ttyglass` repository as an Actions secret named `NPM_TOKEN`.
3. Keep the version identical in the root and all four native package manifests.
4. Publish a GitHub Release using the matching `v<version>` tag.

Do not retry a partially published immutable version. Inspect the registry state, increment the version if needed, and publish a new matching GitHub Release.

## Trusted publishing

After the first version exists on npm, configure a GitHub Actions trusted publisher for every package:

- Organization or user: `MrMaxie`
- Repository: `ttyglass`
- Workflow filename: `publish.yml`
- Allowed action: `npm publish`

After one successful trusted publication, remove the `NPM_TOKEN` repository secret and configure npm publishing access to disallow token-based publication. The workflow has `id-token: write`, so npm can use short-lived OIDC credentials and attach provenance automatically.
