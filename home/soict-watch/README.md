# SOICT website monitor

Beast runs `soict-watch.service` as user `shogo` daily at 09:00, 12:00, and
16:00 in Beast's local timezone, without randomized delay, through December 10,
2026 (inclusive). No runs are scheduled afterward, and a service condition also
skips late catch-up or manual starts from December 11 onward. Lingering keeps
the user manager running without a login.

## Before deployment

Add a **new Slack incoming webhook URL** under `gitcrawl-slack-webhook` in the
existing encrypted Home Manager secrets file:

```sh
sops secrets/home.yaml
```

Do this before rebuilding Beast: the secret declaration expects that key to
exist. Do not put the plaintext URL in Nix or commit an unencrypted value.
The existing Discord webhook is not used or changed.

Pi must already be authenticated with OpenAI Codex as `shogo` on Beast (run `pi`
and `/login` if needed). Reviews and repair attempts explicitly use
`openai-codex/gpt-6-luna`, regardless of Pi's configured default. The timer uses the
Bubblewrap/Pueue wrapper with `@noflake`, making the year's state directory the
sandbox root without requiring a `flake.nix`. Its built-in `read`, `bash`, `edit`,
and `write` tools are enabled, along with the explicitly loaded
`validate-report.ts` extension; unrelated extensions, MCP, skills, project
resources, and context files are disabled. The normal wrapper mounts still
apply, including writable Pi configuration/authentication and Nix cache
access; this is not a dedicated-user sandbox. The webhook stays outside the
sandbox and is never included in the prompt. Website content is sent to the
configured AI provider when changes occur.

Rebuild Beast using the usual repository workflow. Then, as `shogo` on Beast:

```sh
systemctl --user start soict-watch.service
systemctl --user list-timers soict-watch.timer
journalctl --user -u soict-watch.service -n 100
```

The first complete crawl establishes a baseline without starting Pi or sending a
message. Subsequent Markdown changes (including newly linked or removed pages)
start a fresh noninteractive Pi session. Pi writes a Japanese structured report
to `response.json`, using the JSON Schema included in its prompt. The message
shows 「ホームページに変更がありました。」 followed by one collapsed Slack
`container` per category, with separate text sections for related changes and
page URLs. Empty categories are omitted; report content is rendered as plain
text rather than interpreting Slack markup or mentions.

The explicitly loaded `validate-report.ts` extension checks the file at
`agent_before_settle` (the last actionable boundary, not session shutdown).
Missing files, malformed JSON, schema violations, and oversized sections cause
a follow-up user prompt containing validation errors, allowing up to three
repair attempts in the same session. Aborted or failed runs are not continued.
The monitor validates again before delivery using the same Python validator and
schema. If repairs fail, no message is sent and the baseline stays unchanged.
The original 10-minute Pi timeout covers the review and all repairs.

The shared validator also checks the generated Slack payload against the
[documented block limits](https://docs.slack.dev/reference/block-kit/blocks/):
50 top-level blocks per message,
[10 children and a 150-character title per container](https://docs.slack.dev/reference/block-kit/blocks/container-block/),
and [3,000 characters per section](https://docs.slack.dev/reference/block-kit/blocks/section-block/).
The report schema intentionally stays below these limits: six categories, five
sections per category, 100-character titles, and 2,800-character sections.
Fallback `text` must not exceed the
[40,000-character truncation threshold](https://docs.slack.dev/reference/methods/chat.postMessage/);
Slack's 4,000-character advice is a recommendation, not a hard limit. The fixed
Japanese fallback is much shorter. These checks count Unicode code points, not
UTF-8 bytes; Slack's docs do not define counting for complex emoji. No aggregate
block-text or JSON-byte limit is assumed, since these references do not document
one. Boundary checks can be run with the monitor's Python environment:

```sh
python3 -m unittest discover -s home/soict-watch
```

Only an acknowledged Slack POST advances the baseline. A failed crawl, review,
or delivery leaves it unchanged so the next scheduled run can retry. A POST that
Slack accepts just before a connection failure can produce a duplicate on retry.

## Crawl scope

- Start at `https://soict.org/` and recursively follow same-host HTML links until
  the queue is exhausted; there is no arbitrary depth cutoff.
- Treat the live root site and its yearless pages as the current conference.
  Exclude paths containing another `20xx` year, `previous-conferences`, WordPress
  internals, feeds, query URLs, and non-HTML files. External sites, PDFs, images,
  and JavaScript-only links are not crawled.
- Determine the year from Beast's clock. Require the homepage title to advertise
  `SOICT <current year>`; fail rather than silently monitor the previous edition
  after New Year. Each year has an independent baseline.
- Respect `robots.txt` and wait at least one second between page requests. Stop
  with an error rather than accepting a truncated crawl if 200 pages are reached.
- A small Python discovery loop supplies HTML to `gitcrawl archive -i`, because
  upstream's recursive crawler cannot exclude past conference years. Every run
  refetches pages so unchanged parent pages do not hide changed descendants.
- Compare only gitcrawl's Markdown, not raw HTML, assets, or fetch metadata.
  Publication/update timestamps are not a relevance filter: yearless pages in
  the live conference navigation may have originally been published years ago.

## Files and troubleshooting

State is stored in `~/.local/state/soict-watch/<year>/` (or the configured
Home Manager `xdg.stateHome`). It contains:

- `archive/`: gitcrawl's Git repository, snapshots on the `archive` branch.
- `baseline.json`: last successfully handled Markdown snapshot.
- `current.json`: latest complete crawl.
- `changes.diff`: differences since the baseline.
- `response.json`: categorized report written by Pi, in Japanese (replaces `response.md`).
- `pi.log`: Pi stdout and stderr for the latest review.
- `payload.json`: JSON sent to Slack.

systemd prevents overlapping activations of this service. `Persistent=true`
performs one catch-up run after downtime. Crawl failures appear in the journal;
Pi failures also have details in `pi.log`. Failed runs trigger
`soict-watch-failure.service`, which sends a red Discord notification through
`local-notify`, the same host notification backend used by Pueue and Pi. This
also covers service-level timeouts and startup failures that put the monitor in
a failed state. Normal no-change runs and the end-date condition do not alert.
Notifications contain only fixed diagnostic instructions, not exception text,
website content, or webhook URLs. Notification delivery is attempted once, with
no automatic retry or recursive failure handler; delivery errors appear in
`journalctl --user -u soict-watch-failure.service`. The existing
`pueue-discord-webhook` secret and host D-Bus notification service are reused;
no new webhook is needed. Failures do not send a substitute Slack message.
To deliberately reset the baseline, stop the service and remove
only `baseline.json`; the next successful crawl becomes the new silent baseline.
