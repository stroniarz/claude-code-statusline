# cc-slim-statusline

A **minimalist bash statusline** for [Claude Code](https://claude.com/claude-code): context window, plan limits with reset times, effort level, cost and model — in one line. **One file, no Node, no npm, ~20ms render.**

```
◧ 51k/1M 5% | ⏱ 15% → 3h9m  ⊞ 30% → 5d13h | ⚡ medium | $0.81 | ◆ Opus 4.7 | ▸ my-project
```

## Features

- **`◧` Context window** — live token count, percentage of the model's context window (auto-detects `1M` vs `200k` from model id). Turns yellow above 70%, red above 90%.
- **`⏱` 5-hour plan window** — percentage used + time until reset (e.g. `3h9m`).
- **`⊞` 7-day plan window** — percentage used + time until reset (e.g. `5d13h`).
- **`⚡` Effort level** — reads `effortLevel` from `~/.claude/settings.json` (set via `/effort`). Color-coded: green (low), yellow (medium), red (high), bold red (max).
- **`$` Cost** — total session cost in USD.
- **`◆` Model** — display name, stripped of context suffix.
- **`▸` CWD** — basename of the current working directory.
- **`[>200k]` warning** — yellow flag when context has crossed 200k tokens (relevant on 1M models).

All segments are conditional: if a field isn't present in the stdin payload, its segment is skipped rather than showing empty data.

## Screenshot

_Add one: run the script with a real session, paste the rendered output._

## Requirements

- `bash` 4+
- [`jq`](https://jqlang.github.io/jq/) (`brew install jq` on macOS, `apt install jq` on Debian/Ubuntu)
- Claude Code v2.1+ (earlier versions don't expose `rate_limits` or `context_window` in statusline stdin)

## Install

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/stroniarz/cc-slim-statusline/main/install.sh | bash
```

### Manual

1. Copy the script to your Claude config directory:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/stroniarz/cc-slim-statusline/main/statusline.sh \
     -o ~/.claude/statusline.sh
   chmod +x ~/.claude/statusline.sh
   ```

2. Register it in `~/.claude/settings.json` under the `statusLine` key:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash /Users/YOU/.claude/statusline.sh"
     }
   }
   ```

   Replace `/Users/YOU/` with your actual home path (`$HOME` is not expanded in settings.json).

3. Restart Claude Code (or start a new session) to see the statusline.

## How it works

Claude Code pipes a JSON payload into the statusline command on every turn. This script parses it with a single `jq` call and renders the segments. It also reads the last 200 lines of the active transcript to detect thinking tokens (optional, shown as `/1.2k` next to the effort segment).

The entire render takes ~20ms on a typical session (measured with `time`).

## Color coding

| Color | Meaning |
|---|---|
| default | normal |
| yellow | warning (≥70% plan/context usage, or medium effort) |
| red | critical (≥90% usage, high effort) |
| bold red | max effort |
| dim | labels and separators |

## Configuration

All behavior lives in `statusline.sh` — edit it directly. Common tweaks:

- **Change icons** — search for `◧`, `⏱`, `⊞`, `⚡`, `$`, `◆`, `▸` and replace with your preferred glyphs (Nerd Font, emoji, ASCII…).
- **Reorder segments** — segments are built as an array `segs=(...)`, rearrange `segs+=(...)` lines.
- **Change thresholds** — edit `pct_color()` (default: 70/90%).
- **Context window size fallback** — edit the `1M` vs `200k` heuristic near the top.

## Troubleshooting

- **Statusline not showing** — confirm `~/.claude/settings.json` has the `statusLine` block and the path is absolute (not `~`). Run `bash ~/.claude/statusline.sh < /dev/null` to see stderr errors.
- **Empty segments** — your Claude Code may be older than v2.1. Upgrade: `curl -fsSL https://claude.ai/install.sh | bash`.
- **Icons look broken** — your terminal font doesn't support those Unicode glyphs. Replace them with ASCII alternatives (`[ctx]`, `[5h]`, etc.).
- **Slow** — make sure `jq` is installed natively (not via a wrapper). Benchmark: `time (echo "$payload" | bash ~/.claude/statusline.sh)`.

## Alternatives

If you want more features and don't mind heavier tooling:

- **[sirmalloc/ccstatusline](https://github.com/sirmalloc/ccstatusline)** — TypeScript/Node, interactive TUI config, powerline themes, 40+ widgets (git status, token speed, vim mode…). Feature-rich.
- **[rz1989s/claude-code-statusline](https://github.com/rz1989s/claude-code-statusline)** — Bash with TOML config, modular architecture, MCP monitoring, Docker/Homebrew/Debian packaging.

`cc-slim-statusline` intentionally stays small: one bash file you can read in 5 minutes, zero runtime deps beyond `jq`.

## Credits

Built for [Claude Code](https://claude.com/claude-code) — Anthropic's CLI for Claude. The script reads the statusline stdin schema that Claude Code provides; no Claude API calls are made at render time.

## License

MIT — see [LICENSE](LICENSE).
