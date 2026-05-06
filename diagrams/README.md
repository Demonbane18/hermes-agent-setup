# Diagram sources

Mermaid source for the SVGs that ship in [`../images/diagrams/`](../images/diagrams/) and are referenced from the root README.

Each `.mmd` file maps 1:1 to an SVG of the same name in `../images/diagrams/`.

## Regenerate after editing

Requires Node.js. From this folder:

```bash
# First-time install (pulls mermaid-cli + headless Chromium for rendering)
npm install @mermaid-js/mermaid-cli puppeteer

# Render every .mmd in this folder to ../images/diagrams/<name>.svg
./render-all.sh

# Or render a single one
./node_modules/.bin/mmdc \
  -i 01-symlinks.mmd \
  -o ../images/diagrams/01-symlinks.svg \
  -p puppeteer.json \
  -b "#ffffff"
```

The `-b "#ffffff"` flag bakes a solid white background into each SVG so the diagrams stay legible on both **light and dark** GitHub themes — a transparent background plus the dark text in `theme: neutral` would otherwise vanish on dark mode.

## Files

All diagrams render with Mermaid's `theme: neutral` and straight orthogonal lines. The earlier Excalidraw-style `look: handDrawn` was dropped — the curved sketchy strokes made the labels harder to read at small zoom levels.

| Source | Rendered | Used in README section |
|---|---|---|
| `01-symlinks.mmd` | [`01-symlinks.svg`](../images/diagrams/01-symlinks.svg) | "What's a symlink?" |
| `02-host-container-volume.mmd` | [`02-host-container-volume.svg`](../images/diagrams/02-host-container-volume.svg) | "Host VM vs container vs persistent volume" |
| `03-message-flow.mmd` | [`03-message-flow.svg`](../images/diagrams/03-message-flow.svg) | "What happens when you send a Telegram message" |
| `04-four-memories.mmd` | [`04-four-memories.svg`](../images/diagrams/04-four-memories.svg) | "The four kinds of memory" |
| `05-multi-gateway-architecture.mmd` | [`05-multi-gateway-architecture.svg`](../images/diagrams/05-multi-gateway-architecture.svg) | "Architecture → Multi-gateway with shared brain" |
| `06-context-sync-loop.mmd` | [`06-context-sync-loop.svg`](../images/diagrams/06-context-sync-loop.svg) | "Architecture → Context sync loop" |
| `07-llm-wiki-layout.mmd` | [`07-llm-wiki-layout.svg`](../images/diagrams/07-llm-wiki-layout.svg) | "Karpathy's LLM Wiki — four-layer structure" |
| `08-hermes-wiki-ingest.mmd` | [`08-hermes-wiki-ingest.svg`](../images/diagrams/08-hermes-wiki-ingest.svg) | "Multi-bot Hermes ingests sources into the wiki" |
| `09-hermes-vs-openclaw.mmd` | [`09-hermes-vs-openclaw.svg`](../images/diagrams/09-hermes-vs-openclaw.svg) | "Hermes Agent vs. OpenClaw" |
