# ttyglass

<p align="center">
  <img src="assets/ttyglass-logo.svg" alt="ttyglass" width="240">
</p>

<p align="center">
  Run a real terminal UI in a local browser for visual testing, interaction debugging, and agent-assisted review.
</p>

<p align="center">
  <a href="https://www.npmjs.com/package/ttyglass"><img src="https://img.shields.io/npm/v/ttyglass" alt="npm version"></a>
  <a href="https://github.com/MrMaxie/ttyglass/actions/workflows/publish.yml"><img src="https://github.com/MrMaxie/ttyglass/actions/workflows/publish.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache 2.0 license"></a>
</p>

ttyglass is a native Nim executable that wraps any TUI command in a real PTY or Windows ConPTY session and mirrors it into an authenticated browser page on `127.0.0.1`. The observed project does not need ttyglass configuration, a ttyglass dependency, or source changes.

## Quick start

Run a TUI without installing ttyglass:

```sh
npx ttyglass --open -- lazygit
```

Or run a project command from another directory:

```sh
npx ttyglass --open --cwd ../my-app -- npm run tui
```

Everything before `--` configures ttyglass. Everything after `--` is the command and its arguments.

## Why ttyglass

- Observe the real TUI instead of a reconstructed screenshot or text dump.
- Send keyboard input and resize the underlying PTY from the browser.
- Preview ANSI output with Catppuccin Mocha, Gruvbox Dark, Nord, Dracula, or Tokyo Night.
- Switch between a terminal that follows the browser and an exact fixed row and column size.
- Keep application diagnostics outside the terminal without changing the TUI layout.
- Give Codex or Claude Code a browser surface it can inspect and interact with safely.
- Run against an arbitrary project without adding ttyglass to that project.

The server binds only to loopback and uses a fresh token for the browser and diagnostics connections. The terminal process is scoped to that ttyglass session.

## Installation

The quickest option is `npx`:

```sh
npx ttyglass -- <command> [arguments...]
```

Install the command globally if you use it often:

```sh
npm install --global ttyglass
ttyglass -- <command> [arguments...]
```

Nub users can run the same package without installing it:

```sh
nubx -y ttyglass -- <command> [arguments...]
```

ttyglass currently requires Node.js 24.18.0.

Prebuilt executables are provided for Windows x64, Linux x64 with glibc, macOS x64, and macOS arm64. npm selects the matching optional package; installing ttyglass does not compile Nim or native code.

## Usage

```text
ttyglass [options] -- <command> [arguments...]
```

Examples:

```sh
npx ttyglass -- lazygit
npx ttyglass --open -- btop
npx ttyglass --cwd ../app -- npm run tui
npx ttyglass --port 4173 -- cargo run
```

ttyglass prints an authenticated URL such as `http://127.0.0.1:4173/#token=...`. Open that exact URL unless `--open` already opened it.

| Option | Description |
| --- | --- |
| `--cwd <path>` | Run the observed command from this directory. |
| `--port <number>` | Use a fixed loopback port instead of an available port. |
| `--diagnostics-limit <count>` | Keep between 1 and 5000 application diagnostic entries. The default is 500. |
| `--open` | Open the authenticated browser URL after startup. |
| `--no-open` | Print the URL without opening a browser. This is the default. |
| `-h`, `--help` | Show command help. |
| `--version` | Show the installed package version. |

## Terminal display

Open Display to change how the observed terminal is rendered. Color schemes remap ANSI, indexed, and application-supplied RGB colors inside the TUI without changing the ttyglass interface.

Dynamic sizing follows the available browser space. Fixed sizing keeps the exact columns and rows you enter and makes the browser terminal viewport scrollable when necessary. Opening Diagnostics never covers terminal content.

## Application diagnostics

Every observed command receives `TTYGLASS_DIAGNOSTICS_URL` and `TTYGLASS_DIAGNOSTICS_TOKEN`. The application can send JSON or newline-delimited JSON to that loopback endpoint using only its language standard library.

Diagnostics are optional, bounded in memory, and visible only for the current session. ttyglass does not put its own lifecycle or resize events in the Diagnostics panel.

See [Diagnostics without a ttyglass library](docs/diagnostics.md) for the record format and dependency-free Node.js and Python examples.

## TypeScript API

TypeScript applications can import a direct diagnostic sender or a JSON-line sink compatible with loggers such as Pino:

```ts
import { createTtyglassSink, sendTtyglassDiagnostic } from 'ttyglass';

await sendTtyglassDiagnostic({
  source: 'checkout',
  level: 'info',
  event: 'screen.loaded',
  fields: { items: 3 },
});

const sink = createTtyglassSink({ source: 'checkout' });
```

Both APIs are no-ops by default outside a ttyglass session. See [Optional TypeScript diagnostics](docs/typescript.md) for integration details.

## Agent use

The npm package includes dedicated [Codex and Claude Code skills](skills/README.md). They explain how an agent should start ttyglass, inspect the rendered TUI, collect diagnostics, state what it actually verified, and clean up the session.

## Development

The runtime core is Nim 2.2.12. It owns the CLI, local server, WebSocket transport, diagnostics ingestion, PTY or ConPTY bridge, process cleanup, and embedded browser assets. TypeScript is limited to the npm launcher, optional diagnostics helpers, tests, and repository scripts. Svelte is limited to the browser UI.

```sh
nimble install --depsOnly --accept
nub install
just fmt
just check
just build
just test
just package-check
```

`just package-check` builds the publishable tarball, validates its contents, runs the packaged CLI through `npx`, exercises a real terminal and diagnostics session, and imports the public TypeScript API from a clean consumer project.

Native dependencies are pinned in `ttyglass.nimble` and `nimble.lock`. npm and frontend dependencies are pinned in their manifests and `nub.lock`.

Releases follow [Semantic Versioning](https://semver.org/). See [CHANGELOG.md](CHANGELOG.md) for notable changes.

## License

ttyglass is licensed under the [Apache License 2.0](LICENSE).
