# `~/gateways/` — the actual files

This folder mirrors the **production** Hermes multi-gateway layout described in
[the root README's Part 3](../README.md#part-3-the-multi-gateway-pattern-the-magic).
On your VPS, copy this whole folder to `~/gateways/` (inside the Hermes
container if you used the [Hostinger 1-click](../README.md#part-1-spin-up-the-vps-with-hostingers-one-click-install))
and you have a working scaffold — just paste in your real bot tokens, API keys,
and personality prompts.

## What's here

```
gateways/
├── README.md                  # this file
├── run.sh                     # multi-gateway launcher (auto-discovers gateways)
├── inject_config.py           # injects bot token from .env into config.yaml
├── work/
│   ├── .env.example             # template — copy to `.env` and fill in
│   └── config.yaml            # safe-to-commit gateway config
├── personal/
│   ├── .env.example             # template — copy to `.env` and fill in
│   └── config.yaml
└── shared/
    └── handoff/
        └── README.md          # explicit cross-gateway handoff protocol
```

## Quick start (on the VPS, inside the Hermes container)

```bash
cd ~/gateways

# 1) Materialize the real .env files (one per gateway)
for gw in work personal; do
  cp "$gw/.env.example" "$gw/.env"
  chmod 600 "$gw/.env"
  $EDITOR "$gw/.env"          # paste tokens, keys, vault path
done

# 2) Run hermes setup once per gateway to create memories/ skills/ sessions/
for gw in work personal; do
  (cd "$gw" && hermes setup)
done

# 3) Optionally shape the brain — full-share OR split-brain
# Full-share (one shared memories/ and skills/, see §3.1):
ln -sf "$PWD/work/memories" personal/memories
ln -sf "$PWD/work/skills"   personal/skills

# Split-brain (isolated memories, shared skills only — see §3.11):
ln -sf "$PWD/work/skills" personal/skills

# 4) Launch
chmod +x run.sh
./run.sh list                  # confirms it sees both gateways
./run.sh all                   # starts every gateway it discovered
```

## Adding a third (or fourth, or Nth) bot

```bash
NAME=coach
mkdir -p "$NAME"
cp work/.env.example   "$NAME/.env.example"     # use as a template
cp work/config.yaml  "$NAME/config.yaml"
cp "$NAME/.env.example" "$NAME/.env"
chmod 600 "$NAME/.env"
$EDITOR "$NAME/.env"                         # new bot token + new personality
(cd "$NAME" && hermes setup)
ln -sf "$PWD/work/skills" "$NAME/skills"     # share skills (split-brain default)
./run.sh stop && ./run.sh all
```

`run.sh` auto-discovers any subdirectory containing a `.env`. No edits to
`run.sh` needed.

## What stays gitignored

`.env`, `sessions/`, `memories/`, `gateway.pid`, `gateway_state.json`,
`logs/`, `auth.json`, `*_token.json`, anything caches. See the root
[`.gitignore`](../.gitignore).

Only the templates (`.env.example`, `config.yaml`) and the launcher are safe
to commit.
