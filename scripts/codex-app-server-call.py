#!/usr/bin/env python3
"""
codex-app-server-call.py — Python SDK client for `codex app-server`.

Bridges codex-ask.sh (bash) to Codex through the official codex_app_server_sdk
package. Two transport modes, chosen automatically:

  1. WebSocket to a shared daemon (preferred):
        ws://127.0.0.1:<port>
     Port is read from $HOME/.codex/my-harness-daemon.port (written by
     skills/harness-codex-daemon/scripts/codex-daemon.sh). Multiple lanes share one daemon process —
     conversations stay isolated by threadId; per-turn overhead ~15KB.

  2. Stdio (fallback when no daemon is running):
        spawns its own `codex app-server --listen stdio://`
     Equivalent to the per-call cold-start mode. Same protocol, slower.

Usage (from codex-ask.sh):
  python3 codex-app-server-call.py \
      --prompt-file <path>            # prompt body
      --thread-id-file <path>         # read for resume / write for new
      --cwd <path>                    # turn cwd
      [--model <id>]
      [--log-file <path>]             # full event log (optional)
      [--turn-timeout <sec>]
      [--daemon-port <int>]           # explicit override; default: auto-detect
      [--no-daemon]                   # force stdio
      [--disable-plugin <id>]         # repeatable; disables the named plugin
                                      #   only for this call (does not edit
                                      #   ~/.codex/config.toml)

stdout : the assistant's final reply text
stderr : lifecycle log lines + the codex app-server subprocess stderr
exit   : 0 success, 1 protocol/runtime error, 2 bad arguments

Requires the project venv at $HOME/.codex/my-harness-venv populated by
scripts/install-codex-sdk.sh (codex_app_server_sdk + websockets + pydantic).
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import socket
import sys
from pathlib import Path
from typing import Any, Optional

try:
    from codex_app_server_sdk import (
        CodexClient,
        CodexProtocolError,
        CodexTimeoutError,
        CodexTransportError,
        ThreadConfig,
    )
except ImportError as e:
    print(
        "[codex-app-server] codex_app_server_sdk not importable. "
        f"Run scripts/install-codex-sdk.sh first.\n  ({e})",
        file=sys.stderr,
    )
    sys.exit(1)


DEFAULT_DAEMON_PORT_FILE = os.path.expanduser("~/.codex/my-harness-daemon.port")


def log(msg: str) -> None:
    print(f"[codex-app-server] {msg}", file=sys.stderr, flush=True)


# Substrings (case-insensitive on JSON dumps) that indicate an event relates to
# image generation. We match defensively rather than against a fixed event-name
# schema because Codex's app-server protocol surfaces image-gen results under
# slightly different keys across versions (image_generation_call, image_gen,
# imageGeneration, etc.). The shell never *parses* these paths — it only
# checks file presence downstream — so a few false positives are harmless.
_IMAGE_EVENT_HINTS = ("image_generation", "imageGeneration", "image_gen")

# Regex matching common image-path shapes Codex emits when reporting a saved
# image. We accept absolute paths under ~/.codex/generated_images, /tmp,
# /var/folders (macOS temp), or any path the prompt explicitly told Codex to
# save to. Both forward-slash and backslash variants are tolerated.
_IMAGE_PATH_RE = re.compile(
    r'"(/[^"]+?\.(?:png|jpe?g|webp|gif))"',
    re.IGNORECASE,
)


def _extract_image_paths(raw_events) -> list[str]:
    """Scan raw JSON-RPC events for image-generation file paths.

    Used to decide whether an image-only turn (final_text empty) is a success
    rather than a no-output failure. We do NOT depend on a specific event
    name — we serialize each event to JSON, check for an image-related hint,
    and pull any *.png/*.jpg/*.webp/*.gif path out of the string. Duplicates
    are de-duped while preserving first-seen order.
    """
    found: list[str] = []
    seen: set[str] = set()
    for ev in raw_events or []:
        try:
            blob = json.dumps(ev, ensure_ascii=False)
        except (TypeError, ValueError):
            continue
        blob_lower = blob.lower()
        if not any(h.lower() in blob_lower for h in _IMAGE_EVENT_HINTS):
            continue
        for m in _IMAGE_PATH_RE.finditer(blob):
            path = m.group(1)
            if path not in seen:
                seen.add(path)
                found.append(path)
    return found


def detect_daemon_port() -> Optional[int]:
    """Return the daemon's loopback port, or None if no live daemon is found.

    Order:
      1. $MY_HARNESS_CODEX_DAEMON_PORT (explicit override)
      2. ~/.codex/my-harness-daemon.port (file written by codex-daemon.sh)

    The probe binds to nothing — we just check that the file exists, parses
    as int, and the port answers a TCP connect on 127.0.0.1.
    """
    candidates: list[int] = []
    env_port = os.environ.get("MY_HARNESS_CODEX_DAEMON_PORT")
    if env_port:
        try:
            candidates.append(int(env_port))
        except ValueError:
            log(f"$MY_HARNESS_CODEX_DAEMON_PORT={env_port!r} is not an int; ignoring")
    try:
        with open(DEFAULT_DAEMON_PORT_FILE) as f:
            candidates.append(int(f.read().strip()))
    except (OSError, ValueError):
        pass

    for port in candidates:
        if not (1 <= port <= 65535):
            continue
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return port
        except OSError:
            continue
    return None


def resolve_thread_id(thread_id_file: str) -> Optional[str]:
    if not thread_id_file:
        return None
    p = Path(thread_id_file)
    if not p.is_file():
        return None
    stored = p.read_text().strip()
    return stored or None


def persist_thread_id(thread_id_file: str, thread_id: str) -> None:
    if not thread_id_file:
        return
    p = Path(thread_id_file)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(thread_id)
    log(f"thread id saved to {p}")


def build_stdio_command(disabled_plugins: list[str]) -> list[str]:
    """Build the argv for connect_stdio() spawn — `codex app-server` plus
    any per-call plugin disables passed as `-c plugins."<id>".enabled=false`."""
    cmd = ["codex", "app-server"]
    for pid in disabled_plugins:
        pid = pid.strip()
        if not pid:
            continue
        cmd.extend(["-c", f'plugins."{pid}".enabled=false'])
    cmd.extend(["--listen", "stdio://"])
    return cmd


async def run_async(args: argparse.Namespace) -> int:
    prompt_path = Path(args.prompt_file)
    if not prompt_path.is_file():
        log(f"prompt file not found: {prompt_path}")
        return 2
    prompt_text = prompt_path.read_text()

    cwd_abs = os.path.abspath(args.cwd)

    # Resolve disabled plugins (env default + repeatable flag, deduped, ordered)
    disabled_plugins: list[str] = []
    for source in (
        os.environ.get("MY_HARNESS_CODEX_DISABLE_PLUGINS", "").split(","),
        args.disable_plugin or [],
    ):
        for raw in source:
            pid = raw.strip()
            if pid and pid not in disabled_plugins:
                disabled_plugins.append(pid)

    # Choose transport. WebSocket daemon is preferred but only when the
    # configured port is actually accepting connections — otherwise fall
    # back to stdio so a stale port file does not break the call.
    daemon_port: Optional[int] = None
    if not args.no_daemon:
        if args.daemon_port:
            try:
                with socket.create_connection(("127.0.0.1", args.daemon_port), timeout=0.5):
                    daemon_port = args.daemon_port
            except OSError:
                log(f"--daemon-port {args.daemon_port} not reachable; using stdio")
        else:
            daemon_port = detect_daemon_port()

    if daemon_port:
        if disabled_plugins:
            log(
                "note: --disable-plugin is ignored in daemon mode "
                "(plugin set is fixed at daemon start)"
            )
        log(f"connecting to daemon ws://127.0.0.1:{daemon_port}")
        client_ctx = CodexClient.connect_websocket(
            url=f"ws://127.0.0.1:{daemon_port}",
            connect_timeout=10.0,
            request_timeout=30.0,
            inactivity_timeout=args.turn_timeout + 30.0,
        )
        mode = f"ws({daemon_port})"
    else:
        cmd = build_stdio_command(disabled_plugins)
        log(f"spawning stdio: {' '.join(cmd)}")
        client_ctx = CodexClient.connect_stdio(
            command=cmd,
            connect_timeout=30.0,
            request_timeout=30.0,
            inactivity_timeout=args.turn_timeout + 30.0,
        )
        mode = "stdio" + (f" [-{len(disabled_plugins)} plugins]" if disabled_plugins else "")

    log(f"mode={mode}")

    # Optional event log: capture every ConversationStep raw event.
    log_fp = None
    if args.log_file:
        Path(args.log_file).parent.mkdir(parents=True, exist_ok=True)
        log_fp = open(args.log_file, "w", encoding="utf-8")

    try:
        async with client_ctx as client:
            # ---- thread/start or thread/resume ----
            stored_thread_id = resolve_thread_id(args.thread_id_file)
            # Bypass approvals + sandbox by default — the harness only ever
            # invokes Codex from Claude Code, where Claude has already taken
            # responsibility for review. Asking for approvals here would just
            # hang the lane on every shell command. Equivalent to running
            # `codex exec --dangerously-bypass-approvals-and-sandbox`.
            # Override with --no-bypass for paranoid runs.
            cfg = ThreadConfig(
                cwd=cwd_abs,
                model=args.model or None,
                approval_policy=None if args.no_bypass else "never",
                sandbox=None if args.no_bypass else "danger-full-access",
            )

            if stored_thread_id:
                log(f"resuming thread {stored_thread_id}")
                try:
                    handle = await client.resume_thread(stored_thread_id, overrides=cfg)
                except (CodexProtocolError, CodexTransportError) as e:
                    log(f"resume failed ({type(e).__name__}: {e}); starting fresh thread")
                    handle = await client.start_thread(config=cfg)
            else:
                log("starting new thread")
                handle = await client.start_thread(config=cfg)

            persist_thread_id(args.thread_id_file, handle.thread_id)

            # ---- run turn via streaming chat() ----
            #
            # We use `handle.chat()` (AsyncIterator[ConversationStep]) instead
            # of `chat_once()` because chat_once raises CodexProtocolError
            # whenever final_text is empty — and Codex legitimately ends turns
            # with empty text every time it only calls image_gen (the entire
            # Phase-5 image-generation flow). The streaming variant returns
            # cleanly on session.completed regardless of text content, letting
            # us classify the turn ourselves: text-only / image-only / mixed
            # are all success; only true failures (turn/failed, timeout,
            # transport) get propagated.
            #
            # ConversationStep schema:
            #   step_type: canonical UI label
            #   item_type: raw protocol item (agentMessage / reasoning /
            #              commandExecution / image_generation_call / ...)
            #   text:      human-readable text when available
            #   data:      full item payload (image paths live here)
            text_parts: list[str] = []
            event_dicts: list[dict[str, Any]] = []

            try:
                async for step in handle.chat(
                    prompt_text,
                    inactivity_timeout=args.turn_timeout,
                ):
                    # Capture serialized form once — used for log file + image
                    # detection scan.
                    event_dicts.append(step.model_dump(mode="json"))

                    # Aggregate ONLY agent_message text — never reasoning or
                    # command-execution output, which would confuse the shell
                    # caller's downstream pipeline.
                    if step.item_type == "agentMessage" and step.text:
                        text_parts.append(step.text)
            except CodexTimeoutError as e:
                log(f"turn timed out: {e}")
                return 1
            except CodexProtocolError as e:
                # session.failed → real failure from Codex. Surface and exit.
                log(f"turn failed: {e}")
                return 1

            if log_fp is not None:
                for ev in event_dicts:
                    log_fp.write(json.dumps(ev, ensure_ascii=False) + "\n")

            # ---- classify + emit ----
            text = "\n".join(text_parts).rstrip("\n")
            images = _extract_image_paths(event_dicts)

            if not text and not images:
                log("turn ended with no agent_message and no image_generation_call — treating as failure")
                return 1

            if images:
                log(f"detected {len(images)} image_generation_call event(s); "
                    f"text_len={len(text)}")
                # Image paths surface on stderr only; stdout stays "assistant text"
                # so the shell caller's downstream contract is unchanged.
                for p in images:
                    log(f"  image: {p}")

            sys.stdout.write(text + "\n")
            sys.stdout.flush()
            return 0

    except CodexTransportError as e:
        log(f"transport error: {e}")
        return 1
    except CodexProtocolError as e:
        log(f"protocol error: {e}")
        return 1
    finally:
        if log_fp is not None:
            log_fp.close()


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="codex-app-server-call",
        description="codex_app_server_sdk client for codex-ask.sh.",
    )
    p.add_argument("--prompt-file", required=True,
                   help="path to a file whose contents become the user prompt")
    p.add_argument("--thread-id-file", default="",
                   help="file holding the Codex thread id; read for resume, written on new thread")
    p.add_argument("--cwd", default=os.getcwd(),
                   help="working directory passed to thread/start")
    p.add_argument("--model", default="",
                   help="optional Codex model id override")
    p.add_argument("--log-file", default="",
                   help="optional path to write the full event stream as JSONL")
    p.add_argument("--turn-timeout", type=float, default=600.0,
                   help="inactivity timeout for the turn in seconds (default 600)")
    p.add_argument("--daemon-port", type=int, default=0,
                   help=("explicit daemon loopback port. Default: auto-detect via "
                         "$MY_HARNESS_CODEX_DAEMON_PORT then ~/.codex/my-harness-daemon.port"))
    p.add_argument("--no-daemon", action="store_true",
                   help="force stdio mode even if a daemon is running")
    p.add_argument("--no-bypass", action="store_true",
                   help=("disable the default approval/sandbox bypass. By default the "
                         "harness sets approval_policy=never and sandbox=danger-full-access "
                         "so Codex never blocks on a confirmation prompt — Claude Code is the "
                         "outer review boundary. Use this flag to fall back to Codex's normal "
                         "approval flow (requires a human at the keyboard)."))
    p.add_argument("--disable-plugin", action="append", default=[],
                   metavar="PLUGIN_ID",
                   help=("disable a Codex plugin for this call only (repeatable, stdio mode "
                         "only — daemon mode uses the daemon's plugin set). PLUGIN_ID matches "
                         "the [plugins.\"<id>\"] key in ~/.codex/config.toml. Default list also "
                         "comes from $MY_HARNESS_CODEX_DISABLE_PLUGINS (comma-separated)."))
    return p.parse_args()


def main() -> int:
    args = parse_args()
    return asyncio.run(run_async(args))


if __name__ == "__main__":
    sys.exit(main())
