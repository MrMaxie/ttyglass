## MODIFIED Requirements

### Requirement: npm publication is verified and release-gated

The project MUST publish to npm only from a GitHub Release whose tag matches the root and native package versions. It MUST build and verify each native executable on its target architecture, publish the package set under a non-default candidate tag through npm Trusted Publishing, wait until every exact package is available from the registry, exercise the exact registry version from a fresh consumer and npm cache, and promote the complete verified set to `latest` only after verification succeeds. Immutable package publication MUST NOT require a long-lived npm token. Mutable dist-tag promotion MAY use a narrowly scoped automation token while npm Trusted Publishing does not support that operation.

#### Scenario: A matching GitHub Release is published

- **WHEN** a GitHub Release tag matches `v<package version>` and verification passes on Windows x64, Linux x64 glibc, macOS x64, and macOS arm64
- **THEN** the workflow publishes all native packages and the root package as candidates with provenance through trusted publishing
- **AND** waits until all five exact package versions and required native executable files are visible from the registry
- **AND** verifies the CLI, native terminal session, diagnostics, and TypeScript exports from a fresh registry consumer
- **AND** promotes the verified package set to `latest`

#### Scenario: Registry propagation is incomplete

- **WHEN** any exact package version or required native executable is not yet available from the registry
- **THEN** verification fails with the unavailable package identified
- **AND** the workflow retries from a fresh npm cache within its bounded propagation window
- **AND** does not promote any package to `latest`

#### Scenario: Release metadata or verification is invalid

- **WHEN** any package version differs, a target build fails, or exact-version registry verification fails after the bounded retry window
- **THEN** the workflow does not promote the package set to `latest`
