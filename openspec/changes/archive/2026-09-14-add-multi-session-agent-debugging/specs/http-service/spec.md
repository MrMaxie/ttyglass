## ADDED Requirements

### Requirement: browser routes expose session selection and direct session views

The loopback browser service MUST select a retained session from the root route and provide a custom-rendered session selector on each direct session view. A session page MUST expose its terminal, complete display command, status, dimensions, output, and diagnostics to every authorized connected client. The toolbar MUST identify TTYGLASS, show the packaged version below the name, and place the session selector after that identity with clear separation from adjacent status. Display theme selection MUST use the same custom menu treatment.

#### Scenario: the management browser opens the root route

- **WHEN** a browser opens the authenticated service root
- **THEN** it opens the previously selected retained session when it is still available
- **AND** otherwise opens the first retained session

#### Scenario: no retained sessions are available

- **WHEN** the management browser opens the root route without a retained session
- **THEN** the toolbar keeps a disabled session selector
- **AND** the terminal area explains how to start a terminal or command session

#### Scenario: the user changes the selected session

- **WHEN** the user chooses another retained session from the toolbar selector
- **THEN** the browser opens that session's authorized direct view
- **AND** remembers the selection for the next visit to the root route

#### Scenario: the selector labels sessions

- **WHEN** a retained session has a user-provided name
- **THEN** the selector uses the name as its label
- **AND** otherwise uses the first 25 characters of the display command, followed by `(...)` only when more characters remain

#### Scenario: a custom menu opens inside a scrollable panel

- **WHEN** the user opens the theme selector in the Display panel
- **THEN** the option list renders on a floating layer above the panel content
- **AND** opening it does not change the panel's scrollable size

#### Scenario: a narrow viewport truncates the heading visually

- **WHEN** a display command is wider than the session selector
- **THEN** the control may visually truncate it
- **AND** the complete value remains available as the selected option and for copying

### Requirement: browser authorization is scoped

The management token MUST authorize session listing. A session token MUST authorize only its own terminal WebSocket and diagnostic endpoint. HTTP and WebSocket listeners MUST bind only to `127.0.0.1`.

#### Scenario: a session token targets another session

- **WHEN** a client presents a valid token for a different session
- **THEN** ttyglass rejects the request without revealing target session data

## MODIFIED Requirements

### Requirement: the local service exposes a minimal browser surface

The local service MUST serve an embedded browser application at the root path, direct session pages, the terminal WebSocket endpoint, and session-scoped diagnostics endpoints. Unknown paths and unsupported methods MUST return an explicit error response without exposing local files or directory listings.

#### Scenario: the browser requests the root path

- **WHEN** an authenticated browser sends `GET /`
- **THEN** the service returns the embedded browser application and selects a retained session when available

#### Scenario: the browser requests a session path

- **WHEN** an authorized browser sends `GET /sessions/<session-id>`
- **THEN** the service returns the embedded terminal application for that session

#### Scenario: a client requests an unknown route

- **WHEN** the client requests a route outside the defined browser, WebSocket, and diagnostics endpoints
- **THEN** the service returns an explicit not-found or method-not-allowed response
- **AND** it does not expose any local filesystem path or listing
