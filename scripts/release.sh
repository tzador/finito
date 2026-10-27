#!/bin/bash
# Bumps the version, commits, and tags. Push the tag to trigger the release workflow.
# Usage: scripts/release.sh 0.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: $0 X.Y.Z" >&2; exit 2; }
[[ -z "$(git status --porcelain)" ]] || { echo "working tree is not clean" >&2; exit 1; }

sed -i '' "s/^let confettiVersion = \".*\"/let confettiVersion = \"$VERSION\"/" Sources/Confetti/Version.swift
sed -i '' "s|/archive/refs/tags/v[0-9.]*\.tar\.gz|/archive/refs/tags/v$VERSION.tar.gz|" Formula/confetti.rb

git add Sources/Confetti/Version.swift Formula/confetti.rb
git commit -q -m "Release v$VERSION"
git tag -a "v$VERSION" -m "v$VERSION"
echo "Tagged v$VERSION. Push with: git push origin main v$VERSION"
