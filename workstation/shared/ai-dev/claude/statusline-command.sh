#!/usr/bin/env bash
# Claude Code statusLine command
# Format: <model> <effort> | <used>/<total> (<pct%>) | I:<cur>(<total>) O:<cur>(<total>) IC:<cur>(<total>) IW:<cur>(<total>) | $<cost>

input=$(cat)

# --- ANSI color codes ---
RESET='\033[0m'
CYAN_BOLD='\033[1;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
MAGENTA_BOLD='\033[1;35m'
RED_BOLD='\033[1;31m'
DIM_CYAN='\033[2;36m'
DIM_YELLOW='\033[2;33m'
DIM_GREEN='\033[2;32m'
DIM_WHITE='\033[2;37m'

SEP="${DIM_WHITE} | ${RESET}"

# --- Extract fields from JSON ---
model=$(echo "$input"        | jq -r '.model.display_name // empty')
effort=$(echo "$input"       | jq -r '.effort.level // empty')
ctx_size=$(echo "$input"     | jq -r '.context_window.context_window_size // empty')
used_pct=$(echo "$input"     | jq -r '.context_window.used_percentage // empty')
cur_usage=$(echo "$input"    | jq -r '.context_window.current_usage // empty')
total_input=$(echo "$input"  | jq -r '.context_window.total_input_tokens // 0')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
transcript=$(echo "$input"   | jq -r '.transcript_path // empty')
cost_usd=$(echo "$input"     | jq -r '.cost.total_cost_usd // empty')

input_tokens=0
output_tokens=0
cache_read_tokens=0
cache_write_tokens=0

if [ -n "$cur_usage" ] && [ "$cur_usage" != "null" ]; then
    input_tokens=$(echo "$input"       | jq -r '.context_window.current_usage.input_tokens // 0')
    output_tokens=$(echo "$input"      | jq -r '.context_window.current_usage.output_tokens // 0')
    cache_read_tokens=$(echo "$input"  | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
    cache_write_tokens=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
fi

# --- Parse transcript for cumulative IC/IW totals (with delta cache) ---
# Cache file keyed by transcript path. Stores "size:ic:iw" so subsequent
# renders only parse newly-appended bytes instead of re-slurping the whole
# transcript. Self-heals on parse failure or transcript truncation.
total_ic=0
total_iw=0
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    # wc/cksum rather than stat -c/md5sum: the same file is installed on macOS,
    # whose BSD stat takes different flags and which ships no md5sum.
    current_size=$(wc -c < "$transcript" 2>/dev/null | tr -d ' ' || echo 0)
    cache_key=$(printf '%s' "$transcript" | cksum | awk '{print $1}')
    cache_file="/tmp/statusline-cache-${cache_key}"

    cached_size=0
    cached_ic=0
    cached_iw=0
    if [ -f "$cache_file" ]; then
        IFS=: read -r cached_size cached_ic cached_iw < "$cache_file" || true
        cached_size=${cached_size:-0}
        cached_ic=${cached_ic:-0}
        cached_iw=${cached_iw:-0}
    fi

    sum_jq='
        map(select(.message.usage != null) | .message.usage) |
        {
            ic: ([.[].cache_read_input_tokens // 0] | add // 0),
            iw: ([.[].cache_creation_input_tokens // 0] | add // 0)
        }
    '

    if [ "$current_size" = "$cached_size" ] && [ "$cached_size" -gt 0 ]; then
        total_ic=$cached_ic
        total_iw=$cached_iw
    else
        scan_ok=0
        # Incremental: parse only the new tail bytes
        if [ "$current_size" -gt "$cached_size" ] && [ "$cached_size" -gt 0 ]; then
            delta=$((current_size - cached_size))
            tail_totals=$(head -c "$current_size" "$transcript" 2>/dev/null | tail -c "$delta" | jq -s "$sum_jq" 2>/dev/null)
            if [ -n "$tail_totals" ]; then
                new_ic=$(echo "$tail_totals" | jq -r '.ic // 0')
                new_iw=$(echo "$tail_totals" | jq -r '.iw // 0')
                total_ic=$((cached_ic + new_ic))
                total_iw=$((cached_iw + new_iw))
                scan_ok=1
            fi
        fi
        # Fallback: full rescan (no cache, transcript shrank, or tail parse failed)
        if [ "$scan_ok" = "0" ]; then
            full_totals=$(head -c "$current_size" "$transcript" 2>/dev/null | jq -s "$sum_jq" 2>/dev/null)
            if [ -n "$full_totals" ]; then
                total_ic=$(echo "$full_totals" | jq -r '.ic // 0')
                total_iw=$(echo "$full_totals" | jq -r '.iw // 0')
                scan_ok=1
            fi
        fi
        # Atomic cache write (only on successful scan)
        if [ "$scan_ok" = "1" ]; then
            tmp_cache="${cache_file}.tmp.$$"
            if printf '%s:%s:%s\n' "$current_size" "$total_ic" "$total_iw" > "$tmp_cache" 2>/dev/null; then
                mv "$tmp_cache" "$cache_file" 2>/dev/null || rm -f "$tmp_cache"
            fi
        fi
    fi
fi

# --- Helper: abbreviate token number to K/M ---
fmt_tokens() {
    local n="$1"
    if [ -z "$n" ] || [ "$n" = "null" ]; then echo "0"; return; fi
    awk -v n="$n" 'BEGIN {
        if (n >= 1000000)   { printf "%.2fM\n", n/1000000 }
        else if (n >= 1000) { printf "%.2fK\n", n/1000 }
        else                { printf "%d\n", n }
    }'
}

# --- Build output ---

# Model name: bold cyan
if [ -n "$model" ]; then
    out="${CYAN_BOLD}${model}${RESET}"
else
    out="${CYAN_BOLD}(no model)${RESET}"
fi

# Effort: small tag after model. Ascending intensity ramp across the
# Claude Code levels: low < medium < high < xhigh < max, plus the
# session-only `ultracode` mode (xhigh reasoning + dynamic workflows).
if [ -n "$effort" ]; then
    case "$effort" in
        low)       eff_color="$DIM_WHITE" ;;
        medium)    eff_color="$GREEN" ;;
        high)      eff_color="$YELLOW" ;;
        xhigh)     eff_color="$MAGENTA" ;;
        max)       eff_color="$RED_BOLD" ;;
        ultracode) eff_color="$MAGENTA_BOLD" ;;
        *)         eff_color="$DIM_WHITE" ;;
    esac
    out="${out} ${eff_color}${effort}${RESET}"
fi

# Context: used/total (pct%)  — green, yellow when >75%
if [ -n "$ctx_size" ] && [ "$ctx_size" != "0" ]; then
    cur_ctx=$(( input_tokens + cache_read_tokens + cache_write_tokens ))
    used_fmt=$(fmt_tokens "$cur_ctx")
    total_fmt=$(fmt_tokens "$ctx_size")
    ctx_color="$GREEN"
    if [ -n "$used_pct" ]; then
        used_int=${used_pct%.*}
        [ "$used_int" -gt 75 ] 2>/dev/null && ctx_color="$YELLOW"
        pct_str=" (${used_int}%)"
    else
        pct_str=""
    fi
    out="${out}${SEP}${ctx_color}${used_fmt}/${total_fmt}${pct_str}${RESET}"
fi

# Token detail: I O IC IW — each with current(total)
if [ -n "$cur_usage" ] && [ "$cur_usage" != "null" ]; then
    i_fmt=$(fmt_tokens  "$input_tokens")
    it_fmt=$(fmt_tokens "$total_input")
    o_fmt=$(fmt_tokens  "$output_tokens")
    ot_fmt=$(fmt_tokens "$total_output")
    ic_fmt=$(fmt_tokens "$cache_read_tokens")
    ict_fmt=$(fmt_tokens "$total_ic")
    iw_fmt=$(fmt_tokens "$cache_write_tokens")
    iwt_fmt=$(fmt_tokens "$total_iw")

    detail="${BLUE}I:${i_fmt}(${it_fmt})${RESET}"
    detail="${detail}${DIM_WHITE}, ${RESET}${MAGENTA}O:${o_fmt}(${ot_fmt})${RESET}"
    detail="${detail}${DIM_WHITE}, ${RESET}\033[0;36mIC:${ic_fmt}(${ict_fmt})${RESET}"
    detail="${detail}${DIM_WHITE}, ${RESET}${YELLOW}IW:${iw_fmt}(${iwt_fmt})${RESET}"
    out="${out}${SEP}${detail}"
fi

# Cost: $X.XX — dim green
if [ -n "$cost_usd" ] && [ "$cost_usd" != "null" ]; then
    cost_fmt=$(awk -v c="$cost_usd" 'BEGIN { printf "$%.2f\n", c }')
    out="${out}${SEP}${DIM_GREEN}${cost_fmt}${RESET}"
fi

printf '%b\n' "$out"
