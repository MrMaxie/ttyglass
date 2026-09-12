# Stress TUI fixtures

These four standalone applications exercise ttyglass through equivalent workloads implemented in TypeScript, Go, Rust, and Nim. Each fixture:

- redraws the complete screen ten times per second;
- renders ANSI-16 colors, 24-bit RGB colors, changing tables, and wide glyphs;
- reacts to terminal size changes;
- emits a structured diagnostic every 500 ms and supports a twelve-record burst;
- exits safely after `q`, Ctrl+C, or the optional `--duration-ms` limit.

The TypeScript fixture exercises the public `sendTtyglassDiagnostic` package export. The other fixtures use only their language standard library to POST authenticated JSON to the child-specific loopback endpoint. They do not send data anywhere else.

## Run one fixture

Run the command from the repository root. ttyglass prints a local URL without opening a browser automatically.

```sh
just tui-typescript
just tui-go
just tui-rust
just tui-nim
```

Pass an automatic stop time when a bounded session is useful:

```sh
just tui-rust --duration-ms 10000
```

Use `q` to quit, `p` or Space to pause animation, `d` to emit one diagnostic, `b` to emit a diagnostic burst, and `r` to force a redraw. Rust and Go may require Enter after a command when the host terminal keeps canonical input enabled.

## Validate all fixtures

```sh
just check-tuis
just verify-tuis
```

`check-tuis` builds ttyglass, type-checks TypeScript, vets Go, checks Rust, and checks Nim. `verify-tuis` additionally runs every fixture through a real ttyglass PTY or ConPTY session and verifies screen output, resize handling, structured diagnostics, diagnostic bursts, and orderly exit. Compiled fixture artifacts stay under the private `.local/` directory.
