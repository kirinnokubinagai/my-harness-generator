#!/usr/bin/env bash
# memory-probe.sh — single source of truth for memory metrics on macOS / Linux.
# Sourced by recommend-lanes.sh, doctor.sh, and the team-lead spawn gate.
#
# Public API:
#   detect_total_ram_gb       → integer GB
#   detect_avail_ram_mb       → integer MB reclaimable RAM (free + inactive + speculative + purgeable on macOS, MemAvailable on Linux)
#   detect_swap_total_gb      → integer GB
#   detect_swap_used_mb       → integer MB
#   detect_compressor_mb      → integer MB (macOS only; 0 elsewhere)
#   detect_pressure           → green|yellow|red (macOS uses memory_pressure; Linux/other → green)
#
# Why this matters: macOS over-commits via memory compression + swap. Linux uses
# straight swap. Treating them with one formula was the 4.x bug.
#
# Failure mode: every function falls back to a conservative default rather than
# erroring out — the harness should keep going when a probe is unavailable.

# shellcheck shell=bash

detect_total_ram_gb() {
  sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024/1024)}' \
    || awk '/^MemTotal:/{print int($2/1024/1024)}' /proc/meminfo 2>/dev/null \
    || echo 16
}

detect_avail_ram_mb() {
  if [ -r /proc/meminfo ]; then
    awk '/^MemAvailable:/{print int($2/1024); exit}' /proc/meminfo
    return
  fi
  if command -v vm_stat >/dev/null 2>&1; then
    local page free inact spec purg
    page=$(vm_stat | awk '/page size of/{print $8}')
    page=${page:-16384}
    free=$(vm_stat | awk '/Pages free:/{gsub(/\./,"",$3); print $3; exit}')
    inact=$(vm_stat | awk '/Pages inactive:/{gsub(/\./,"",$3); print $3; exit}')
    spec=$(vm_stat | awk '/Pages speculative:/{gsub(/\./,"",$3); print $3; exit}')
    purg=$(vm_stat | awk '/Pages purgeable:/{gsub(/\./,"",$3); print $3; exit}')
    echo $(( ( ${free:-0} + ${inact:-0} + ${spec:-0} + ${purg:-0} ) * page / 1024 / 1024 ))
    return
  fi
  echo 0
}

detect_swap_total_gb() {
  case "$(uname -s)" in
    Darwin)
      local raw
      raw=$(sysctl -n vm.swapusage 2>/dev/null \
        | awk '{for(i=1;i<=NF;i++) if($i=="total")print $(i+2)}' \
        | sed 's/M$//')
      [ -n "$raw" ] && awk -v v="$raw" 'BEGIN{print int(v/1024)}' || echo 0
      ;;
    Linux)
      awk '/^SwapTotal:/{print int($2/1024/1024)}' /proc/meminfo 2>/dev/null || echo 0
      ;;
    *) echo 0 ;;
  esac
}

detect_swap_used_mb() {
  case "$(uname -s)" in
    Darwin)
      local raw
      raw=$(sysctl -n vm.swapusage 2>/dev/null \
        | awk '{for(i=1;i<=NF;i++) if($i=="used")print $(i+2)}' \
        | sed 's/M$//')
      [ -z "$raw" ] && { echo 0; return; }
      printf '%d' "${raw%.*}"
      ;;
    Linux)
      awk '/^SwapTotal:/{t=$2}/^SwapFree:/{f=$2} END{print int(((t-f)>0?(t-f):0)/1024)}' /proc/meminfo 2>/dev/null \
        || echo 0
      ;;
    *) echo 0 ;;
  esac
}

detect_compressor_mb() {
  case "$(uname -s)" in
    Darwin)
      local b
      b=$(sysctl -n vm.compressor_bytes_used 2>/dev/null || echo 0)
      echo $(( b / 1024 / 1024 ))
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
