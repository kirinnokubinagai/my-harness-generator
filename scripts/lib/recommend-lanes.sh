#!/usr/bin/env bash
# recommend-lanes.sh — compute a sensible MAX_LANES recommendation for the
# current host. Sourced by bootstrap.sh and doctor.sh.
#
# Public API:
#   recommend_lanes        → prints "<n>|total_gb=<X> swap_gb=<Y> effective_gb=<Z> pressure=<green|yellow|red>"
#   detect_total_ram_gb    → integer GB
#   detect_swap_gb         → integer GB
#   detect_pressure        → green|yellow|red (macOS uses memory_pressure; others always green)
#
# Model:
#   effective_gb = total_ram + (compression_bonus on macOS) | swap (on Linux)
#   capacity     = (effective_gb - overhead_gb) / per_lane_gb
#   pressure adjustment: yellow → -1, red → cap to 1
#   absolute ceiling: 4 (Agent Teams beyond that hits diminishing returns and
#                        Codex daemon back-pressure)
#
# Why this matters: macOS over-commits via memory compression + swap, so
# physical RAM is not the cap. The runtime gate (spawn-lane-decision.sh) is
# still the source of truth at spawn time — this script only seeds a
# user-friendly default.

# shellcheck shell=bash

detect_total_ram_gb() {
  sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024/1024)}' \
    || awk '/^MemTotal:/{print int($2/1024/1024)}' /proc/meminfo 2>/dev/null \
    || echo 16
}

detect_swap_gb() {
  case "$(uname -s)" in
    Darwin)
      # vm.swapusage looks like: total = 4096.00M ...
      local raw
      raw=$(sysctl -n vm.swapusage 2>/dev/null \
        | awk '{for(i=1;i<=NF;i++) if($i=="total")print $(i+2)}' \
        | sed 's/M$//')
      [ -n "$raw" ] && printf '%d' "$(awk -v v="$raw" 'BEGIN{print int(v/1024)}')" \
        || echo 0
      ;;
    Linux)
      awk '/^SwapTotal:/{print int($2/1024/1024)}' /proc/meminfo 2>/dev/null \
        || echo 0
      ;;
    *) echo 0 ;;
  esac
}

detect_pressure() {
  case "$(uname -s)" in
    Darwin)
      if command -v memory_pressure >/dev/null 2>&1; then
        local out
        out=$(memory_pressure -Q 2>/dev/null || true)
        case "$out" in
          *Critical*|*critical*) echo red ;;
          *Warn*|*warning*)      echo yellow ;;
          *Normal*|*normal*|*)   echo green ;;
        esac
      else
        echo green
      fi
      ;;
    *) echo green ;;
  esac
}

recommend_lanes() {
  local total swap pressure effective overhead per_lane capacity
  total=$(detect_total_ram_gb)
  swap=$(detect_swap_gb)
  pressure=$(detect_pressure)

  case "$(uname -s)" in
    Darwin)
      # +33% effective via memory compression. Add half of swap on top — macOS
      # swaps gracefully on SSD but performance degrades past that.
      effective=$(( total + total / 3 + swap / 2 ))
      ;;
    Linux)
      # Swap is fair game on Linux for over-commit but slower than RAM.
      effective=$(( total + swap ))
      ;;
    *) effective=$total ;;
  esac

  overhead=4
  per_lane=4
  capacity=$(( (effective - overhead) / per_lane ))

  case "$pressure" in
    yellow) capacity=$(( capacity - 1 )) ;;
    red)    capacity=1 ;;
  esac

  [ "$capacity" -gt 4 ] && capacity=4
  [ "$capacity" -lt 1 ] && capacity=1

  printf '%d|total_gb=%d swap_gb=%d effective_gb=%d pressure=%s\n' \
    "$capacity" "$total" "$swap" "$effective" "$pressure"
}

# CLI: when run directly, print the recommendation. Sourced files just expose
# the functions.
case "${BASH_SOURCE[0]:-$0}" in
  "${0}") recommend_lanes ;;
esac
