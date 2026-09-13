default:
	@just --list

# Format TypeScript, JavaScript, CSS, and HTML sources.
fmt:
	nub run format

# Run static validation.
check:
	nub run check

# Build the browser frontend, CLI, and library.
build:
	nub run build

# Run automated tests, including a real PTY or ConPTY session.
test:
	nub run test

# Validate the exact tarball, npx executable, and public library exports without publishing.
package-check:
	nub run package:check

# Exercise the exact package version from the public npm registry.
package-check-published:
	nub run package:check:published

# Compile and statically check every stress TUI fixture.
check-tuis: build
	tsc --noEmit -p tests/typescript/tsconfig.json
	go -C tests/go vet ./...
	cargo check --manifest-path tests/rust/Cargo.toml --target-dir .local/rust-target
	nim check --threads:on --hints:off tests/nim/main.nim

# Exercise every stress TUI through a real ttyglass PTY or ConPTY session.
verify-tuis: check-tuis
	nim c --threads:on --hints:off --nimcache:.local/nimcache --out:.local/ttyglass-stress-nim.exe tests/nim/main.nim
	node tests/verify.ts

# Run the TypeScript stress TUI through ttyglass.
tui-typescript *args: build
	node dist/cli.js -- node tests/typescript/main.ts {{args}}

# Run the Go stress TUI through ttyglass.
tui-go *args: build
	node dist/cli.js -- go -C tests/go run . {{args}}

# Run the Rust stress TUI through ttyglass.
tui-rust *args: build
	node dist/cli.js -- cargo run --quiet --manifest-path tests/rust/Cargo.toml --target-dir .local/rust-target -- {{args}}

# Build and run the Nim stress TUI through ttyglass.
tui-nim *args: build
	nim c --threads:on --hints:off --nimcache:.local/nimcache --out:.local/ttyglass-stress-nim.exe tests/nim/main.nim
	node dist/cli.js -- .local/ttyglass-stress-nim.exe {{args}}

# Run ttyglass after a local build. Pass ttyglass arguments after `--`.
run *args:
	node dist/cli.js {{args}}
