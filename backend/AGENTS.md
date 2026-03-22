# Mise en Place — Backend

## Build & Test
- `go build ./...` — build all packages
- `go test ./...` — run all tests
- `golangci-lint run` — lint

## Architecture
Go server with Chi router. Dependency layers (strict, enforced by structural tests):
`types → config → repo → service → handler`

Each layer can only import layers to its left. Handlers must not import repo directly.

## Conventions
- Table-driven tests with `t.Run`
- Errors: wrap with `fmt.Errorf("context: %w", err)`
- Structured logging via `slog`
- All external APIs behind interfaces for testability
