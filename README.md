# ttyglass

<p align="center">
  <img src="assets/ttyglass-logo.svg" alt="ttyglass" width="240">
</p>

<p align="center">
  Observe and interact with terminal sessions from a browser, CLI, or coding agent without changing the target app.
</p>

<p align="center">
  <a href="https://www.npmjs.com/package/ttyglass"><img src="https://img.shields.io/npm/v/ttyglass" alt="npm version"></a>
  <a href="https://github.com/MrMaxie/ttyglass/actions/workflows/publish.yml"><img src="https://github.com/MrMaxie/ttyglass/actions/workflows/publish.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache 2.0 license"></a>
</p>

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

Start a generic shell terminal without naming a command:

```sh
npx ttyglass --open
```

## Why ttyglass

- Work with the live TUI instead of a screenshot or text dump.
- Interact with it and resize it directly from the browser.
- Switch themes to preview the TUI through different color palettes.
- Test responsive behavior or exact terminal dimensions.
- View application diagnostics alongside the terminal without covering the TUI.
- Let browsers, CLI clients, and coding agents inspect and interact with the same retained session.
- Run several independent PTY or ConPTY sessions through one local ttyglass service.

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

ttyglass also works with package managers that can run npm package binaries.

ttyglass requires Node.js 24.18.0.

Supported platforms: Windows x64, Linux x64 with glibc, and macOS x64 or arm64.

## Usage

```text
ttyglass [options] [-- <command> [arguments...]]
```

Examples:

```sh
npx ttyglass -- lazygit
npx ttyglass --open -- btop
npx ttyglass --cwd ../app -- npm run tui
npx ttyglass --port 4173 -- cargo run
```

ttyglass prints a local URL. Open it unless `--open` already opened the browser.

The no-command form starts your user shell. Resolution uses `--shell`, then `SHELL`, then PowerShell or `ComSpec` on Windows, with `/bin/sh` as the POSIX fallback. Shell sessions show `No command` and do not support Restart.

| Option | Description |
| --- | --- |
| `--cwd <path>` | Run the observed command from this directory. |
| `--port <number>` | Use a specific local port instead of choosing one automatically. |
| `--diagnostics-limit <count>` | Keep between 1 and 5000 application diagnostic entries. The default is 500. |
| `--output-limit <bytes>` | Keep bounded raw ANSI output. The default is 1 MiB. |
| `--name <name>` | Give the new session a browser and client-visible name. |
| `--shell <executable>` | Select the shell for terminal mode. |
| `--open` | Open the browser after startup. |
| `--no-open` | Print the URL without opening a browser. This is the default. |
| `-h`, `--help` | Show command help. |
| `--version` | Show the installed package version. |

## Sessions and headless control

The first command starts one per-user service. It can own many sessions, and each session can have several attached browser, CLI, JSONL, or MCP clients.

```sh
ttyglass start --name "App" -- npm run tui
ttyglass start --name "Terminal"
ttyglass sessions
ttyglass status <session-id> --json
ttyglass screen <session-id> --json
ttyglass output <session-id> --from 0 --json
ttyglass input <session-id> --text q
ttyglass resize <session-id> --cols 100 --rows 30
ttyglass diagnostics <session-id> --json
ttyglass restart <session-id>
ttyglass stop <session-id>
ttyglass open <session-id>
```

`ttyglass agent` accepts persistent JSON-RPC 2.0 over JSON Lines. `ttyglass mcp` exposes equivalent multi-session tools over MCP stdio protocol `2025-11-25`. Both accept an optional `name` when starting a session, work headlessly, and control the same sessions shown in the browser.

Example agent request:

```json
{"jsonrpc":"2.0","id":1,"method":"read_screen","params":{"sessionId":"<session-id>"}}
```

Example MCP configuration:

```json
{
  "mcpServers": {
    "ttyglass": {
      "command": "ttyglass",
      "args": ["mcp"]
    }
  }
}
```

## Language examples

Run the command your project already uses:

| Project | Example |
| --- | --- |
| [Node.js or TypeScript](tests/typescript/main.ts) | `npx ttyglass --open -- npm run tui` |
| Python | `npx ttyglass --open -- python -m your_app` |
| [Go](tests/go/main.go) | `npx ttyglass --open -- go run .` |
| [Rust](tests/rust/src/main.rs) | `npx ttyglass --open -- cargo run` |
| [Nim](tests/nim/main.nim) | `npx ttyglass --open -- nimble run` |
| [Ruby](tests/ruby/main.rb) | `npx ttyglass --open -- ruby app.rb` |

The linked examples are complete TUIs used by the ttyglass test suite. They cover terminal input, resizing, color output, and application diagnostics. See [Stress TUI fixtures](tests/README.md) for instructions.

## Terminal display

Open Display to switch themes and preview the TUI through a different color palette.

Dynamic sizing follows the available browser space. Fixed sizing lets you test exact columns and rows. Diagnostics appears below the terminal without covering the TUI.

## Application diagnostics

Applications can send structured diagnostics to the browser without mixing them into the terminal output. The data stays with the current ttyglass session.

See [Diagnostics without a ttyglass library](docs/diagnostics.md) for setup, the record format, and dependency-free Node.js, Python, and Ruby examples.

## TypeScript API

TypeScript applications can use the included diagnostic helpers directly or with JSON-line loggers such as Pino:

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

Outside a ttyglass session, both helpers do nothing by default. See [Optional TypeScript diagnostics](docs/typescript.md) for integration details.

## Agent use

The npm package includes [skills for Codex and Claude Code](skills/README.md) that help agents start ttyglass, inspect and interact with the rendered TUI, report what they verified, and stop the session when finished.

## Development

ttyglass uses Nim for the executable, TypeScript for npm integration and diagnostic helpers, and Svelte for the browser UI.

```sh
nimble install --depsOnly --accept
nub install
just fmt
just check
just build
just test
just package-check
```

Run `just docs` to preview the Astro website or `just docs-build` to rebuild the static output in `docs`.

Run `just package-check` to validate the publishable package before a release.

Releases follow [Semantic Versioning](https://semver.org/). See [CHANGELOG.md](CHANGELOG.md) for notable changes.

## License

ttyglass is licensed under the [Apache License 2.0](LICENSE).
