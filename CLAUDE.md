# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Type

Documentation-only repo. Single `README.md` guide for running [Hermes Agent](https://github.com/NousResearch/hermes-agent) as **two Telegram bots sharing one brain** on a Hostinger VPS. No source code, no build, no tests, no package manifest. Edits are prose, code blocks inside Markdown, and Mermaid diagrams.

## Core Architectural Concept (the whole point of the guide)

The README documents a non-obvious pattern that diverges from upstream Hermes:

- Upstream Hermes ships **profiles** (`hermes profile create`) — fully isolated copies, separate `memories/`, `skills/`, `sessions/`.
- This repo's pattern: **dual parallel Telegram gateways under `~/gateways/{work,personal}/`** with `memories/` and `skills/` shared via Linux **symlinks** from `personal/` → `work/`. `sessions/`, `config.yaml`, and `.env` stay per-gateway. Result: one shared brain, two voices/personalities, two bot tokens.

When editing the guide, preserve this distinction — it is the entire reason the repo exists. Profiles vs. dual-gateway tradeoffs live in the table at README §"Why Dual/Multi Gateway instead of Profiles?".

## Runtime Pieces Referenced (not in this repo, but the guide drives them)

- `~/gateways/run.sh` — launcher; sources per-gateway `.env`, exports `HERMES_HOME`, runs `inject_config.py`, then `hermes gateway run`. Supports `work | personal | both | stop | status`.
- `~/gateways/inject_config.py` — reads `HERMES_TELEGRAM_BOT_TOKEN` from the loaded `.env` and writes it into that gateway's `config.yaml` at startup, so `config.yaml` stays commit-safe and the secret stays in `.env`.
- `.env.example` — referenced by §3.3 as the template both gateways copy from. Not currently present in this repo.
- `skills/obsidian_vault.md` and `skills/hermes_context_autosync.md` — example skill files shown inline in §6.3 and §7.3.

If a user asks to "add the launcher" or "add the env example", these are the canonical filenames/locations the README already commits to — match them exactly.

## Companion Systems

- **Obsidian vault** at `$OBSIDIAN_VAULT_PATH` — markdown second brain, read/written by Hermes via the `obsidian_vault` skill.
- **`hermes-context` repo** ([Demonbane18/hermes-context](https://github.com/Demonbane18/hermes-context)) — bridge between Claude Code sessions on the laptop and Hermes on the VPS. Pulled every 15 min via Hermes cron, plus on-demand via `/hermes_context_autosync`. Layout: `active-projects/`, `session-notes/`, `snippets/`.
- **Models**: primary `custom:xiaomi-mimo` (region-specific base URL — `sgp`/`ams`/`cn` are NOT interchangeable), fallback `openrouter`. Auxiliary (compression, titles) routed to `mimo-v2-flash`.

## Editing Conventions (inferred from the existing README)

- Audience is **non-developer following along**. First use of a term gets a one-line plain-English gloss; shell blocks get a `> *What this does:*` callout. Match this when adding new sections.
- Section numbering is `Part N` → `N.M` subsections; preserve when inserting.
- Two Mermaid diagrams (`flowchart TB`, `sequenceDiagram`) — keep diagrams in sync if architecture text changes.
- Comparison tables use the same column shape (`| | Profiles | Dual Gateway |`); reuse for new comparisons.
- Voice is first-person, opinionated, lightly informal. Don't sanitize into corporate-doc tone.

## Security Invariants Stated in the Guide (don't weaken them in edits)

- `.env` files are `chmod 600`; Hermes refuses world-readable env files.
- Bot tokens and API keys live in `.env`, never in `config.yaml`.
- Never force-push the `hermes-context` repo; never delete `session-notes/` without explicit user confirmation.
- Region-specific MiMo base URLs must match the dashboard's dedicated URL.

## Common Edit Tasks

- Updating model recommendations (§4 "My current picks" table, §5 default models) — keep both consistent.
- Bumping the troubleshooting list (§"Troubleshooting & Non-Tech Tips") — newest issue at the top of its sub-section, plain-English diagnosis first, fix second.
- Adding a new shared skill — show it as a fenced ```markdown block with the `---` frontmatter (`name`, `description`, optional `trigger`), matching §6.3 and §7.3.
