---
name: rust-preferences
description: Use when creating, editing, or reviewing Rust crates, Cargo.toml dependencies, CLI tools, serialization, logging, error handling, or async/blocking Rust code.
compatibility: pi
---

# Rust Preferences

Use these preferences when working on Rust packages, crates, binaries, and libraries.

## Dependencies

When adding a crate dependency, prefer `cargo add` so Cargo selects the current compatible version and updates `Cargo.toml` correctly:

```shell
cargo add crate-name
```

Use manual `Cargo.toml` edits only when `cargo add` is unavailable, the workspace has unusual dependency management, or an exact version/features layout is required.

Prefer using existing crates for needed functionality instead of implementing custom versions. Check for a well-maintained crate before writing nontrivial parsing, protocol, serialization, cryptography, CLI, logging, or error-handling code.

## Error Handling

Use `color-eyre` for application error handling. Prefer returning `color_eyre::Result<T>` from binaries and setup paths.

For libraries, expose error types appropriate for callers and avoid leaking application-only reporting choices unless the crate is intentionally app-focused.

## Logging

Always use a logging or instrumentation crate.

Use `tracing` for async projects, services, concurrent systems, or code that benefits from structured spans and instrumentation.

Use `log` for blocking crates or libraries where a lightweight facade is enough.

Do not use `println!` or `eprintln!` as the main logging mechanism except for intentional CLI output.

## CLI Arguments

Use `clap` for command-line argument parsing. Prefer derive-based parsers for normal CLIs.

## Serialization

Do not roll your own serialization format. Use `serde` and an appropriate format crate such as `serde_json`, `toml`, `serde_yaml`, `bincode`, or another established format crate.

Prefer explicit, documented formats over ad-hoc delimiter parsing when data may be persisted, exchanged, or consumed by other tools.
