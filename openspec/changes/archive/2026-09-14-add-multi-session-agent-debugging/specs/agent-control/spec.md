## ADDED Requirements

### Requirement: local clients share one authenticated control plane

Stateless CLI commands, the JSONL agent, and MCP MUST use the same authenticated per-user local control plane. Windows MUST use a Named Pipe and POSIX MUST use a Unix Domain Socket stored through a private runtime descriptor. Management secrets MUST NOT appear in process arguments or session listings.

#### Scenario: a stale singleton descriptor exists

- **WHEN** a client finds a descriptor whose service process or endpoint is dead
- **THEN** it removes the stale descriptor
- **AND** starts one replacement per-user service without reusing its token

### Requirement: ttyglass provides stateless session commands

The CLI MUST provide `serve`, `start`, `sessions`, `status`, `screen`, `output`, `input`, `resize`, `diagnostics`, `restart`, `stop`, and `open`. Session-creating commands MUST accept an optional session name. These commands MUST execute the same operations exposed to persistent clients.

#### Scenario: an agent controls a session without a browser

- **WHEN** the agent starts a session, sends input, resizes it, and reads its screen through stateless commands
- **THEN** all operations succeed without opening or running a browser

### Requirement: ttyglass provides a persistent JSONL agent protocol

`ttyglass agent` MUST accept JSON-RPC 2.0 requests separated by newlines and return one JSON-RPC response per request. One agent process MUST be able to attach to and control multiple session ids.

#### Scenario: one agent attaches to two sessions

- **WHEN** an agent sends attach requests for two session ids
- **THEN** both attachments remain active until detached or the agent exits
- **AND** the sessions continue independently

#### Scenario: a JSONL client names a new session

- **WHEN** an agent starts a session with a name
- **THEN** the returned metadata and later session listings expose that name

### Requirement: ttyglass provides an MCP stdio server

`ttyglass mcp` MUST implement MCP protocol version `2025-11-25` over stdio and expose `list_sessions`, `start_session`, `attach_session`, `detach_session`, `get_status`, `read_screen`, `read_output`, `send_input`, `resize_terminal`, `read_diagnostics`, `restart_session`, and `stop_session`. `start_session` MUST accept an optional session name. Stdout MUST contain JSON-RPC protocol messages only and logs MUST use stderr.

#### Scenario: an MCP client controls a browser-visible session

- **WHEN** an MCP client starts or attaches to a session also open in a browser
- **THEN** MCP input, resize, status, snapshot, output, and diagnostics operate on the same session
- **AND** browser and MCP clients observe the resulting shared state
