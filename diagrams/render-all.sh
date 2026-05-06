#!/usr/bin/env bash
# Render every .mmd file in this folder to ../images/diagrams/<name>.svg
# Requires: Node.js (npx will fetch @mermaid-js/mermaid-cli on first run).
#
# Background is a solid near-white (`#ffffff`) instead of transparent so
# diagrams stay legible on GitHub's dark mode — text in `theme: neutral`
# is dark grey and would vanish against a transparent (= dark) page.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/../images/diagrams"
mkdir -p "$OUT_DIR"

for mmd in "$SCRIPT_DIR"/*.mmd; do
    base="$(basename "$mmd" .mmd)"
    out="$OUT_DIR/$base.svg"
    echo "Rendering $base -> $out"
    npx --yes -p @mermaid-js/mermaid-cli@latest mmdc \
        -i "$mmd" \
        -o "$out" \
        -p "$SCRIPT_DIR/puppeteer.json" \
        -b "#ffffff"
done

echo "Done. SVGs in $OUT_DIR"
