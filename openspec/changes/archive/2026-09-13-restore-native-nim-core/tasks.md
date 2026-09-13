## 1. Native runtime

- [x] 1.1 Add exact Nim dependencies and implement the cligen CLI, Mummy loopback server, jsony messages and diagnostics, and chronicles logging.
- [x] 1.2 Implement framed IPC and native Windows ConPTY and POSIX `forkpty` hosts with resize, input, output, exit, and process-tree cleanup.
- [x] 1.3 Embed the production Svelte assets in the native executable.

## 2. npm boundary

- [x] 2.1 Replace the Node.js server with a thin TypeScript platform launcher while preserving the optional TypeScript diagnostics API.
- [x] 2.2 Add exact-version platform packages for Windows x64, Linux x64 glibc, macOS x64, and macOS arm64.
- [x] 2.3 Remove `.mjs` sources and keep TypeScript only in the permitted launcher, helper, test, and script roles.

## 3. Distribution and verification

- [x] 3.1 Add package checks for tarball contents, `npx`, native PTY behavior, diagnostics, and TypeScript imports in a clean consumer directory.
- [x] 3.2 Build and test all four native packages on target GitHub Actions runners before candidate publication and promotion.
- [x] 3.3 Run `just fmt`, `just check`, `just build`, `just test`, `just check-tuis`, `just verify-tuis`, and `just package-check`.
