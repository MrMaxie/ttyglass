## ADDED Requirements

### Requirement: The terminal observation runtime is native Nim

The distributed ttyglass executable MUST implement CLI parsing, HTTP and WebSocket handling, PTY or ConPTY ownership, process lifecycle, diagnostics ingestion, and embedded browser asset delivery in Nim. TypeScript MUST be limited to the npm launcher, optional diagnostics library, tests, and build or verification scripts. Svelte MUST be limited to the browser UI.

#### Scenario: A user starts ttyglass through npm

- **WHEN** a user invokes the root package through a global install, `npx`, or `nubx`
- **THEN** the TypeScript launcher selects and starts the matching native executable
- **AND** the native executable owns the complete observation session

#### Scenario: The browser UI is served

- **WHEN** a browser requests an application asset from a running ttyglass session
- **THEN** the native executable serves the Svelte production asset embedded at compile time

### Requirement: npm installation selects a prebuilt native package

The root npm package MUST declare exact-version optional dependencies for Windows x64, Linux x64 glibc, macOS x64, and macOS arm64. Installation MUST NOT compile Nim or native code on the consumer machine.

#### Scenario: A supported platform executes ttyglass

- **WHEN** the package runs on a supported operating system and CPU architecture
- **THEN** the launcher resolves the matching optional package and forwards all arguments to its executable

#### Scenario: The native package is unavailable

- **WHEN** the matching optional package was omitted or cannot be resolved
- **THEN** the launcher exits with a message that identifies the missing package and how to restore optional dependencies

## MODIFIED Requirements

### Requirement: npm publication is verified and release-gated

The project MUST publish to npm only from a GitHub Release whose tag matches the root and native package versions. It MUST build and verify each native executable on its target architecture, publish the package set under a non-default candidate tag, exercise the exact registry version, and promote the complete verified set to `latest` only after verification succeeds.

#### Scenario: A matching GitHub Release is published

- **WHEN** a GitHub Release tag matches `v<package version>` and verification passes on Windows x64, Linux x64 glibc, macOS x64, and macOS arm64
- **THEN** the workflow publishes all native packages and the root package as candidates with provenance
- **AND** verifies the CLI, native terminal session, diagnostics, and TypeScript exports from the registry
- **AND** promotes the verified package set to `latest`

#### Scenario: Release metadata or verification is invalid

- **WHEN** any package version differs, a target build fails, or registry verification fails
- **THEN** the workflow does not promote the package set to `latest`
