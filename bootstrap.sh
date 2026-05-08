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
  --parent PATH           Parent folder for gateways (default: ~/gateways)
  --count N               Number of gateways (fresh setup only)
  --names a,b,c           Comma-separated gateway names (overrides --count)
  --strategy STRATEGY     isolated | shared-skills | shared-both
                          Aliases: none|skills|both|all
                          Default: isolated (fresh) or auto-detected (--add)
  --add                   Force Mode B (extend existing setup)
  --soul                  Also create a SOUL.md scaffold per gateway
  --scan-path PATH        Additional path to scan for existing setups
                          (repeatable)
  --repo-url URL          Base URL for fetching templates when no local
                          templates/ directory exists
                          (default: $HERMES_BOOTSTRAP_REPO_URL or the
                          Demonbane18/hermes-agent-setup main branch)
  --dry-run               Print every action without executing
  --non-interactive       Fail loudly on missing required values instead of
                          prompting
  -h, --help              This help

STRATEGIES
  isolated        Each gateway has its own memories/ and skills/. Default.
                  Maximum context separation. No _shared/ folder created.
  shared-skills   Each gateway has its own memories/. skills/ symlinked to
                  <parent>/_shared/skills/. Useful for separate personas
                  sharing one tool library.
  shared-both     memories/ AND skills/ symlinked to <parent>/_shared/.
                  Multiple Telegram front-ends to the same logical agent.

NAME RULES
  Gateway names match ^[A-Za-z0-9][A-Za-z0-9_-]*$. No leading dot or
  underscore (those clash with _shared/ and dotfiles).

SAFETY
  Never overwrites existing .env or config.yaml.
  Backs up run.sh / inject_config.py to .bak exactly once when replacing
  with a non-matching universal template.

EXAMPLES
  # Fresh setup, 3 isolated gateways
  bootstrap.sh --parent ~/gateways --count 3 --names alpha,beta,gamma \
      --strategy isolated

  # Add 2 gateways to an existing parent (strategy auto-detected)
  bootstrap.sh --add --parent ~/gateways --names delta,epsilon

  # Curl-piped, non-interactive
  curl -fsSL .../bootstrap.sh | bash -s -- \
      --parent ~/agents --count 2 --names work,personal \
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

prompt() {
    local msg="$1" default="${2:-}"
    if [ "$NON_INTERACTIVE" = 1 ]; then
        die "missing required value: $msg (running --non-interactive)"
    fi
    local reply
    if [ -n "$default" ]; then
        read -r -p "$msg [$default]: " reply
        echo "${reply:-$default}"
    else
        read -r -p "$msg: " reply
        echo "$reply"
    fi
}

confirm() {
    local msg="$1" default="${2:-Y}"
    if [ "$NON_INTERACTIVE" = 1 ]; then
        echo "$default"
        return
    fi
    local reply
    read -r -p "$msg [$default]: " reply
    echo "${reply:-$default}"
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

    write_file_if_absent ".env.template" "$gw_path/.env"
    op "chmod 600 $gw_path/.env"
    [ "$DRY_RUN" = 1 ] || { [ -f "$gw_path/.env" ] && chmod 600 "$gw_path/.env"; }

    write_file_if_absent "config.yaml.template" "$gw_path/config.yaml"

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
mode_a_fresh() {
    log "Mode A — fresh setup"

    if [ -z "$PARENT" ]; then
        PARENT="$(prompt "Parent folder" "$HOME/gateways")"
    fi
    PARENT="$(realpath -m "$PARENT")"

    local names=()
    if [ -n "$NAMES_RAW" ]; then
        IFS=',' read -ra names <<<"$NAMES_RAW"
    elif [ -n "$COUNT" ]; then
        local i
        for ((i=1; i<=COUNT; i++)); do names+=("gateway-$i"); done
    else
        local n; n="$(prompt "How many gateways?" "2")"
        [[ "$n" =~ ^[0-9]+$ ]] || die "count must be a positive integer"
        local i nm default
        for ((i=1; i<=n; i++)); do
            default="gateway-$i"
            nm="$(prompt "Name for gateway $i" "$default")"
            names+=("$nm")
        done
    fi

    [ ${#names[@]} -ge 1 ] || die "no gateway names provided"

    local nm
    for nm in "${names[@]}"; do validate_name "$nm"; done

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
                1|isolated)         STRATEGY="isolated" ;;
                2|skills|shared-skills) STRATEGY="shared-skills" ;;
                3|both|shared-both) STRATEGY="shared-both" ;;
                *) die "invalid choice: $sel" ;;
            esac
        fi
    fi
    STRATEGY="$(normalize_strategy "$STRATEGY")"

    log "Plan:"
    log "  parent:   $PARENT"
    log "  gateways: ${names[*]}"
    log "  strategy: $STRATEGY"
    log "  templates: $([ -d "${SCRIPT_DIR:-/nope}/templates" ] && echo "local ($SCRIPT_DIR/templates)" || echo "remote ($REPO_URL)")"

    if [ "$NON_INTERACTIVE" = 0 ] && [ "$DRY_RUN" = 0 ]; then
        local ok; ok="$(confirm "Proceed?" "Y")"
        [[ "$ok" =~ ^[Yy] ]] || die "aborted"
    fi

    op "mkdir -p $PARENT"
    [ "$DRY_RUN" = 1 ] || mkdir -p "$PARENT"

    ensure_shared_dirs "$PARENT" "$STRATEGY"
    ensure_universal_script "$PARENT" "run.sh.template"          "run.sh"
    ensure_universal_script "$PARENT" "inject_config.py.template" "inject_config.py"

    for nm in "${names[@]}"; do
        build_gateway "$PARENT" "$nm" "$STRATEGY"
    done

    print_next_steps "$PARENT" "${names[@]}"
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
            local sel; sel="$(prompt "Strategy (isolated|shared-skills|shared-both)" "isolated")"
            STRATEGY="$(normalize_strategy "$sel")"
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

    # Detect old shared/ -> _shared/ migration suggestion
    if [ -d "$parent/shared" ] && [ ! -d "$parent/_shared" ]; then
        warn "found old layout: $parent/shared/ — consider 'mv $parent/shared $parent/_shared' (not done automatically)"
    fi

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

    local names=()
    IFS=',' read -ra names <<<"$NAMES_RAW"
    local nm
    for nm in "${names[@]}"; do
        validate_name "$nm"
        if [ -d "$parent/$nm" ]; then
            die "gateway '$nm' already exists at $parent/$nm — pick a different name"
        fi
    done

    log "Plan:"
    log "  parent:   $parent"
    log "  add:      ${names[*]}"
    log "  strategy: $STRATEGY"

    if [ "$NON_INTERACTIVE" = 0 ] && [ "$DRY_RUN" = 0 ]; then
        local ok; ok="$(confirm "Proceed?" "Y")"
        [[ "$ok" =~ ^[Yy] ]] || die "aborted"
    fi

    ensure_shared_dirs "$parent" "$STRATEGY"
    ensure_universal_script "$parent" "run.sh.template"          "run.sh"
    ensure_universal_script "$parent" "inject_config.py.template" "inject_config.py"

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
        --parent)           PARENT="$2"; shift 2 ;;
        --count)            COUNT="$2"; shift 2 ;;
        --names)            NAMES_RAW="$2"; shift 2 ;;
        --strategy)         STRATEGY="$2"; shift 2 ;;
        --add)              MODE="add"; shift ;;
        --soul)             CREATE_SOUL=1; shift ;;
        --scan-path)        EXTRA_SCAN_PATHS+=("$2"); shift 2 ;;
        --repo-url)         REPO_URL="$2"; shift 2 ;;
        --dry-run)          DRY_RUN=1; shift ;;
        --non-interactive)  NON_INTERACTIVE=1; shift ;;
        -h|--help)          usage; exit 0 ;;
        *) die "unknown flag: $1 (try --help)" ;;
    esac
done

# -----------------------------------------------------------------------------
# Mode dispatch
# -----------------------------------------------------------------------------
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
    ans="$(confirm "Extend it?" "Y")"
    if [[ "$ans" =~ ^[Yy] ]]; then
        PARENT="${CANDIDATES[0]}"
        mode_b_add "$PARENT"
    else
        mode_a_fresh
    fi
else
    echo "found multiple candidates:"
    for i in "${!CANDIDATES[@]}"; do
        printf "  %d) %s\n" "$((i+1))" "${CANDIDATES[$i]}"
    done
    echo "  $((${#CANDIDATES[@]}+1))) none of these — start fresh"
    sel="$(prompt "Pick" "1")"
    [[ "$sel" =~ ^[0-9]+$ ]] || die "invalid selection"
    if [ "$sel" -le "${#CANDIDATES[@]}" ]; then
        PARENT="${CANDIDATES[$((sel-1))]}"
        mode_b_add "$PARENT"
    else
        mode_a_fresh
    fi
fi
