# ttyglass repository guidance

## Project boundary

- Keep the executable, HTTP and WebSocket server, PTY or ConPTY ownership, process lifecycle, IPC, diagnostics ingestion, and embedded asset delivery in Nim.
- Keep TypeScript limited to the npm launcher, optional importable diagnostics helpers, tests, and build or verification scripts. Keep Svelte limited to the browser UI.
- Prefer the Nim and Node.js standard libraries. Add native dependencies only when an established library materially replaces protocol, parsing, CLI, or logging infrastructure.
- Keep source code, documentation, configuration, and other project-facing artifacts in English.
- Version public releases with Semantic Versioning and maintain `CHANGELOG.md` in Keep a Changelog format.
- Publish only through the release-gated workflow defined by the accepted OpenSpec behavior.
- Declare exact dependency and tool versions in manifests and lockfiles. Do not use version ranges such as `>=`, `^`, or `~`.

## Sources of truth

- `openspec/specs/` describes accepted product and engineering behavior.
- `openspec/changes/` contains proposed and active work until it is implemented, verified, and archived.
- `CHANGELOG.md` records consumer-visible outcomes for published versions.
- `todo.txt` is a lightweight queue for work that has not earned an OpenSpec change.
- `.local/` is private operational context. Shared project behavior and tracked files must not depend on it.
- Use these sources directly. The Arcantry CLI is not required for this repository.

Do not duplicate the same decision between these layers. Link to the owning artifact.

## Development workflow

- Use the root `justfile` as the command surface.
- Run `just fmt` after editing TypeScript, JavaScript, CSS, or HTML source.
- Run `just check` for static validation, `just build` for package output, and `just test` for automated coverage including real PTY or ConPTY behavior.
- Preserve unrelated working-tree and private `.local/` content.
