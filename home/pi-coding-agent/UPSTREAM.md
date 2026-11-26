# Upstream sources and update notes

The host broker is local code. Two tools patch published npm packages; the
usage and GitHub integrations track upstream behavior without installing a fork.
The companion [pi-customizations credits](https://github.com/pineapplehunter/pi-customizations/blob/main/CREDITS.md#patched-tools-and-compatibility-references)
link to the sandbox-side code. Update the docs and the corresponding version
or hash pins together; `pi-update` does not rebase either patch.

[codex-host.nix](codex-host.nix) runs strict, no-emit type checking against
the packaged Pi SDK using `pkgs.typescript` (the Go compiler in the pinned
nixpkgs). It then checks Node's native TypeScript syntax before
installing the broker. The service runs those same `.mts` files directly.

The build runs [chat differential tests](pineapplehunter/wrapper/codex_chat.test.mjs)
against the packaged Pi Codex provider: full and simple requests, streamed text,
thinking and tool calls, usage, refusals, HTTP/stream failures, retries, and
cancellation. They use fake credentials and a mock upstream, not a live account.

The compatibility target is native Pi Codex chat. The client requests the SDK's
`auto` transport by default. The broker accepts only SDK transport names (SSE,
WebSocket, cached WebSocket, or auto), pins the endpoint, and gates priority on
Fast capability. WebSocket continuation is account-, credential-, and session-scoped;
an isolated replay or a token change cannot reuse the previous socket. A second
offline test checks delta requests, socket isolation, and fallback to guarded SSE. It never forwards client credentials, custom headers, URLs, or fetch
implementations. `onPayload` edits the broker request, not raw OpenAI JSON.
`onResponse` receives upstream status per HTTP attempt, without upstream headers;
raw provider-event callbacks are not proxied. A successful WebSocket chat
doesn't synthesize an HTTP status event.
The broker caps a chat at 15 minutes and accepts at most five SDK retries.
The [compiler config](pineapplehunter/wrapper/codex-tsconfig.json) enables
`strict` plus checks for missing returns, switch fall-through, unused code,
and explicit type-only imports. Keep runtime validation for socket input
and upstream JSON; compiler types alone do not validate either.

## Web search and page helpers

The base is Nico Bailon's [pi-web-access](https://github.com/nicobailon/pi-web-access)
(MIT), published as [npm 0.48.0](https://www.npmjs.com/package/pi-web-access/v/0.48.0).
The patch, bundle hashes, and porting instructions live in
[pi-customizations `extensions/codex-host/web/`](https://github.com/pineapplehunter/pi-customizations/tree/main/extensions/codex-host/web).
The patch changes only the published Pi `dist/index.js`, not the MCP build.
On this side, [codex_search.mts](pineapplehunter/wrapper/codex_search.mts) implements
hosted search; [codex_host.mts](pineapplehunter/wrapper/codex_host.mts) wires it
into `/v1/search`. Run the mocked host test after changing the contract:

```sh
node --test home/pi-coding-agent/pineapplehunter/wrapper/codex_search.test.mjs
```

## Codex image generation

The base is Jose Mocito's [pi-codex-image-gen](https://github.com/jvm/pi-mono/tree/main/packages/pi-codex-image-gen)
(Apache-2.0), published as [npm 0.3.2](https://www.npmjs.com/package/pi-codex-image-gen/v/0.3.2).
Its bundled `imagegen` skill was itself adapted from [OpenAI Codex's imagegen skill](https://github.com/openai/codex/tree/main/codex-rs/skills/src/assets/samples/imagegen).

- [codex-images.nix](codex-images.nix) pins the exact npm tarball and
  `@silvia-odwyer/photon-node` (0.3.4), including their hashes. The upstream
  notices ship with the package.
- [codex-image.patch](pineapplehunter/wrapper/codex-image.patch) changes
  `extensions/index.ts` and `skills/imagegen/SKILL.md`: the sandbox sends
  image requests through the Unix socket and never registers a local OAuth
  provider. It retains upstream reference selection, saves, and artifacts.
- [codex_image_client.ts](pineapplehunter/wrapper/codex_image_client.ts) is
  installed as `src/host-image.ts` in the patched package.
  [codex_image_host.mts](pineapplehunter/wrapper/codex_image_host.mts) uses
  upstream `src/image-oauth.ts`, `src/images-request.ts`, and
  `src/codex-response.ts` for host-side OAuth, request building, and parsing.

To upgrade, unpack the exact candidate npm tarball into a fresh directory and
port the patch against it. Review those three upstream modules for changed
exports, request shapes, or response parsing. Regenerate the patch from clean
and edited copies, update the package version and fixed-output hash in
`codex-images.nix`, and rebuild the host configuration before switching it.
Check that both image transports still handle references and errors, that
saved artifacts can be recovered, and that an absent socket, missing login,
or an Off route never invokes another account or local OAuth. Use fixtures for
these checks so they do not spend image quota.

## Usage, reset credits, and Fast mode

The compatibility reference is [@narumitw/pi-usage](https://github.com/narumiruna/pi-extensions/tree/main/packages/pi-usage)
(MIT), specifically [npm 0.69.3](https://www.npmjs.com/package/@narumitw/pi-usage/v/0.69.3)
at implementation. Compare its `src/providers/codex.ts` (quota windows),
`src/codex-resets.ts` (credit listing and redemption), and
`src/codex-fast-catalog.ts` (priority capability). It is not a dependency:
update the local broker and [sandbox usage UI](https://github.com/pineapplehunter/pi-customizations/blob/main/extensions/codex-host/usage.ts)
when the protocol changes. Keep credentials host-only and mock redemption
when testing account and credit binding.

The chat broker and auth dashboard also reuse the SDK and TUI shipped by
[Pi](https://github.com/earendil-works/pi) through `pkgs.pi-coding-agent`.
On Pi upgrades, verify `ModelRuntime`, SSE event and usage shapes, and whether
`streamSimple` passes the priority tier. With Pi 1.5.2 it did not, so Fast uses
the full stream API.

## GitHub fetch shim

This is a local compatibility shim for `pi-web-access`, not a fork of `gh`.
Compare `github-api.ts`, `github-extract.ts`, and `github-issue-pr.ts` in the
candidate npm tarball with the command shapes accepted by
[github_fetch_daemon.py](pineapplehunter/wrapper/github_fetch_daemon.py) and
[github_fetch_client.py](pineapplehunter/wrapper/github_fetch_client.py).
Check repo metadata, file reads, issue/PR JSON fields, and review comment
pagination. Only add the exact read invocations the tools need; keep unrelated
commands denied and public clones sandbox-local.
