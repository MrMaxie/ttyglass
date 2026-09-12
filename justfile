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

# Run ttyglass after a local build. Pass ttyglass arguments after `--`.
run *args:
	node dist/cli.js {{args}}
