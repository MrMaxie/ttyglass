binary := if os_family() == "windows" { "build/ttyglass.exe" } else { "build/ttyglass" }

default:
	@just --list

# Format Nim source.
fmt:
	nimpretty --indent:2 --maxLineLen:100 src/ttyglass.nim

# Run compiler checks without producing an application binary.
check:
	nimble check
	nim check src/ttyglass.nim

# Build an optimized local binary.
build:
	nim c -d:release --out:{{binary}} --nimcache:build/nimcache src/ttyglass.nim

# Compile and run the HTTP service.
run:
	nim r src/ttyglass.nim
