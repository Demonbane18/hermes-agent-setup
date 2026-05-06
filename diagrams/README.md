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
  -b transparent
```

The `-b transparent` flag keeps backgrounds clean for both light and dark GitHub themes.

## Files

Rendering "look" per diagram is a deliberate choice:

- **handDrawn** (Excalidraw-style, friendly, sketchy): used for *conceptual / educational* diagrams aimed at first-timers — the kind of picture where vibes matter more than precision. Source files declare `look: handDrawn` in their frontmatter.
- **Default Mermaid** (clean, technical): used for *systems / sequence* diagrams where edge labels, alt-paths, and structural fidelity matter more than vibe.

| Source | Rendered | Look | Used in README section |
|---|---|---|---|
| `01-symlinks.mmd` | [`01-symlinks.svg`](../images/diagrams/01-symlinks.svg) | handDrawn | "What's a symlink?" |
| `02-host-container-volume.mmd` | [`02-host-container-volume.svg`](../images/diagrams/02-host-container-volume.svg) | handDrawn | "Host VM vs container vs persistent volume" |
| `03-message-flow.mmd` | [`03-message-flow.svg`](../images/diagrams/03-message-flow.svg) | mermaid | "What happens when you send a Telegram message" |
| `04-four-memories.mmd` | [`04-four-memories.svg`](../images/diagrams/04-four-memories.svg) | handDrawn | "The four kinds of memory" |
| `05-multi-gateway-architecture.mmd` | [`05-multi-gateway-architecture.svg`](../images/diagrams/05-multi-gateway-architecture.svg) | mermaid | "Architecture → Multi-gateway with shared brain" |
| `06-context-sync-loop.mmd` | [`06-context-sync-loop.svg`](../images/diagrams/06-context-sync-loop.svg) | mermaid | "Architecture → Context sync loop" |
| `07-llm-wiki-layout.mmd` | [`07-llm-wiki-layout.svg`](../images/diagrams/07-llm-wiki-layout.svg) | handDrawn | "Karpathy's LLM Wiki — four-layer structure" |
| `08-hermes-wiki-ingest.mmd` | [`08-hermes-wiki-ingest.svg`](../images/diagrams/08-hermes-wiki-ingest.svg) | mermaid | "Multi-bot Hermes ingests sources into the wiki" |
| `09-hermes-vs-openclaw.mmd` | [`09-hermes-vs-openclaw.svg`](../images/diagrams/09-hermes-vs-openclaw.svg) | handDrawn | "Hermes Agent vs. OpenClaw" |
