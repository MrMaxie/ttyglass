# ttyglass

<p align="center">
  <img src="assets/ttyglass-logo.svg" alt="TTYGlass logo" width="240">
</p>

ttyglass runs a real terminal user interface through PTY or Windows ConPTY and mirrors it into a local browser. It gives humans and coding agents a faithful surface for visual review, interaction debugging, terminal resize checks, and separate structured diagnostics without adapting the observed project.

## Status

The package is local and private. It has not been published. The package layout and command contract are prepared for a later npm publication, but registry commands will not resolve ttyglass yet.

## Requirements

- Node.js 24.18.0
- nub 0.7.5
- just

## Build and run locally

```sh
nub install
just build
node dist/cli.js -- <command> [arguments...]
```

For example:

```sh
node dist/cli.js -- lazygit
node dist/cli.js --cwd ../another-project -- npm run tui
```

ttyglass prints an authenticated `http://127.0.0.1:<port>/#token=...` URL. Open that exact URL. The TUI process starts when the browser connects and ends when the browser disconnects or ttyglass stops.

Options belong before `--`. The observed command and all of its arguments belong after it.

```text
--cwd <path>                Run the command from this directory
--port <number>             Use a fixed loopback port instead of an available port
--diagnostics-limit <count> Keep 1-5000 diagnostic entries
--open                      Open the browser after startup
--no-open                   Do not open the browser, which is the default
```

## Intended installation contract

After a future publication, the same package is intended to support:

```sh
ttyglass [options] -- <command> [arguments...]
npx ttyglass [options] -- <command> [arguments...]
nubx ttyglass [options] -- <command> [arguments...]
```

No publication, global installation, tag, or release is part of the current repository state.

## Terminal display controls

Use Display to preview the observed TUI with a different terminal palette for the current session. The choices are the unmodified default output, Catppuccin Mocha, Gruvbox Dark, Nord, Dracula, and Tokyo Night. The preview maps ANSI colors, indexed colors, and application-supplied 24-bit RGB colors into the selected palette while leaving the ttyglass interface unchanged.

Terminal size defaults to Dynamic, which follows the available browser space. Fixed accepts an explicit size from 2 to 1000 columns and 1 to 500 rows and keeps it across browser layout changes. Display overlays the terminal without resizing it. Diagnostics docks below the terminal. In Dynamic mode, opening or closing Diagnostics refits the TUI to the remaining space; in Fixed mode, the configured terminal dimensions remain unchanged and the terminal viewport stays scrollable.

## Diagnostics

The observed process receives a loopback diagnostics URL and token in environment variables. It can send JSON with only a language standard library. The Diagnostics panel contains only records emitted by that process, never ttyglass lifecycle or resize events. See [dependency-free diagnostics](docs/diagnostics.md).

TypeScript applications may instead import `sendTtyglassDiagnostic` or `createTtyglassSink` from `ttyglass`. The sink works as a Pino destination without adding Pino to ttyglass. See [optional TypeScript diagnostics](docs/typescript.md).

## Agent skills

The package includes dedicated [Codex and Claude Code skills](skills/README.md). They explain when ttyglass is useful, how an agent should open and assess the real TUI, what evidence it may claim, and how to keep the session and diagnostics local.

## Development

```sh
just fmt
just check
just build
just test
```

## License

This project is licensed under the [Apache License 2.0](LICENSE).
