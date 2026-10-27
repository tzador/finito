#!/bin/bash
# Regenerates Sources/Finito/LeafAtlas.swift from the leaf sheets in Assets/.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(mktemp -d)/pack-leaves"
swiftc -O scripts/pack-leaves.swift -o "$BIN"
"$BIN" Assets Sources/Finito/LeafAtlas.swift
