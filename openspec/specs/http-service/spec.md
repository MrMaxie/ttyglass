# HTTP service specification

## Purpose

Define the externally observable behavior of the local ttyglass HTTP service.

## Requirements

### Requirement: Unknown routes are rejected

The service MUST respond to unknown routes or unsupported methods with HTTP status 404 and a plain-text `Not found` body followed by a newline.

#### Scenario: A client requests an unknown path

- **WHEN** a client sends a request for an unrecognized path or unsupported method
- **THEN** the service responds with HTTP status 404
- **AND** returns a plain-text `Not found` body

### Requirement: Root endpoint serves the observer

The service MUST serve the packaged ttyglass browser application from the root endpoint with no-store caching and restrictive browser security headers.

#### Scenario: A local client requests the observer

- **WHEN** a client sends `GET /` to the active loopback origin
- **THEN** the service responds with the packaged browser application
- **AND** the response prevents caching, framing, external connections, and MIME-type guessing
