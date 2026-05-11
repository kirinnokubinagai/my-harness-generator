#!/usr/bin/env bash
# recommend-lanes.sh — compute a sensible MAX_LANES recommendation.
# Sourced by bootstrap.sh and doctor.sh; memory probes live in memory-probe.sh.
#
# Public API:
#   recommend_lanes   → "<n>|total_gb=<X> swap_gb=<Y> effective_gb=<Z> pressure=<green|yellow|red>"
#
# Model:
#   effective_gb = total_ram + (compression bonus on macOS) | swap (on Linux)
#   capacity     = (effective_gb - overhead_gb) / per_lane_gb
#   pressure adjustment: yellow → -1; red → cap to 1
#   absolute ceiling: 4 (Agent Teams beyond → diminishing returns + Codex back-pressure)

# shellcheck shell=bash
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]:-$0}")/memory-probe.sh"

recommend_lanes() {
  local total swap pressure effective overhead per_lane capacity
  total=$(detect_total_ram_gb)
  swap=$(detect_swap_total_gb)
  pressure=$(detect_pressure)

  case "$(uname -s)" in
    Darwin) effective=$(( total + total / 3 + swap / 2 )) ;;
    Linux)  effective=$(( total + swap )) ;;
    *)      effective=$total ;;
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

case "${BASH_SOURCE[0]:-$0}" in
  "${0}") recommend_lanes ;;
esac
