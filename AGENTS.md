# ttyglass repository guidance

## Project boundary

- Prefer the Nim standard library. Add dependencies only for a current, verified need.
- Keep source code, documentation, configuration, and other project-facing artifacts in English.
- This repository is release-less. Do not add changelogs, release artifacts, tags, release automation, or a product release lifecycle unless the user explicitly authorizes one.
- Dependency constraints, lockfiles, tool compatibility metadata, and the neutral Nimble package version required by tooling are allowed and must remain reproducible.

## Sources of truth

- `openspec/specs/` describes accepted product and engineering behavior.
- `openspec/changes/` contains proposed and active work until it is implemented, verified, and archived.
- `todo.txt` is a lightweight queue for work that has not earned an OpenSpec change.
- `.local/` is private operational context. Shared project behavior and tracked files must not depend on it.
- Use these sources directly. The Arcantry CLI is not required for this repository.

Do not duplicate the same decision between these layers. Link to the owning artifact.

## Development workflow

- Use the root `justfile` as the command surface.
- Run `just fmt` after editing Nim source.
- Run `just check` for compiler validation and `just build` for a release-mode local binary.
- Preserve unrelated working-tree and private `.local/` content.
