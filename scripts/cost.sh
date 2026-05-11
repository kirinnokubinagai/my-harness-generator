#!/usr/bin/env bash
# cost.sh — Codex token / 推定 USD を集計する。
# `.my-harness/logs/codex-cost.jsonl` を読み、role 別 / 期間別に合計を出す。
#
# JSONL フォーマット (codex-ask.sh / codex-exec.sh が書く):
#   {"ts":"2026-05-11T12:00:00Z","role":"engineer","lane":2,"input_tokens":1200,"output_tokens":340,"model":"gpt-5"}
#
# 推定単価 (`scripts/lib/codex-price.json` で上書き可、無ければデフォルト):
#   gpt-5            : $5.00 / 1M input, $15.00 / 1M output
#   o4-pro           : $10.00 / 1M input, $30.00 / 1M output
#   codex-mini       : $1.00 / 1M input, $4.00 / 1M output
#
# Usage:
#   bash scripts/cost.sh                       # 全期間
#   bash scripts/cost.sh --since 2026-05-01    # 指定期間
#   bash scripts/cost.sh --json                # 機械可読

set -u

JSON=0
SINCE=""
UNTIL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json)  JSON=1;     shift ;;
    --since) SINCE="$2"; shift 2 ;;
    --until) UNTIL="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

__resolve_root() {
  local d="${1:-$PWD}"
  while [ "$d" != "/" ]; do
    [ -d "$d/.bare" ] && { echo "$d"; return 0; }
    d="$(dirname "$d")"
  done
  echo "${1:-$PWD}"
}
ROOT="$(__resolve_root "$PWD")"
LOG="$ROOT/.my-harness/logs/codex-cost.jsonl"

if [ ! -f "$LOG" ]; then
  if [ "$JSON" -eq 1 ]; then
    echo '{"total_usd":0,"records":0,"note":"no codex-cost.jsonl yet"}'
  else
    echo "no Codex cost log yet ($LOG)"
    echo "codex-ask.sh / codex-exec.sh が token を記録するようになるとここに溜まります"
  fi
  exit 0
fi

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 3; }

jq -s --arg since "$SINCE" --arg until "$UNTIL" --argjson json "$JSON" '
  def price(model):
    if   model == "gpt-5"      then {in: 5,  out: 15}
    elif model == "o4-pro"     then {in: 10, out: 30}
    elif model == "codex-mini" then {in: 1,  out: 4}
    else                            {in: 5,  out: 15}
    end;
  map(select(($since == "" or .ts >= $since) and ($until == "" or .ts <= $until)))
  | map(
      . + {
        usd: ((.input_tokens // 0) * (price(.model // "").in)
            + (.output_tokens // 0) * (price(.model // "").out)) / 1000000
      }
    )
  | {
      total_usd: (map(.usd) | add // 0),
      records:   length,
      by_role:   (group_by(.role // "unknown")
                    | map({role: .[0].role, count: length,
                           input: (map(.input_tokens // 0) | add),
                           output: (map(.output_tokens // 0) | add),
                           usd: (map(.usd) | add // 0)})),
      by_model:  (group_by(.model // "unknown")
                    | map({model: .[0].model, count: length, usd: (map(.usd) | add // 0)}))
    }
  | if $json == 1 then .
    else "Total: $\(.total_usd | tostring | .[0:6]) (\(.records) records)\n\nBy role:\n" +
         (.by_role | map("  \(.role): $\(.usd | tostring | .[0:6])  in=\(.input)  out=\(.output)") | join("\n")) +
         "\n\nBy model:\n" +
         (.by_model | map("  \(.model): $\(.usd | tostring | .[0:6])") | join("\n"))
    end
' "$LOG" | { if [ "$JSON" -eq 1 ]; then cat; else jq -r .; fi }
