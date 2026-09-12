# ttyglass

<p align="center">
  <img src="assets/ttyglass-logo.svg" alt="TTYGlass logo" width="240">
</p>

A minimal HTTP service written in Nim.

## Requirements

- Nim
- just

## Run

```sh
just run
```

The service listens on `http://127.0.0.1:8080`. Request the root endpoint with:

```sh
curl http://127.0.0.1:8080/
```

It responds with `Hello, World!` as plain text.

## Development

```sh
just fmt
just check
just build
```

## License

This project is licensed under the [Apache License 2.0](LICENSE).
