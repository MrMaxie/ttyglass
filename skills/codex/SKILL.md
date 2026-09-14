---
name: ttyglass
description: Run and inspect real terminal sessions in ttyglass through browser, stateless CLI, or MCP when Codex needs visual or headless evidence without modifying the observed project.
---

# Inspect a TUI with ttyglass

Use ttyglass to let Codex see and operate a real TUI through a local browser. It is for visual assessment, interaction debugging, responsive terminal checks, and diagnostics that must remain separate from the terminal screen.

## Workflow

1. Identify the exact project command that normally starts the TUI. Do not create a mock screen or project-specific wrapper.
2. From the tested project directory, run `ttyglass -- <command> <arguments>`. Put ttyglass options before `--` and preserve the tested command after it.
3. For visual work, open the exact authenticated loopback URL. For headless work, use `ttyglass start --name <name>`, then `screen`, `output`, `input`, `resize`, `diagnostics`, and `stop` with the returned session id. Give concurrent sessions distinct names. Use `ttyglass mcp` when an MCP connection is available; pass `name` to `start_session` for the same result.
4. Attach browser and headless clients to the same session when both rendered and structured terminal evidence are needed. Verify the real state before interacting. Exercise only actions authorized by the user.
5. Check relevant terminal sizes, keyboard navigation, focus, errors, loading and empty states, and process exit behavior. Use Diagnostics for investigation data, not as a substitute for the visible TUI.
6. Capture evidence only when requested or required by the parent task. State which states and sizes were actually observed.
7. Detach clients and explicitly stop sessions when finished. Confirm each observed process ended. Do not stop unrelated sessions in the shared service.

## Safety

- ttyglass is a local observation tool, not authorization to mutate project or external state.
- Use the exact loopback URL printed for the current run. Never expose it, its fragment token, or diagnostics token outside the local task.
- Do not put credentials, personal data, complete environment dumps, or unrelated project content in diagnostics.
- Do not claim native terminal behavior from a static mock or DOM-only recreation. ttyglass must be connected to the real PTY or ConPTY process.
- If browser automation is unavailable, report that visual interaction remains unverified instead of inferring it from tests.

See the package `README.md` for CLI options and `docs/diagnostics.md` for dependency-free diagnostic records.
