# ttyglass repository guidance

## Project boundary

- Prefer the Node.js standard library. Runtime dependencies are limited to the real terminal bridge and WebSocket transport required by current behavior.
- Keep source code, documentation, configuration, and other project-facing artifacts in English.
- This repository is release-less. Do not add changelogs, release artifacts, tags, release automation, or a product release lifecycle unless the user explicitly authorizes one.
- Declare exact dependency and tool versions in manifests and lockfiles. Do not use version ranges such as `>=`, `^`, or `~`.
- The neutral npm package version required by tooling is allowed and does not create a product release lifecycle.

## Sources of truth

- `openspec/specs/` describes accepted product and engineering behavior.
- `openspec/changes/` contains proposed and active work until it is implemented, verified, and archived.
- `todo.txt` is a lightweight queue for work that has not earned an OpenSpec change.
- `.local/` is private operational context. Shared project behavior and tracked files must not depend on it.
- Use these sources directly. The Arcantry CLI is not required for this repository.

Do not duplicate the same decision between these layers. Link to the owning artifact.

## Development workflow

- Use the root `justfile` as the command surface.
- Run `just fmt` after editing TypeScript, JavaScript, CSS, or HTML source.
- Run `just check` for static validation, `just build` for package output, and `just test` for automated coverage including real PTY or ConPTY behavior.
- Preserve unrelated working-tree and private `.local/` content.
