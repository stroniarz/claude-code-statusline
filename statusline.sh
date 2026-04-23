#!/usr/bin/env bash
# Claude Code statusline (optimized: single-pass jq)
# Segments: ctx | plan (5h/7d) | think | cost | model | cwd

JQ=/usr/bin/jq
input=$(cat)

# --- ANSI colors ---
R=$'\033[0m'; DIM=$'\033[2m'; B=$'\033[1m'
Y=$'\033[33m'; RED=$'\033[31m'; C=$'\033[36m'; G=$'\033[32m'; M=$'\033[35m'

# --- Single jq call: pull everything we need, TSV-delimited ---
# Fields: model_id model_name cwd cost ctx_size ctx_pct_stdin
#         cur_in cur_out cur_cr cur_cc plan5 plan7 exceeds transcript
IFS=$'\t' read -r model_id model_name cwd cost ctx_size ctx_pct_stdin \
  cur_in cur_out cur_cr cur_cc plan5 plan5_reset plan7 plan7_reset exceeds transcript_path <<< "$(
  echo "$input" | $JQ -r '[
    .model.id // "",
    .model.display_name // "",
    .workspace.current_dir // "",
    (.cost.total_cost_usd // ""),
    (.context_window.context_window_size // ""),
    (.context_window.used_percentage // ""),
    (.context_window.current_usage.input_tokens // 0),
    (.context_window.current_usage.output_tokens // 0),
    (.context_window.current_usage.cache_read_input_tokens // 0),
    (.context_window.current_usage.cache_creation_input_tokens // 0),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // ""),
    (.exceeds_200k_tokens // false),
    (.transcript_path // "")
  ] | @tsv'
)"

cwd_base=$(basename "$cwd")

pct_color() {
  if [ "$1" -ge 90 ] 2>/dev/null; then echo "$RED"
  elif [ "$1" -ge 70 ] 2>/dev/null; then echo "$Y"
  fi
}

# --- Context window ---
if [ -z "$ctx_size" ]; then
  case "$model_id" in *1m*|*1M*) ctx_size=1000000 ;; *) ctx_size=200000 ;; esac
fi
if [ "$ctx_size" -ge 1000000 ]; then ctx_label="1M"
elif [ "$ctx_size" -ge 1000 ]; then ctx_label="$((ctx_size/1000))k"
else ctx_label="$ctx_size"
fi

ctx_tokens=$((cur_in + cur_out + cur_cr + cur_cc))
if [ "$ctx_tokens" -eq 0 ] && [ -n "$ctx_pct_stdin" ]; then
  ctx_tokens=$(awk -v p="$ctx_pct_stdin" -v s="$ctx_size" 'BEGIN{printf "%d",(p/100)*s}')
fi

if [ "$ctx_tokens" -gt 0 ]; then
  ctx_pct=$(( ctx_tokens * 100 / ctx_size ))
else
  ctx_pct=0
fi

if [ "$ctx_tokens" -ge 1000000 ]; then
  ctx_fmt=$(awk -v t="$ctx_tokens" 'BEGIN{printf "%.1fM",t/1000000}')
elif [ "$ctx_tokens" -ge 1000 ]; then
  ctx_fmt="$((ctx_tokens/1000))k"
else
  ctx_fmt="$ctx_tokens"
fi
ctx_color=$(pct_color "$ctx_pct")

# --- Effort level (set by /effort slash command in settings.json) ---
effort_level=$($JQ -r '.effortLevel // empty' ~/.claude/settings.json 2>/dev/null)

# --- Think tokens (scan only last 200 transcript lines, one jq call) ---
effort_label=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  think_chars=$(tail -n 200 "$transcript_path" 2>/dev/null | $JQ -r '
    select(.type == "assistant" and (.message.content | type) == "array") |
    .message.content | map(select(.type == "thinking") | (.thinking // "") | length) | add // 0
  ' 2>/dev/null | tail -1)
  if [ -n "$think_chars" ] && [ "$think_chars" -gt 0 ] 2>/dev/null; then
    think_toks=$((think_chars / 4))
    if [ "$think_toks" -ge 1000 ]; then
      effort_label=$(awk -v t="$think_toks" 'BEGIN{printf "%.1fk",t/1000}')
    else
      effort_label="$think_toks"
    fi
  fi
fi

# --- Cost ---
if [ -n "$cost" ]; then
  cost_fmt=$(awk -v c="$cost" 'BEGIN{printf "$%.2f",c}')
fi

# --- Warning ---
warn=""
[ "$exceeds" = "true" ] && warn="${Y}[>200k]${R} "

# --- Assemble ---
segs=("${warn}${ctx_color}◧ ${ctx_fmt}/${ctx_label} ${ctx_pct}%${R}")

# --- Format relative time until reset (e.g. "2h15m", "45m", "3d4h") ---
fmt_reset() {
  local ts=$1 now=$(date +%s) diff
  [ -z "$ts" ] && return
  diff=$((ts - now))
  [ "$diff" -le 0 ] && { echo "now"; return; }
  local d=$((diff/86400)) h=$(((diff%86400)/3600)) m=$(((diff%3600)/60))
  if [ "$d" -gt 0 ]; then echo "${d}d${h}h"
  elif [ "$h" -gt 0 ]; then echo "${h}h${m}m"
  else echo "${m}m"
  fi
}

# Sanitize: valid percentages are 0..100. Anything else (e.g. raw timestamp
# leaking into used_percentage on a fresh session) is treated as missing.
valid_pct() {
  [ -n "$1" ] && [ "$1" -ge 0 ] 2>/dev/null && [ "$1" -le 100 ] 2>/dev/null
}
valid_pct "$plan5" || plan5=""
valid_pct "$plan7" || plan7=""

if [ -n "$plan5" ]; then
  p5c=$(pct_color "$plan5")
  r5=$(fmt_reset "$plan5_reset")
  [ -n "$r5" ] && r5=" ${DIM}→ ${r5}${R}"
  plan_str="${DIM}⏱${R} ${p5c}${plan5}%${R}${r5}"
  if [ -n "$plan7" ]; then
    p7c=$(pct_color "$plan7")
    r7=$(fmt_reset "$plan7_reset")
    [ -n "$r7" ] && r7=" ${DIM}→ ${r7}${R}"
    plan_str="${plan_str}  ${DIM}⊞${R} ${p7c}${plan7}%${R}${r7}"
  fi
  segs+=("$plan_str")
fi

# effort segment: prefer explicit level from /effort, append think tokens if present
if [ -n "$effort_level" ] || [ -n "$effort_label" ]; then
  eff_parts=""
  if [ -n "$effort_level" ]; then
    case "$effort_level" in
      low)    eff_color=$G ;;
      medium) eff_color=$Y ;;
      high)   eff_color=$RED ;;
      max)    eff_color="${B}${RED}" ;;
      *)      eff_color=$M ;;
    esac
    eff_parts="${eff_color}${effort_level}${R}"
  fi
  if [ -n "$effort_label" ]; then
    [ -n "$eff_parts" ] && eff_parts="${eff_parts}${DIM}/${R}"
    eff_parts="${eff_parts}${M}${effort_label}${R}"
  fi
  segs+=("${DIM}⚡${R}${eff_parts}")
fi
[ -n "$cost_fmt" ]     && segs+=("${B}${cost_fmt}${R}")
model_short=${model_name% (*}
segs+=("${C}◆ ${model_short}${R}")

# --- Git branch (one fork; empty when cwd isn't inside a repo) ---
branch=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  branch=$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null)
  [ -z "$branch" ] && branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
fi

if [ -n "$branch" ]; then
  segs+=("${G}▸ ${cwd_base}${R} ${DIM}⎇${R} ${M}${branch}${R}")
else
  segs+=("${G}▸ ${cwd_base}${R}")
fi

sep="${DIM} | ${R}"
out="${segs[0]}"
for s in "${segs[@]:1}"; do out+="${sep}${s}"; done
printf '%s\n' "$out"
