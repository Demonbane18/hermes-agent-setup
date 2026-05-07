#!/bin/bash
# =============================================================================
# Hermes Multi-Gateway Startup Script
# =============================================================================
# Runs N isolated Telegram-bot gateway processes from a single command.
# Each subdirectory of this folder containing a `.env` is a gateway.
# This file lives in production at ~/gateways/run.sh inside the Hermes
# Docker container (or on bare metal if you skipped the 1-click).
#
# Usage:
#   ./run.sh              Start every discovered gateway (alias: `all`, `both`)
#   ./run.sh work         Start the "work" gateway only (foreground)
#   ./run.sh personal     Start the "personal" gateway only (foreground)
#   ./run.sh status       Check what's running
#   ./run.sh stop         Stop every gateway
#   ./run.sh list         Print discovered gateway names
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_BIN="${HERMES_BIN:-hermes}"
STAGGER_SECONDS="${HERMES_GATEWAY_STAGGER:-2}"

# Discover every subdirectory that has a `.env` (the marker for "this is a gateway").
discover_gateways() {
    for d in "$SCRIPT_DIR"/*/; do
        [ -f "$d/.env" ] && basename "$d"
    done
}

# Source .env, inject token into config.yaml, exec hermes gateway run.
# Runs in a subshell so per-gateway env vars never leak across gateways.
inject_and_run() {
    local GW_DIR="$1"
    local GW_PATH="$SCRIPT_DIR/$GW_DIR"

    # Run everything in a subshell so env vars don't leak
    (
        export HERMES_HOME="$GW_PATH"
        export HERMES_EPHEMERAL_SYSTEM_PROMPT=""

        if [ -f "$GW_PATH/.env" ]; then
            set -a
            source "$GW_PATH/.env"
            set +a
        fi

        # Sanity check the token before injection
        if [ -z "$HERMES_TELEGRAM_BOT_TOKEN" ]; then
            echo "[$GW_DIR] ERROR: HERMES_TELEGRAM_BOT_TOKEN not set"
            exit 1
        fi
        echo "[$GW_DIR] Token length: ${#HERMES_TELEGRAM_BOT_TOKEN}"

        python3 "$SCRIPT_DIR/inject_config.py"

        echo "[$GW_DIR] Starting Hermes Gateway..."
        echo "[$GW_DIR] Sessions: $HERMES_HOME/sessions"

        cd "$GW_PATH"
        exec $HERMES_BIN gateway run
    )
}

CMD="${1:-all}"
case "$CMD" in
    all|both)
        first=true
        for gw in $(discover_gateways); do
            [ "$first" = true ] || sleep "$STAGGER_SECONDS"
            first=false
            inject_and_run "$gw" &
        done
        echo ""
        echo "=========================================="
        echo "Hermes Multi-Gateway running!"
        echo "Press Ctrl+C to stop all"
        echo "=========================================="
        wait
        ;;
    list)
        discover_gateways
        ;;
    stop)
        echo "Stopping all Hermes gateways..."
        pkill -f "hermes gateway run" 2>/dev/null || true
        find "$SCRIPT_DIR" -maxdepth 2 -name 'gateway.pid' -delete 2>/dev/null || true
        echo "Done."
        ;;
    status)
        if pgrep -f "hermes gateway run" > /dev/null; then
            echo "✓ Hermes gateways are RUNNING"
            pgrep -af "hermes gateway run"
        else
            echo "✗ No Hermes gateways running"
        fi
        ;;
    *)
        # Treat as a gateway name (e.g., `./run.sh work`)
        inject_and_run "$CMD"
        ;;
esac
