#!/usr/bin/env bash
# =============================================================================
# Hermes Multi-Gateway Bootstrap
# =============================================================================
# One-command setup for N Telegram-bot gateways with one of three sharing
# strategies. Works for fresh installs (Mode A), extending an existing setup
# (Mode B), and non-interactive automation (Mode C — flag-driven).
#
# Quick start (interactive):
#   curl -fsSL https://raw.githubusercontent.com/Demonbane18/hermes-agent-setup/main/bootstrap.sh | bash
#
# Or from a clone:
#   ./bootstrap.sh
#
# Non-interactive examples:
#   ./bootstrap.sh --parent ~/gateways --count 3 --names alpha,beta,gamma --strategy isolated
#   ./bootstrap.sh --add --parent ~/gateways --names delta,epsilon
#
# See --help for the full flag list.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Version
# -----------------------------------------------------------------------------
# Bump on every meaningful change so users running `curl ... | bash` can see
# whether their copy matches the latest.
BOOTSTRAP_VERSION="0.4.0"
BOOTSTRAP_RELEASED="2026-05-08"

# -----------------------------------------------------------------------------
# Globals
# -----------------------------------------------------------------------------
SCRIPT_NAME="${0##*/}"
SCRIPT_PATH=""
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
fi

DEFAULT_REPO_URL="https://raw.githubusercontent.com/Demonbane18/hermes-agent-setup/main"
REPO_URL="${HERMES_BOOTSTRAP_REPO_URL:-$DEFAULT_REPO_URL}"

PARENT=""
COUNT=""
NAMES_RAW=""
STRATEGY=""
MODE=""                 # "" | "fresh" | "add"
DRY_RUN=0
NON_INTERACTIVE=0
EXTRA_SCAN_PATHS=()
CREATE_SOUL=0

# Provider selection (defaults match the templates: xiaomi-mimo primary,
# openrouter fallback). Override interactively or via --provider/--model/etc.
PROVIDER=""             # e.g. xiaomi-mimo, anthropic, openai, gemini, openrouter,
                        #      groq, deepseek, minimax, zai, ollama, custom
MODEL=""                # default model id for the primary provider
BASE_URL=""             # only for OpenAI-compatible custom providers
KEY_ENV=""              # env var name holding the API key (e.g. ANTHROPIC_API_KEY)
FALLBACK_PROVIDER=""    # fallback provider name; set to "none" or empty to skip
FALLBACK_MODEL=""

# Logged operations (so a final summary works even in --dry-run)
OPS=()

trap 'echo "[bootstrap] error on line $LINENO" >&2' ERR

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
log()    { echo "[bootstrap] $*"; }
warn()   { echo "[bootstrap] WARN: $*" >&2; }
die()    { echo "[bootstrap] FATAL: $*" >&2; exit 1; }
op()     { OPS+=("$1"); if [ "$DRY_RUN" = 1 ]; then echo "[dry-run] $1"; else echo "[do] $1"; fi; }

usage() {
    cat <<'EOF'
hermes-agent-setup bootstrap.sh — N-gateway Hermes setup

USAGE
  bootstrap.sh [flags]

INTERACTIVE
  Run with no flags. The script scans your $HOME, /root, /home/* for an
  existing Hermes parent folder. If one is found you'll be offered to extend
  it (Mode B); otherwise you'll be walked through a fresh setup (Mode A).

FLAGS
  --parent PATH               Parent folder for gateways (default: ~/gateways)
  --count N                   Number of gateways (fresh setup only)
  --names a,b,c               Comma-separated gateway names (overrides --count)
  --strategy STRATEGY         isolated | shared-skills | shared-both
                              Aliases: none|skills|both|all
                              Default: isolated (fresh) or auto-detected (--add)
  --provider NAME             LLM provider for the default model.
                              Built-in: xiaomi-mimo (default), openrouter,
                              anthropic, openai, gemini.
                              Custom OpenAI-compatible: groq, deepseek,
                              minimax, zai, ollama, custom.
  --model ID                  Model ID for the primary provider. Defaults per
                              provider (e.g. mimo-v2.5-pro, claude-sonnet-4-6,
                              gpt-4o, gemini-2.5-pro).
  --base-url URL              Override the provider base URL (mostly for
                              region-specific MiMo endpoints or custom
                              providers).
  --key-env VAR               Override the env var name that holds the API key
                              (default per provider, e.g. ANTHROPIC_API_KEY).
  --fallback-provider NAME    Fallback provider (default: openrouter unless
                              primary is openrouter; pass 'none' to skip).
  --fallback-model ID         Fallback model id (default per provider).
  --no-fallback               Shortcut for --fallback-provider none.
  --add                       Force Mode B (extend existing setup)
  --soul                      Also create a SOUL.md scaffold per gateway
  --scan-path PATH            Additional path to scan for existing setups
                              (repeatable)
  --repo-url URL              Base URL for fetching run.sh / inject_config.py
                              when no local templates/ directory exists
                              (default: $HERMES_BOOTSTRAP_REPO_URL or the
                              Demonbane18/hermes-agent-setup main branch)
  --dry-run                   Print every action without executing
  --non-interactive           Fail loudly on missing required values instead
                              of prompting
  -V, --version               Print bootstrap version and exit
  -h, --help                  This help

STRATEGIES
  isolated        Each gateway has its own memories/ and skills/. Default.
                  Maximum context separation. No _shared/ folder created.
  shared-skills   Each gateway has its own memories/. skills/ symlinked to
                  <parent>/_shared/skills/. Useful for separate personas
                  sharing one tool library.
  shared-both     memories/ AND skills/ symlinked to <parent>/_shared/.
                  Multiple Telegram front-ends to the same logical agent.

PROVIDERS (hard-coded model lists; check provider for newest)
  xiaomi-mimo  mimo-v2.5-pro, mimo-v2-flash
               base_url: https://token-plan-{sgp,ams,cn}.xiaomimimo.com/v1
               key_env: XIAOMI_MIMO_API_KEY
  openrouter   anthropic/claude-sonnet-4, openai/gpt-4o, google/gemini-2.5-pro
               (built-in provider, no base_url)
               key_env: OPENROUTER_API_KEY
  anthropic    claude-opus-4-7, claude-sonnet-4-6, claude-haiku-4-5
               (built-in)  key_env: ANTHROPIC_API_KEY
  openai       gpt-4o, gpt-4o-mini, o1, o3-mini
               (built-in)  key_env: OPENAI_API_KEY
  gemini       gemini-2.5-pro, gemini-2.5-flash
               (built-in)  key_env: GEMINI_API_KEY
  groq         llama-3.3-70b-versatile, mixtral-8x7b-32768
               base_url: https://api.groq.com/openai/v1
               key_env: GROQ_API_KEY
  deepseek     deepseek-chat, deepseek-reasoner
               base_url: https://api.deepseek.com/v1
               key_env: DEEPSEEK_API_KEY
  minimax      minimax-m2.7
               base_url: https://api.minimax.chat/v1
               key_env: MINIMAX_API_KEY
  zai          glm-4-plus, glm-4-flash
               base_url: https://open.bigmodel.cn/api/paas/v4
               key_env: ZAI_API_KEY
  ollama       llama3.1:8b, qwen2.5:14b, deepseek-r1:14b (local, no key)
               base_url: http://localhost:11434/v1
  custom       provide --model, --base-url, --key-env yourself

NAME RULES
  Gateway names match ^[A-Za-z0-9][A-Za-z0-9_-]*$. No leading dot or
  underscore (those clash with _shared/ and dotfiles).

SAFETY
  Never overwrites existing .env or config.yaml.
  Backs up run.sh / inject_config.py to .bak exactly once when replacing
  with a non-matching universal template.

EXAMPLES
  # Fresh setup with the defaults — xiaomi-mimo + openrouter fallback
  bootstrap.sh --parent ~/gateways --count 3 --names alpha,beta,gamma \\
      --strategy isolated

  # Anthropic primary, OpenRouter fallback
  bootstrap.sh --parent ~/agents --count 1 --names assistant \\
      --strategy isolated --provider anthropic --model claude-opus-4-7 \\
      --non-interactive

  # OpenAI primary, no fallback
  bootstrap.sh --parent ~/bots --count 2 --names work,personal \\
      --strategy shared-both --provider openai --model gpt-4o \\
      --no-fallback --non-interactive

  # Local Ollama, no API keys at all
  bootstrap.sh --parent ~/local-bots --count 1 --names dev \\
      --strategy isolated --provider ollama --model llama3.1:8b \\
      --no-fallback --non-interactive

  # Custom OpenAI-compatible provider
  bootstrap.sh --parent ~/gateways --count 1 --names myagent \\
      --provider custom --model my-llm-v1 \\
      --base-url https://api.example.com/v1 --key-env EXAMPLE_API_KEY \\
      --no-fallback --non-interactive

  # Add 2 gateways to an existing parent (strategy + provider auto-inherited
  # from the existing config.yaml; pass --provider to override)
  bootstrap.sh --add --parent ~/gateways --names delta,epsilon \\
      --non-interactive

  # Curl-piped, non-interactive
  curl -fsSL .../bootstrap.sh | bash -s -- \\
      --parent ~/agents --count 2 --names work,personal \\
      --strategy shared-both --non-interactive
EOF
}

# Strategy alias normalizer
normalize_strategy() {
    case "${1:-}" in
        ""|isolated|none)         echo "isolated" ;;
        skills|shared-skills)     echo "shared-skills" ;;
        both|all|shared-both)     echo "shared-both" ;;
        *) die "unknown strategy: $1 (use isolated|shared-skills|shared-both)" ;;
    esac
}

validate_name() {
    local n="$1"
    if ! [[ "$n" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
        die "invalid gateway name: '$n' (must match ^[A-Za-z0-9][A-Za-z0-9_-]*$)"
    fi
    if [[ "$n" == _* ]]; then
        die "gateway name '$n' starts with underscore (reserved for _shared/)"
    fi
    if [[ "$n" == .* ]]; then
        die "gateway name '$n' starts with dot (reserved for dotfiles)"
    fi
    return 0
}

# When the script is piped (`curl ... | bash`), stdin is the script source —
# any plain `read` returns empty string. Read from /dev/tty instead so prompts
# still work. If /dev/tty isn't available (some CI), fall back to the script's
# own stdin and warn the user up-front.
TTY_FD=""
init_tty() {
    if [ -t 0 ]; then
        TTY_FD="0"               # stdin is already a tty
    elif [ -r /dev/tty ] && [ -w /dev/tty ]; then
        TTY_FD="tty"             # use /dev/tty directly
    else
        TTY_FD=""                # no interactive input possible
    fi
}

read_tty() {
    # Args: <prompt-msg>; sets REPLY
    local msg="$1"
    if [ "$TTY_FD" = "0" ]; then
        read -r -p "$msg" REPLY
    elif [ "$TTY_FD" = "tty" ]; then
        read -r -p "$msg" REPLY </dev/tty
    else
        die "no interactive terminal available (stdin is piped, /dev/tty unreachable). Re-run with --non-interactive plus --parent/--count/--names/--strategy, or download the script first: curl -fsSL .../bootstrap.sh -o bootstrap.sh && bash bootstrap.sh"
    fi
}

prompt() {
    local msg="$1" default="${2:-}"
    if [ "$NON_INTERACTIVE" = 1 ]; then
        die "missing required value: $msg (running --non-interactive)"
    fi
    local label
    if [ -n "$default" ]; then
        label="$msg [$default]: "
    else
        label="$msg: "
    fi
    read_tty "$label"
    echo "${REPLY:-$default}"
}

confirm() {
    local msg="$1" default="${2:-Y}"
    if [ "$NON_INTERACTIVE" = 1 ]; then
        echo "$default"
        return
    fi
    read_tty "$msg [$default]: "
    echo "${REPLY:-$default}"
}

# yes_no — returns 0 for yes, 1 for no. Default Y shows `[Y/n]`,
# default N shows `[y/N]`. Empty input = default.
yes_no() {
    local msg="$1" default="${2:-Y}"
    local label
    case "$default" in
        Y|y) label="$msg [Y/n]: " ;;
        N|n) label="$msg [y/N]: " ;;
        *)   label="$msg [Y/n]: "; default="Y" ;;
    esac
    if [ "$NON_INTERACTIVE" = 1 ]; then
        case "$default" in Y|y) return 0 ;; *) return 1 ;; esac
    fi
    read_tty "$label"
    local reply="${REPLY:-$default}"
    [[ "$reply" =~ ^[Yy] ]]
}

# Suggest a non-colliding parent path when the user wants a fresh setup
# alongside an existing one. Picks $HOME/gateways-2, -3, … until free.
suggest_fresh_parent() {
    local existing="$1"
    local base="$HOME/gateways"
    [ "$existing" = "$base" ] || base="$HOME/gateways"
    local i=2
    local candidate="$base-$i"
    while [ -e "$candidate" ]; do
        i=$((i+1))
        candidate="$base-$i"
    done
    echo "$candidate"
}

# -----------------------------------------------------------------------------
# Provider registry
# -----------------------------------------------------------------------------
# Each entry: <default_model>|<base_url>|<key_env>|<is_builtin>
#   built-in providers are referenced as `provider: <name>` in config.yaml.
#   non-built-in providers go under `custom_providers:` with `name`/`base_url`/`key_env`.
provider_info() {
    case "$1" in
        xiaomi-mimo) echo "mimo-v2.5-pro|https://token-plan-sgp.xiaomimimo.com/v1|XIAOMI_MIMO_API_KEY|0" ;;
        openrouter)  echo "anthropic/claude-sonnet-4||OPENROUTER_API_KEY|1" ;;
        anthropic)   echo "claude-sonnet-4-6||ANTHROPIC_API_KEY|1" ;;
        openai)      echo "gpt-4o||OPENAI_API_KEY|1" ;;
        gemini)      echo "gemini-2.5-pro||GEMINI_API_KEY|1" ;;
        groq)        echo "llama-3.3-70b-versatile|https://api.groq.com/openai/v1|GROQ_API_KEY|0" ;;
        deepseek)    echo "deepseek-chat|https://api.deepseek.com/v1|DEEPSEEK_API_KEY|0" ;;
        minimax)     echo "minimax-m2.7|https://api.minimax.chat/v1|MINIMAX_API_KEY|0" ;;
        zai)         echo "glm-4-plus|https://open.bigmodel.cn/api/paas/v4|ZAI_API_KEY|0" ;;
        ollama)      echo "llama3.1:8b|http://localhost:11434/v1||0" ;;
        custom)      echo "|||0" ;;
        *) return 1 ;;
    esac
}

# Hard-coded model catalog. As-of bootstrap-script date — providers add and
# deprecate models constantly. Hit the provider's /v1/models endpoint for the
# live list, then edit config.yaml manually.
provider_models() {
    case "$1" in
        xiaomi-mimo) echo "mimo-v2.5-pro mimo-v2-flash" ;;
        openrouter)  echo "anthropic/claude-sonnet-4 anthropic/claude-opus-4 minimax/minimax-m2.7 openai/gpt-4o google/gemini-2.5-pro meta-llama/llama-3.3-70b-instruct deepseek/deepseek-chat" ;;
        anthropic)   echo "claude-opus-4-7 claude-sonnet-4-6 claude-haiku-4-5" ;;
        openai)      echo "gpt-4o gpt-4o-mini o1 o3-mini" ;;
        gemini)      echo "gemini-2.5-pro gemini-2.5-flash" ;;
        groq)        echo "llama-3.3-70b-versatile mixtral-8x7b-32768 llama-3.1-8b-instant" ;;
        deepseek)    echo "deepseek-chat deepseek-reasoner" ;;
        minimax)     echo "minimax-m2.7" ;;
        zai)         echo "glm-4-plus glm-4-flash" ;;
        ollama)      echo "llama3.1:8b qwen2.5:14b deepseek-r1:14b mistral:7b" ;;
        *) echo "" ;;
    esac
}

provider_is_builtin() {
    case "$1" in
        anthropic|openai|openrouter|gemini) return 0 ;;
        *) return 1 ;;
    esac
}

yaml_provider_ref() {
    if provider_is_builtin "$1"; then echo "$1"; else echo "custom:$1"; fi
}

# Resolve PROVIDER, MODEL, BASE_URL, KEY_ENV, FALLBACK_PROVIDER, FALLBACK_MODEL.
# Honours flags first, prompts only for what's missing in interactive mode.
prompt_provider() {
    # Default in non-interactive mode if still unset.
    if [ -z "$PROVIDER" ]; then
        if [ "$NON_INTERACTIVE" = 1 ]; then
            PROVIDER="xiaomi-mimo"
        else
            cat <<'EOF'

Default LLM provider for these gateways:

   1) xiaomi-mimo  (default — Token Plan / Orbit, free tokens via Orbit program)
   2) openrouter             (multi-model gateway, sk-or-v1-...)
   3) anthropic              (Claude API)
   4) openai                 (OpenAI API)
   5) gemini                 (Google Gemini)
   6) groq                   (fast Llama / Mixtral)
   7) deepseek               (DeepSeek chat & reasoner)
   8) minimax                (MiniMax)
   9) zai                    (Z.AI / GLM)
  10) ollama                 (local Ollama, no API key)
  11) custom                 (you supply name + base_url + key_env)

EOF
            local sel; sel="$(prompt "Pick 1-11" "1")"
            case "$sel" in
                1|xiaomi-mimo) PROVIDER="xiaomi-mimo" ;;
                2|openrouter)  PROVIDER="openrouter" ;;
                3|anthropic)   PROVIDER="anthropic" ;;
                4|openai)      PROVIDER="openai" ;;
                5|gemini)      PROVIDER="gemini" ;;
                6|groq)        PROVIDER="groq" ;;
                7|deepseek)    PROVIDER="deepseek" ;;
                8|minimax)     PROVIDER="minimax" ;;
                9|zai)         PROVIDER="zai" ;;
                10|ollama)     PROVIDER="ollama" ;;
                11|custom)     PROVIDER="custom" ;;
                *) die "invalid pick: $sel" ;;
            esac
        fi
    fi

    # Custom provider — gather everything from the user (or flags).
    if [ "$PROVIDER" = "custom" ]; then
        if [ "$NON_INTERACTIVE" = 1 ]; then
            [ -n "$MODEL" ] && [ -n "$BASE_URL" ] && [ -n "$KEY_ENV" ] \
                || die "--provider custom requires --model, --base-url, --key-env"
        fi
        local cname=""
        if [ "$NON_INTERACTIVE" = 0 ]; then
            cname="$(prompt "Provider short name (a-z0-9-)" "myprovider")"
        else
            cname="${HERMES_CUSTOM_PROVIDER_NAME:-myprovider}"
        fi
        [[ "$cname" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die "invalid custom provider name: $cname"
        [ -z "$MODEL" ]    && MODEL="$(prompt "Default model id" "")"
        [ -z "$BASE_URL" ] && BASE_URL="$(prompt "Base URL (OpenAI-compatible /v1)" "")"
        [ -z "$KEY_ENV" ]  && KEY_ENV="$(prompt "Env var name for API key" "MY_API_KEY")"
        PROVIDER="$cname"
    else
        local info; info="$(provider_info "$PROVIDER")" \
            || die "unknown provider: $PROVIDER (see --help)"
        local def_model def_url def_key _builtin
        IFS='|' read -r def_model def_url def_key _builtin <<<"$info"

        # Model
        if [ -z "$MODEL" ]; then
            if [ "$NON_INTERACTIVE" = 1 ]; then
                MODEL="$def_model"
            else
                local models; models="$(provider_models "$PROVIDER")"
                if [ -n "$models" ]; then
                    echo
                    echo "Models for $PROVIDER (hard-coded list — check the provider's /v1/models for newest):"
                    local i=1 m
                    for m in $models; do printf "  %2d) %s\n" "$i" "$m"; i=$((i+1)); done
                    printf "  %2d) (type your own)\n" "$i"
                    local sel; sel="$(prompt "Pick (default 1)" "1")"
                    if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
                        MODEL="$(echo "$models" | awk -v n="$sel" '{print $n}')"
                    else
                        MODEL="$(prompt "Type model id" "$def_model")"
                    fi
                else
                    MODEL="$def_model"
                fi
            fi
        fi

        # Base URL (skip for built-in providers — they don't need one)
        if [ -z "$BASE_URL" ]; then
            BASE_URL="$def_url"
            # Xiaomi MiMo region picker
            if [ "$PROVIDER" = "xiaomi-mimo" ] && [ "$NON_INTERACTIVE" = 0 ]; then
                echo
                echo "Xiaomi MiMo region (must match your dashboard's dedicated URL):"
                echo "   1) Singapore (sgp) [default]"
                echo "   2) Amsterdam (ams)"
                echo "   3) China (cn)"
                local r; r="$(prompt "Pick" "1")"
                case "$r" in
                    2) BASE_URL="https://token-plan-ams.xiaomimimo.com/v1" ;;
                    3) BASE_URL="https://token-plan-cn.xiaomimimo.com/v1" ;;
                    *) BASE_URL="https://token-plan-sgp.xiaomimimo.com/v1" ;;
                esac
            fi
        fi

        # Key env var
        [ -z "$KEY_ENV" ] && KEY_ENV="$def_key"
    fi

    # Fallback provider
    if [ -z "$FALLBACK_PROVIDER" ]; then
        if [ "$NON_INTERACTIVE" = 1 ]; then
            # Sensible default: openrouter unless the primary IS openrouter
            if [ "$PROVIDER" = "openrouter" ]; then
                FALLBACK_PROVIDER="none"
            else
                FALLBACK_PROVIDER="openrouter"
            fi
        else
            local default_fb="openrouter"
            [ "$PROVIDER" = "openrouter" ] && default_fb="none"
            local fb; fb="$(prompt "Fallback provider (or 'none')" "$default_fb")"
            FALLBACK_PROVIDER="${fb:-none}"
        fi
    fi

    if [ "$FALLBACK_PROVIDER" != "none" ] && [ -n "$FALLBACK_PROVIDER" ]; then
        if [ -z "$FALLBACK_MODEL" ]; then
            local fb_info; fb_info="$(provider_info "$FALLBACK_PROVIDER" 2>/dev/null)" \
                || die "unknown fallback provider: $FALLBACK_PROVIDER"
            local fb_def_model
            IFS='|' read -r fb_def_model _ _ _ <<<"$fb_info"
            # Sensible default if the registry has none (e.g. openrouter)
            [ -z "$fb_def_model" ] && [ "$FALLBACK_PROVIDER" = "openrouter" ] && fb_def_model="anthropic/claude-sonnet-4"

            if [ "$NON_INTERACTIVE" = 1 ]; then
                FALLBACK_MODEL="${fb_def_model:-$MODEL}"
            else
                local fb_models; fb_models="$(provider_models "$FALLBACK_PROVIDER")"
                if [ -n "$fb_models" ]; then
                    echo
                    echo "Fallback models for $FALLBACK_PROVIDER:"
                    local i=1 m
                    for m in $fb_models; do printf "  %2d) %s\n" "$i" "$m"; i=$((i+1)); done
                    printf "  %2d) (type your own)\n" "$i"
                    local sel; sel="$(prompt "Pick fallback model (default 1)" "1")"
                    if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
                        FALLBACK_MODEL="$(echo "$fb_models" | awk -v n="$sel" '{print $n}')"
                    else
                        FALLBACK_MODEL="$(prompt "Type fallback model id" "${fb_def_model:-$MODEL}")"
                    fi
                else
                    FALLBACK_MODEL="$(prompt "Fallback model id" "${fb_def_model:-$MODEL}")"
                fi
            fi
        fi
    fi

    log "Provider: primary=$PROVIDER model=$MODEL${BASE_URL:+ base=$BASE_URL}${KEY_ENV:+ key=$KEY_ENV}"
    if [ "$FALLBACK_PROVIDER" != "none" ] && [ -n "$FALLBACK_PROVIDER" ]; then
        log "Provider: fallback=$FALLBACK_PROVIDER model=$FALLBACK_MODEL"
    else
        log "Provider: no fallback"
    fi
}

# -----------------------------------------------------------------------------
# Generate config.yaml content for the chosen provider(s).
# Always writes a complete config.yaml — independent of templates/ — so the
# provider section is in sync with the .env keys.
# -----------------------------------------------------------------------------
generate_config_yaml() {
    local out="$1"
    {
        cat <<EOF
# =============================================================================
# Hermes Gateway config — generated by bootstrap.sh
# =============================================================================
# Safe to commit. The Telegram bot token gets injected into
# platforms.telegram.token at startup by inject_config.py — DO NOT paste
# tokens here directly.
#
# To swap providers / models manually: edit the model + custom_providers
# blocks below. See README §"LLM Provider Reference" for the supported
# provider list, base URLs, and example model IDs.
# =============================================================================

model:
  default: $MODEL
  provider: $(yaml_provider_ref "$PROVIDER")
  api_mode: chat_completions
EOF

        if [ "$FALLBACK_PROVIDER" != "none" ] && [ -n "$FALLBACK_PROVIDER" ]; then
            cat <<EOF
  fallback_providers:
    - provider: $(yaml_provider_ref "$FALLBACK_PROVIDER")
      model: $FALLBACK_MODEL
EOF
        fi

        # custom_providers block — only emitted when at least one of the
        # primary/fallback is non-built-in.
        local need_custom=0
        provider_is_builtin "$PROVIDER" || need_custom=1
        if [ "$FALLBACK_PROVIDER" != "none" ] && [ -n "$FALLBACK_PROVIDER" ] \
            && [ "$FALLBACK_PROVIDER" != "$PROVIDER" ] \
            && ! provider_is_builtin "$FALLBACK_PROVIDER"; then
            need_custom=1
        fi

        echo
        if [ "$need_custom" = 1 ]; then
            echo "custom_providers:"
            if ! provider_is_builtin "$PROVIDER"; then
                cat <<EOF
  - name: $PROVIDER
    base_url: $BASE_URL
EOF
                if [ -n "$KEY_ENV" ]; then
                    echo "    key_env: $KEY_ENV"
                fi
            fi
            if [ "$FALLBACK_PROVIDER" != "none" ] && [ -n "$FALLBACK_PROVIDER" ] \
                && [ "$FALLBACK_PROVIDER" != "$PROVIDER" ] \
                && ! provider_is_builtin "$FALLBACK_PROVIDER"; then
                local fb_info fb_url fb_key
                fb_info="$(provider_info "$FALLBACK_PROVIDER")"
                IFS='|' read -r _ fb_url fb_key _ <<<"$fb_info"
                cat <<EOF
  - name: $FALLBACK_PROVIDER
    base_url: $fb_url
    key_env: $fb_key
EOF
            fi
        fi

        # providers block — built-in providers may be configured here.
        echo
        echo "providers: {}"

        # Auxiliary tasks (compression + title generation) — route to the
        # primary provider's model so the context window matches.
        cat <<EOF

auxiliary:
  compression:
    provider: $(yaml_provider_ref "$PROVIDER")
    model: $MODEL
  title_generation:
    provider: $(yaml_provider_ref "$PROVIDER")
    model: $MODEL
EOF

        # Standard rest-of-config (matches templates/config.yaml.template).
        cat <<'EOF'

agent:
  max_turns: 90
  gateway_timeout: 1800 # 30 minutes per turn
  restart_drain_timeout: 60
  service_tier: ''
  tool_use_enforcement: auto
  gateway_timeout_warning: 900
  gateway_notify_interval: 600
  verbose: false
  reasoning_effort: medium
  system_prompt: '' # leave empty — HERMES_EPHEMERAL_SYSTEM_PROMPT in .env wins

platforms:
  telegram:
    enabled: true
    token: '' # injected by inject_config.py at startup
    extra:
      require_pairing: false

platform_toolsets:
  cli:
    - hermes-cli
  telegram:
    - hermes-telegram

sessions_dir: ./sessions

session_reset:
  mode: both
  idle_minutes: 1440 # auto-reset session after 24h idle
  at_hour: 4 # …or daily at 04:00 local time

streaming:
  enabled: false

approvals:
  mode: manual
  timeout: 60
  cron_mode: deny

command_allowlist: []
quick_commands: {}
hooks: {}
hooks_auto_accept: false

privacy:
  redact_pii: false

cron:
  wrap_response: true
  max_parallel_jobs: null

code_execution:
  mode: project
  timeout: 300
  max_tool_calls: 50

logging:
  level: INFO
  max_size_mb: 5
  backup_count: 3

network:
  force_ipv4: false

_config_version: 22
group_sessions_per_user: true

# Set this to your own Telegram chat ID if you want the bot to post home-channel
# notifications (cron summaries, errors, etc.). Leave blank to disable.
TELEGRAM_HOME_CHANNEL: ''
EOF
    } > "$out"
}

# -----------------------------------------------------------------------------
# Generate .env content with the right API-key placeholders for the chosen
# provider(s). Mirrors templates/.env.template, but swaps the provider keys.
# -----------------------------------------------------------------------------
generate_env_content() {
    local out="$1"
    {
        cat <<'EOF'
# =============================================================================
# Hermes Gateway .env — generated by bootstrap.sh
# =============================================================================
# 1. Fill in every value below before launching.
# 2. NEVER commit this file. The repo .gitignore excludes it.
# 3. Permissions are chmod 600 — Hermes refuses world-readable env files.
# =============================================================================

# --- Telegram identity --------------------------------------------------------
# From @BotFather -> /newbot -> copy the token. Each gateway needs its OWN
# token (Telegram only allows one polling process per token).
HERMES_TELEGRAM_BOT_TOKEN=***

# Comma-separated Telegram user IDs allowed to talk to this bot.
# Get yours from @userinfobot. Leave blank to allow ALL (not recommended).
TELEGRAM_ALLOWED_USERS=

# --- Operational rules (system prompt) ----------------------------------------
# Loaded by run.sh into HERMES_EPHEMERAL_SYSTEM_PROMPT at startup.
# Identity/personality goes in SOUL.md (created alongside this file by
# bootstrap when --soul flag is set). This var handles behavior, tools, and
# constraints. Edit freely — this is what makes each bot's voice different.
HERMES_EPHEMERAL_SYSTEM_PROMPT="DOMAIN:
- Replace this block with what this gateway is for.

RESPONSE FORMAT:
- Phone-screen friendly (Telegram delivery).
- Lead with the recommendation, then the reasoning.
- Use code blocks for commands, configs, and code.

TOOL USAGE:
- Use search/web tools before claiming something doesn't exist.
- Delegate to subagents for parallel research.
- Use cron jobs for scheduled automation.

CONSTRAINTS:
- If a request is ambiguous, ask one clarifying question, not five.
- Never invent API endpoints, library functions, or pricing.
- No moralizing. The user is an adult.

OUTPUT STRUCTURE:
- Default to short answers. Expand only when complexity demands it.
- Use markdown formatting: headers for sections, code blocks for commands."

# --- Model providers ----------------------------------------------------------
EOF

        if [ -n "$KEY_ENV" ]; then
            echo "# Primary: $PROVIDER ($MODEL)"
            echo "$KEY_ENV=***"
        else
            echo "# Primary: $PROVIDER ($MODEL) — no API key required (e.g. local Ollama)"
        fi

        if [ "$FALLBACK_PROVIDER" != "none" ] && [ -n "$FALLBACK_PROVIDER" ]; then
            local fb_info fb_key
            fb_info="$(provider_info "$FALLBACK_PROVIDER" 2>/dev/null || true)"
            IFS='|' read -r _ _ fb_key _ <<<"$fb_info"
            if [ -n "$fb_key" ] && [ "$fb_key" != "$KEY_ENV" ]; then
                echo
                echo "# Fallback: $FALLBACK_PROVIDER ($FALLBACK_MODEL)"
                echo "$fb_key=***"
            fi
        fi

        cat <<'EOF'

# --- Companion paths ----------------------------------------------------------
# Absolute path to your shared Obsidian vault. Same path in every gateway's
# .env (cross-bot durable knowledge layer). Leave blank to skip.
OBSIDIAN_VAULT_PATH=
EOF
    } > "$out"
}

# -----------------------------------------------------------------------------
# Template fetching
# -----------------------------------------------------------------------------
# Resolution order:
#   1. <SCRIPT_DIR>/templates/<name> (local clone)
#   2. <REPO_URL>/templates/<name>   (curl raw GitHub)
fetch_template() {
    local name="$1" dest="$2"
    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/templates/$name" ]; then
        op "cp $SCRIPT_DIR/templates/$name -> $dest"
        [ "$DRY_RUN" = 1 ] || cp "$SCRIPT_DIR/templates/$name" "$dest"
    else
        local url="$REPO_URL/templates/$name"
        op "curl $url -> $dest"
        if [ "$DRY_RUN" = 0 ]; then
            curl -fsSL "$url" -o "$dest" || die "failed to fetch $url (try --repo-url)"
        fi
    fi
}

# -----------------------------------------------------------------------------
# Discovery — find existing Hermes parent folders
# -----------------------------------------------------------------------------
find_hermes_parents() {
    local roots=("$HOME")
    [ -d "/root" ] && roots+=("/root")
    if compgen -G "/home/*" >/dev/null; then
        for h in /home/*; do roots+=("$h"); done
    fi
    for p in "${EXTRA_SCAN_PATHS[@]:-}"; do
        [ -n "$p" ] && roots+=("$p")
    done

    local seen=()
    local root runsh parent has_gateway sub name
    for root in "${roots[@]}"; do
        [ -d "$root" ] || continue
        # maxdepth 3 keeps the scan bounded (skips node_modules, vaults, etc.)
        while IFS= read -r runsh; do
            parent=$(dirname "$runsh")
            [ -f "$parent/inject_config.py" ] || continue
            # Skip parents inside repos that are NOT the live setup
            [[ "$parent" == */hermes-agent-setup/gateways ]] && continue
            has_gateway=0
            for sub in "$parent"/*/; do
                [ -d "$sub" ] || continue
                name=$(basename "$sub")
                [[ "$name" == _* ]] && continue
                [ -f "$sub/config.yaml" ] && { has_gateway=1; break; }
            done
            [ "$has_gateway" = 1 ] || continue
            # Dedupe
            local already=0
            for s in "${seen[@]:-}"; do [ "$s" = "$parent" ] && already=1 && break; done
            [ "$already" = 0 ] && { seen+=("$parent"); echo "$parent"; }
        done < <(find "$root" -maxdepth 3 -type f -name run.sh 2>/dev/null)
    done
}

# Detect strategy from an existing parent. Echoes one of:
#   isolated | shared-skills | shared-both | unknown
detect_strategy() {
    local parent="$1"
    local sub name mem sk
    for sub in "$parent"/*/; do
        [ -d "$sub" ] || continue
        name=$(basename "$sub")
        [[ "$name" == _* ]] && continue
        [ -f "$sub/.env" ] || continue
        mem="dir"; sk="dir"
        [ -L "$sub/memories" ] && mem="link"
        [ -L "$sub/skills" ] && sk="link"
        case "$mem:$sk" in
            dir:dir)   echo "isolated"; return ;;
            dir:link)  echo "shared-skills"; return ;;
            link:link) echo "shared-both"; return ;;
            *)         echo "unknown"; return ;;
        esac
    done
    echo "unknown"
}

# -----------------------------------------------------------------------------
# Build steps (per gateway)
# -----------------------------------------------------------------------------
write_file_if_absent() {
    local src_template="$1" dest="$2"
    if [ -e "$dest" ]; then
        op "[skip] $dest exists (no overwrite)"
        return 0
    fi
    fetch_template "$src_template" "$dest"
}

build_gateway() {
    local parent="$1" gw="$2" strategy="$3"
    local gw_path="$parent/$gw"
    local shared="$parent/_shared"

    op "mkdir -p $gw_path"
    op "mkdir -p $gw_path/sessions"
    [ "$DRY_RUN" = 1 ] || mkdir -p "$gw_path/sessions"

    # .env — generated from the chosen provider, never overwritten.
    if [ -e "$gw_path/.env" ]; then
        op "[skip] $gw_path/.env exists (no overwrite)"
    else
        op "generate .env -> $gw_path/.env (provider=$PROVIDER)"
        [ "$DRY_RUN" = 1 ] || generate_env_content "$gw_path/.env"
    fi
    op "chmod 600 $gw_path/.env"
    [ "$DRY_RUN" = 1 ] || { [ -f "$gw_path/.env" ] && chmod 600 "$gw_path/.env"; }

    # config.yaml — generated from the chosen provider, never overwritten.
    if [ -e "$gw_path/config.yaml" ]; then
        op "[skip] $gw_path/config.yaml exists (no overwrite)"
    else
        op "generate config.yaml -> $gw_path/config.yaml (provider=$PROVIDER model=$MODEL)"
        [ "$DRY_RUN" = 1 ] || generate_config_yaml "$gw_path/config.yaml"
    fi

    if [ "$CREATE_SOUL" = 1 ]; then
        if [ ! -e "$gw_path/SOUL.md" ]; then
            fetch_template "SOUL.md.template" "$gw_path/SOUL.md"
            if [ "$DRY_RUN" = 0 ] && [ -f "$gw_path/SOUL.md" ]; then
                # Substitute {{GATEWAY_NAME}} placeholder
                sed -i.bak "s/{{GATEWAY_NAME}}/$gw/g" "$gw_path/SOUL.md"
                rm -f "$gw_path/SOUL.md.bak"
            fi
        else
            op "[skip] $gw_path/SOUL.md exists"
        fi
    fi

    case "$strategy" in
        isolated)
            op "mkdir -p $gw_path/memories $gw_path/skills"
            [ "$DRY_RUN" = 1 ] || mkdir -p "$gw_path/memories" "$gw_path/skills"
            ;;
        shared-skills)
            op "mkdir -p $gw_path/memories"
            [ "$DRY_RUN" = 1 ] || mkdir -p "$gw_path/memories"
            link_shared "$gw_path/skills" "$shared/skills"
            ;;
        shared-both)
            link_shared "$gw_path/memories" "$shared/memories"
            link_shared "$gw_path/skills"   "$shared/skills"
            ;;
    esac
}

link_shared() {
    local link="$1" target="$2"
    if [ -L "$link" ]; then
        local cur; cur=$(readlink "$link" 2>/dev/null || true)
        if [ "$cur" = "$target" ]; then
            op "[skip] $link -> $target already correct"
            return 0
        fi
    elif [ -e "$link" ]; then
        op "[skip] $link exists as a real path (not overwriting)"
        return 0
    fi
    op "ln -s $target $link"
    [ "$DRY_RUN" = 1 ] || ln -s "$target" "$link"
}

ensure_shared_dirs() {
    local parent="$1" strategy="$2"
    local shared="$parent/_shared"
    [ "$strategy" = "isolated" ] && return 0
    op "mkdir -p $shared/handoff"
    [ "$DRY_RUN" = 1 ] || mkdir -p "$shared/handoff"
    case "$strategy" in
        shared-skills)
            op "mkdir -p $shared/skills"
            [ "$DRY_RUN" = 1 ] || mkdir -p "$shared/skills"
            ;;
        shared-both)
            op "mkdir -p $shared/skills $shared/memories"
            [ "$DRY_RUN" = 1 ] || mkdir -p "$shared/skills" "$shared/memories"
            ;;
    esac
}

# Replace run.sh / inject_config.py only if they exist and don't match the
# canonical template. Backup the old version to .bak exactly once.
ensure_universal_script() {
    local parent="$1" template_name="$2" dest_name="$3"
    local dest="$parent/$dest_name"
    local bak="$dest.bak"

    if [ ! -e "$dest" ]; then
        fetch_template "$template_name" "$dest"
        if [ "$dest_name" = "run.sh" ] && [ "$DRY_RUN" = 0 ] && [ -f "$dest" ]; then
            chmod +x "$dest"
            op "chmod +x $dest"
        fi
        return 0
    fi

    # Compare to template via SHA-256
    local tmp; tmp=$(mktemp)
    fetch_template "$template_name" "$tmp" 2>/dev/null
    if [ "$DRY_RUN" = 0 ] && [ -s "$tmp" ]; then
        if cmp -s "$tmp" "$dest"; then
            op "[skip] $dest already matches universal template"
            rm -f "$tmp"
            return 0
        fi
        if [ -e "$bak" ]; then
            warn "$bak already exists — leaving $dest in place"
            rm -f "$tmp"
            return 0
        fi
        op "mv $dest $bak"
        mv "$dest" "$bak"
        op "install $tmp -> $dest"
        mv "$tmp" "$dest"
        [ "$dest_name" = "run.sh" ] && chmod +x "$dest"
    else
        rm -f "$tmp" 2>/dev/null || true
    fi
}

# -----------------------------------------------------------------------------
# Mode A — fresh setup
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# Single-purpose collectors. Each prompts only when the relevant variable is
# empty. Calling again with the var cleared re-prompts — that's what makes the
# Proceed-loop edit menu work.
# -----------------------------------------------------------------------------
collect_parent() {
    if [ -z "$PARENT" ]; then
        PARENT="$(prompt "Parent folder" "$HOME/gateways")"
    fi
    PARENT="$(realpath -m "$PARENT")"
}

collect_names() {
    if [ -z "$NAMES_RAW" ]; then
        local n
        if [ -n "$COUNT" ]; then
            n="$COUNT"
        else
            n="$(prompt "How many gateways?" "2")"
        fi
        [[ "$n" =~ ^[0-9]+$ ]] || die "count must be a positive integer"
        local i nm default names_raw=""
        for ((i=1; i<=n; i++)); do
            default="gateway-$i"
            nm="$(prompt "Name for gateway $i" "$default")"
            names_raw+="${names_raw:+,}$nm"
        done
        NAMES_RAW="$names_raw"
    fi
    local nm; local _names
    IFS=',' read -ra _names <<<"$NAMES_RAW"
    [ ${#_names[@]} -ge 1 ] || die "no gateway names provided"
    for nm in "${_names[@]}"; do validate_name "$nm"; done
}

collect_strategy() {
    if [ -z "$STRATEGY" ]; then
        if [ "$NON_INTERACTIVE" = 1 ]; then
            STRATEGY="isolated"
        else
            local sel
            cat <<'EOF'

Sharing strategy:
  1) isolated      Each gateway has its own memories/ and skills/. Default.
  2) shared-skills Own memories/, shared skills/.
  3) shared-both   Both shared via _shared/ (one logical agent, N voices).

EOF
            sel="$(prompt "Choose 1/2/3" "1")"
            case "$sel" in
                1|isolated)             STRATEGY="isolated" ;;
                2|skills|shared-skills) STRATEGY="shared-skills" ;;
                3|both|shared-both)     STRATEGY="shared-both" ;;
                *) die "invalid choice: $sel" ;;
            esac
        fi
    fi
    STRATEGY="$(normalize_strategy "$STRATEGY")"
}

# -----------------------------------------------------------------------------
# Plan display + edit menus
# -----------------------------------------------------------------------------
show_plan_a() {
    local _names; _names="$(echo "$NAMES_RAW" | tr ',' ' ')"
    log "Plan:"
    log "  parent:   $PARENT"
    log "  gateways: $_names"
    log "  strategy: $STRATEGY"
    if [ "$FALLBACK_PROVIDER" != "none" ] && [ -n "$FALLBACK_PROVIDER" ]; then
        log "  provider: $PROVIDER ($MODEL) -> fallback $FALLBACK_PROVIDER ($FALLBACK_MODEL)"
    else
        log "  provider: $PROVIDER ($MODEL)  [no fallback]"
    fi
    log "  templates: $([ -d "${SCRIPT_DIR:-/nope}/templates" ] && echo "local ($SCRIPT_DIR/templates)" || echo "remote ($REPO_URL)")"
}

edit_menu_a() {
    cat <<'EOF'

What do you want to change?
   1) Parent folder
   2) Gateway names / count
   3) Sharing strategy
   4) Default LLM provider  (re-picks model + base URL + key env)
   5) Default model only    (keep the current provider)
   6) Default base URL      (MiMo region or custom provider URL)
   7) Default key env var   (e.g. ANTHROPIC_API_KEY)
   8) Fallback provider     (re-picks fallback model)
   9) Fallback model only   (keep the current fallback provider)
  10) Cancel — exit without making changes

EOF
    local sel; sel="$(prompt "Pick (1-10)" "")"
    case "$sel" in
        1)  PARENT="";                                                      collect_parent ;;
        2)  NAMES_RAW=""; COUNT="";                                         collect_names ;;
        3)  STRATEGY="";                                                    collect_strategy ;;
        4)  PROVIDER=""; MODEL=""; BASE_URL=""; KEY_ENV="";                  prompt_provider ;;
        5)  MODEL="";                                                       prompt_provider ;;
        6)  BASE_URL="";                                                    prompt_provider ;;
        7)  KEY_ENV="";                                                     prompt_provider ;;
        8)  FALLBACK_PROVIDER=""; FALLBACK_MODEL="";                        prompt_provider ;;
        9)  FALLBACK_MODEL="";                                              prompt_provider ;;
        10) die "aborted" ;;
        *)  warn "invalid pick: ${sel:-(empty)} — try again" ;;
    esac
}

# -----------------------------------------------------------------------------
# Mode A — fresh setup
# -----------------------------------------------------------------------------
mode_a_fresh() {
    log "Mode A — fresh setup"

    collect_parent
    collect_names
    collect_strategy
    prompt_provider

    while true; do
        echo
        show_plan_a
        if [ "$NON_INTERACTIVE" = 1 ] || [ "$DRY_RUN" = 1 ]; then
            break
        fi
        if yes_no "Proceed?" "Y"; then
            break
        fi
        edit_menu_a
    done

    op "mkdir -p $PARENT"
    [ "$DRY_RUN" = 1 ] || mkdir -p "$PARENT"

    ensure_shared_dirs "$PARENT" "$STRATEGY"
    ensure_universal_script "$PARENT" "run.sh.template"          "run.sh"
    ensure_universal_script "$PARENT" "inject_config.py.template" "inject_config.py"

    local names; IFS=',' read -ra names <<<"$NAMES_RAW"
    local nm
    for nm in "${names[@]}"; do
        build_gateway "$PARENT" "$nm" "$STRATEGY"
    done

    print_next_steps "$PARENT" "${names[@]}"
}

# -----------------------------------------------------------------------------
# Mode B — extend existing setup
# -----------------------------------------------------------------------------
# Mode B-specific name collector — different default ("how many NEW") and
# rejects names that already exist under the chosen parent.
collect_names_for_add() {
    local parent="$1"
    if [ -z "$NAMES_RAW" ]; then
        if [ "$NON_INTERACTIVE" = 1 ]; then
            die "--names required for --add in non-interactive mode"
        fi
        local n; n="$(prompt "How many new gateways to add?" "1")"
        [[ "$n" =~ ^[0-9]+$ ]] || die "count must be a positive integer"
        local i nm names_raw=""
        for ((i=1; i<=n; i++)); do
            nm="$(prompt "Name for new gateway $i" "")"
            [ -n "$nm" ] || die "empty gateway name"
            names_raw+="${names_raw:+,}$nm"
        done
        NAMES_RAW="$names_raw"
    fi
    local _names nm
    IFS=',' read -ra _names <<<"$NAMES_RAW"
    [ ${#_names[@]} -ge 1 ] || die "no gateway names provided"
    for nm in "${_names[@]}"; do
        validate_name "$nm"
        if [ -d "$parent/$nm" ]; then
            die "gateway '$nm' already exists at $parent/$nm — pick a different name"
        fi
    done
}

show_plan_b() {
    local parent="$1"
    local _names; _names="$(echo "$NAMES_RAW" | tr ',' ' ')"
    log "Plan:"
    log "  parent:   $parent (existing — won't touch existing gateways)"
    log "  add:      $_names"
    log "  strategy: $STRATEGY"
    if [ "$FALLBACK_PROVIDER" != "none" ] && [ -n "$FALLBACK_PROVIDER" ]; then
        log "  provider: $PROVIDER ($MODEL) -> fallback $FALLBACK_PROVIDER ($FALLBACK_MODEL)"
    else
        log "  provider: $PROVIDER ($MODEL)  [no fallback]"
    fi
}

edit_menu_b() {
    local parent="$1"
    cat <<'EOF'

What do you want to change?
   1) Gateway names / count       (which new gateways to add)
   2) Sharing strategy override   (warning: existing gateways stay as-is)
   3) Default LLM provider        (re-picks model + base URL + key env)
   4) Default model only          (keep the current provider)
   5) Default base URL            (MiMo region or custom provider URL)
   6) Default key env var
   7) Fallback provider           (re-picks fallback model)
   8) Fallback model only         (keep the current fallback provider)
   9) Cancel — exit without making changes

EOF
    local sel; sel="$(prompt "Pick (1-9)" "")"
    case "$sel" in
        1)  NAMES_RAW=""; COUNT="";                                         collect_names_for_add "$parent" ;;
        2)  STRATEGY="";                                                    collect_strategy ;;
        3)  PROVIDER=""; MODEL=""; BASE_URL=""; KEY_ENV="";                  prompt_provider ;;
        4)  MODEL="";                                                       prompt_provider ;;
        5)  BASE_URL="";                                                    prompt_provider ;;
        6)  KEY_ENV="";                                                     prompt_provider ;;
        7)  FALLBACK_PROVIDER=""; FALLBACK_MODEL="";                        prompt_provider ;;
        8)  FALLBACK_MODEL="";                                              prompt_provider ;;
        9)  die "aborted" ;;
        *)  warn "invalid pick: ${sel:-(empty)} — try again" ;;
    esac
}

# -----------------------------------------------------------------------------
# Mode B — extend existing setup
# -----------------------------------------------------------------------------
mode_b_add() {
    local parent="$1"
    log "Mode B — extending $parent"

    local detected; detected="$(detect_strategy "$parent")"
    log "detected strategy: $detected"

    if [ -z "$STRATEGY" ]; then
        if [ "$detected" = "unknown" ]; then
            if [ "$NON_INTERACTIVE" = 1 ]; then
                die "could not auto-detect strategy; pass --strategy explicitly"
            fi
            log "couldn't auto-detect strategy from existing gateways"
            collect_strategy
        else
            STRATEGY="$detected"
        fi
    else
        STRATEGY="$(normalize_strategy "$STRATEGY")"
        if [ "$detected" != "$STRATEGY" ] && [ "$detected" != "unknown" ]; then
            warn "overriding detected strategy ($detected) with --strategy $STRATEGY"
            warn "new gateways will use $STRATEGY but EXISTING gateways stay $detected (no migration)"
        fi
    fi

    # Old shared/ -> _shared/ migration hint
    if [ -d "$parent/shared" ] && [ ! -d "$parent/_shared" ]; then
        warn "found old layout: $parent/shared/ — consider 'mv $parent/shared $parent/_shared' (not done automatically)"
    fi

    collect_names_for_add "$parent"
    prompt_provider

    while true; do
        echo
        show_plan_b "$parent"
        if [ "$NON_INTERACTIVE" = 1 ] || [ "$DRY_RUN" = 1 ]; then
            break
        fi
        if yes_no "Proceed?" "Y"; then
            break
        fi
        edit_menu_b "$parent"
    done

    ensure_shared_dirs "$parent" "$STRATEGY"
    ensure_universal_script "$parent" "run.sh.template"          "run.sh"
    ensure_universal_script "$parent" "inject_config.py.template" "inject_config.py"

    local names; IFS=',' read -ra names <<<"$NAMES_RAW"
    local nm
    for nm in "${names[@]}"; do
        build_gateway "$parent" "$nm" "$STRATEGY"
    done

    print_next_steps "$parent" "${names[@]}"
}

# -----------------------------------------------------------------------------
# Final banner
# -----------------------------------------------------------------------------
print_next_steps() {
    local parent="$1"; shift
    local names=("$@")
    cat <<EOF

================================================================
Next steps
================================================================
1. Edit each gateway's .env (paste your real Telegram bot token,
   API keys, allowed users, vault path):
EOF
    local nm
    for nm in "${names[@]}"; do
        echo "     \$EDITOR $parent/$nm/.env"
    done
    cat <<EOF
2. (Optional) Run \`hermes setup\` per gateway to seed memories/
   and skills/ if you haven't yet:
     for gw in ${names[*]}; do (cd $parent/\$gw && hermes setup); done
3. Launch every discovered gateway:
     cd $parent && ./run.sh all
4. List / status / stop:
     ./run.sh list
     ./run.sh status
     ./run.sh stop          # stop all
     ./run.sh stop $nm      # stop one
================================================================
EOF
}

# -----------------------------------------------------------------------------
# Arg parsing
# -----------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --version|-V)         echo "bootstrap.sh $BOOTSTRAP_VERSION (released $BOOTSTRAP_RELEASED)"; exit 0 ;;
        --parent)             PARENT="$2"; shift 2 ;;
        --count)              COUNT="$2"; shift 2 ;;
        --names)              NAMES_RAW="$2"; shift 2 ;;
        --strategy)           STRATEGY="$2"; shift 2 ;;
        --provider)           PROVIDER="$2"; shift 2 ;;
        --model)              MODEL="$2"; shift 2 ;;
        --base-url)           BASE_URL="$2"; shift 2 ;;
        --key-env)            KEY_ENV="$2"; shift 2 ;;
        --fallback-provider)  FALLBACK_PROVIDER="$2"; shift 2 ;;
        --fallback-model)     FALLBACK_MODEL="$2"; shift 2 ;;
        --no-fallback)        FALLBACK_PROVIDER="none"; shift ;;
        --add)                MODE="add"; shift ;;
        --soul)               CREATE_SOUL=1; shift ;;
        --scan-path)          EXTRA_SCAN_PATHS+=("$2"); shift 2 ;;
        --repo-url)           REPO_URL="$2"; shift 2 ;;
        --dry-run)            DRY_RUN=1; shift ;;
        --non-interactive)    NON_INTERACTIVE=1; shift ;;
        -h|--help)            usage; exit 0 ;;
        *) die "unknown flag: $1 (try --help)" ;;
    esac
done

# -----------------------------------------------------------------------------
# Mode dispatch
# -----------------------------------------------------------------------------
log "bootstrap.sh v$BOOTSTRAP_VERSION ($BOOTSTRAP_RELEASED)"

# Set up interactive input source. Important for `curl ... | bash` runs where
# stdin is the script source — prompts must read from /dev/tty instead.
init_tty
if [ "$NON_INTERACTIVE" = 0 ] && [ -z "$TTY_FD" ]; then
    log "no terminal available — switching to non-interactive mode (will fail loudly on missing required values)"
    NON_INTERACTIVE=1
fi

if [ "$MODE" = "add" ]; then
    [ -n "$PARENT" ] || die "--add requires --parent"
    PARENT="$(realpath -m "$PARENT")"
    [ -d "$PARENT" ] || die "$PARENT does not exist (use Mode A for fresh setups)"
    [ -f "$PARENT/run.sh" ] || die "$PARENT/run.sh missing — does this look like a Hermes setup?"
    mode_b_add "$PARENT"
    exit 0
fi

# Auto-detect
if [ -n "$PARENT" ] || [ -n "$NAMES_RAW" ] || [ -n "$COUNT" ]; then
    # User supplied at least one fresh-mode flag — go to Mode A.
    mode_a_fresh
    exit 0
fi

# Fully interactive — scan first
log "scanning for existing Hermes setups under \$HOME, /root, /home/* ..."
mapfile -t CANDIDATES < <(find_hermes_parents)

if [ ${#CANDIDATES[@]} -eq 0 ]; then
    log "no existing setup found — fresh install"
    mode_a_fresh
elif [ ${#CANDIDATES[@]} -eq 1 ]; then
    log "found existing setup: ${CANDIDATES[0]}"
    if yes_no "Extend it (add gateways into the same parent)?" "Y"; then
        PARENT="${CANDIDATES[0]}"
        mode_b_add "$PARENT"
    else
        log "leaving ${CANDIDATES[0]} untouched"
        if yes_no "Create a separate, brand-new parent folder for a fresh setup?" "Y"; then
            suggested="$(suggest_fresh_parent "${CANDIDATES[0]}")"
            PARENT="$(prompt "New parent folder (must not exist or be empty)" "$suggested")"
            if [ -e "$PARENT" ] && [ -n "$(ls -A "$PARENT" 2>/dev/null)" ]; then
                die "$PARENT already exists and is not empty — pick a different path"
            fi
            mode_a_fresh
        else
            log "nothing to do — bye"
            exit 0
        fi
    fi
else
    echo "found multiple candidates:"
    for i in "${!CANDIDATES[@]}"; do
        printf "  %d) %s\n" "$((i+1))" "${CANDIDATES[$i]}"
    done
    echo "  $((${#CANDIDATES[@]}+1))) none of these — fresh setup at a NEW parent folder"
    sel="$(prompt "Pick" "1")"
    [[ "$sel" =~ ^[0-9]+$ ]] || die "invalid selection"
    if [ "$sel" -le "${#CANDIDATES[@]}" ]; then
        PARENT="${CANDIDATES[$((sel-1))]}"
        mode_b_add "$PARENT"
    else
        suggested="$(suggest_fresh_parent "${CANDIDATES[0]}")"
        PARENT="$(prompt "New parent folder (must not exist or be empty)" "$suggested")"
        if [ -e "$PARENT" ] && [ -n "$(ls -A "$PARENT" 2>/dev/null)" ]; then
            die "$PARENT already exists and is not empty — pick a different path"
        fi
        mode_a_fresh
    fi
fi
