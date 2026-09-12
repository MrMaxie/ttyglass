# HTTP service specification

## Purpose

Define the initial externally observable behavior of the ttyglass HTTP service.

## Requirements

### Requirement: Root endpoint returns a greeting

The service MUST listen on `127.0.0.1:8080` and respond to `GET /` with HTTP status 200, the `text/plain; charset=utf-8` content type, and the body `Hello, World!` followed by a newline.

#### Scenario: A client requests the root endpoint

- **WHEN** a client sends `GET /`
- **THEN** the service responds with HTTP status 200
- **AND** returns the configured plain-text greeting

### Requirement: Unknown routes are rejected

The service MUST respond to requests outside `GET /` with HTTP status 404 and a plain-text `Not Found` body followed by a newline.

#### Scenario: A client requests an unknown path

- **WHEN** a client sends a request for an unrecognized route
- **THEN** the service responds with HTTP status 404
- **AND** returns a plain-text `Not Found` body
