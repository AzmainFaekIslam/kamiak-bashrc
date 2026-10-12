#!/usr/bin/env bash
# Build kamiak_architecture.pdf: generate the per-node figures, then run LaTeX.
set -euo pipefail
cd "$(dirname "$0")"
python3 make_figs.py
mkdir -p build
latexmk -pdf -interaction=nonstopmode -halt-on-error -outdir=build main.tex >/dev/null
cp build/main.pdf kamiak_architecture.pdf
echo "built kamiak_architecture.pdf"
