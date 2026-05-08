# `~/gateways/` — the actual files

This folder mirrors the **production** Hermes multi-gateway layout described in
[the root README's Part 3](../README.md#part-3-multi-gateway-setup--flexible-n-gateway-pattern).
On your VPS, copy this whole folder to `~/gateways/` (inside the Hermes
container if you used the [Hostinger 1-click](../README.md#part-1-spin-up-the-vps-with-hostingers-one-click-install))
and you have a working scaffold for the **`shared-both`** strategy — paste in
your real bot tokens, API keys, and personality prompts, and you're done.

For other strategies (`isolated`, `shared-skills`) and any non-default parent
folder name, run [`bootstrap.sh`](../bootstrap.sh) instead — see
[§3.9](../README.md#39-one-command-bootstrap-bootstrapsh).

## What's here

```
gateways/
├── README.md                  # this file
├── run.sh                     # universal launcher (auto-discovers gateways)
├── inject_config.py           # universal token injector
├── work/                      # worked example — work voice
│   ├── .env.example             # template — copy to `.env` and fill in
│   ├── config.yaml            # safe-to-commit gateway config
│   └── SOUL.md                # identity / personality (committed)
├── personal/                  # worked example — personal voice
│   ├── .env.example
│   ├── config.yaml
│   └── SOUL.md
└── _shared/
    └── handoff/
        └── README.md          # explicit cross-gateway handoff protocol
```

The `work/` and `personal/` directories are a **worked example of the
`shared-both` strategy** (one shared brain, two voices). Use them as-is, or
read them as reference and `bootstrap.sh` your own layout from scratch.

## Quick start (on the VPS — clone-then-copy)

```bash
cd ~/gateways

# 1) Materialise the real .env files (one per gateway)
for gw in work personal; do
  cp "$gw/.env.example" "$gw/.env"
  chmod 600 "$gw/.env"
  $EDITOR "$gw/.env"          # paste tokens, keys, vault path
done

# 2) Run hermes setup once per gateway to create memories/ skills/ sessions/
for gw in work personal; do
  (cd "$gw" && hermes setup)
done

# 3) Apply the strategy you want (this example: shared-both)
mkdir -p _shared/memories _shared/skills _shared/handoff
for gw in work personal; do
  rm -rf "$gw/memories" "$gw/skills"
  ln -s "$PWD/_shared/memories" "$gw/memories"
  ln -s "$PWD/_shared/skills"   "$gw/skills"
done

# 4) Launch
chmod +x run.sh
./run.sh list                  # confirms it sees both gateways
./run.sh all                   # starts every gateway it discovered
```

## Quick start (on the VPS — bootstrap)

From any clone or curl-piped one-liner:

```bash
# Fresh setup (interactive)
./bootstrap.sh

# Or non-interactive
./bootstrap.sh --parent ~/gateways --count 2 --names work,personal \
    --strategy shared-both --non-interactive

# Add another bot later
./bootstrap.sh --add --parent ~/gateways --names coach
```

`bootstrap.sh` auto-detects whether you're starting fresh or extending an
existing setup, prompts for the strategy, and never overwrites existing
`.env` or `config.yaml`. See the [root README §3.9](../README.md#39-one-command-bootstrap-bootstrapsh).

## Adding a third (or fourth, or Nth) bot — manual recipe

```bash
NAME=coach
mkdir -p "$NAME"
cp work/.env.example   "$NAME/.env.example"   # use as a template
cp work/config.yaml    "$NAME/config.yaml"
cp "$NAME/.env.example" "$NAME/.env"
chmod 600 "$NAME/.env"
$EDITOR "$NAME/.env"                          # new bot token + new personality
(cd "$NAME" && hermes setup)

# Apply the same strategy as your existing gateways. shared-both example:
rm -rf "$NAME/memories" "$NAME/skills"
ln -s "$PWD/_shared/memories" "$NAME/memories"
ln -s "$PWD/_shared/skills"   "$NAME/skills"

./run.sh stop && ./run.sh all
```

`run.sh` auto-discovers any subdirectory containing `.env` + `config.yaml`
(and skips anything starting with `_`). No edits to `run.sh` needed.

## What stays gitignored

`.env`, `sessions/`, `memories/`, `gateway.pid`, `gateway_state.json`,
`logs/`, `auth.json`, `*_token.json`, anything caches, plus the canonical
shared dirs (`_shared/memories/`, `_shared/sessions/`) and any `.bak`
backups bootstrap creates. See the root [`.gitignore`](../.gitignore).

Only the templates (`.env.example`, `config.yaml`, `SOUL.md`) and the
launcher are safe to commit.
