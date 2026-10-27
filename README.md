# finito

Throw confetti across all your displays from the command line. Celebrate a green build,
a finished task, or a merged PR with a single command.

```sh
finito            # confetti + party sound on every connected display
finito --silent   # no sound
```

A click-through, transparent overlay fires geometric confetti (squares, rectangles, triangles,
stars, circles, hexagons, diamonds) in [Open Color](https://yeun.github.io/open-color/) mid-tones
from both bottom corners, followed by a short rain from the top. The process exits once the last
piece has left the screen and the sound has finished, usually within a few seconds.

Drop a file at `~/Library/Application Support/Finito/party.wav` (also `mp3`, `m4a`, `aiff`,
`caf`) to replace the built-in synthesized party sound.

Currently macOS only. The layout leaves room for Linux and Windows ports later.

## Install

### Homebrew (macOS)

```sh
brew tap tzador/finito https://github.com/tzador/finito
brew install finito
```

The formula builds from source with the Swift toolchain, so it needs Xcode or the
Command Line Tools and macOS 13 or later. Locally built binaries are not quarantined,
so there is no Gatekeeper prompt.

### Prebuilt binary

Each [release](https://github.com/tzador/finito/releases) ships a universal (Apple Silicon
and Intel) `finito-vX.Y.Z-macos-universal.tar.gz`. The binary is not notarized, so after
downloading you may need to clear the quarantine flag:

```sh
tar -xzf finito-v*-macos-universal.tar.gz
xattr -d com.apple.quarantine finito
mv finito /usr/local/bin/
```

### From source

```sh
swift build -c release --package-path mac
mac/.build/release/finito
```

## Repository layout

- `mac/` — the Swift package for macOS.
- `Formula/finito.rb` — the Homebrew formula.
- `.github/workflows/mac-*.yml` — CI and tagged releases for the macOS build.
- `scripts/release.sh` — version bump and tag helper.

## Releasing

Releases are built by GitHub Actions from git tags.

```sh
scripts/release.sh 0.2.0           # bumps Version.swift and the formula, commits, tags v0.2.0
git push origin main v0.2.0
```

The workflow checks that `Version.swift` matches the tag, builds a universal binary, creates
the GitHub release with the tarball and checksums, then updates `Formula/finito.rb` on
`main` with the tagged source tarball's URL and SHA-256.

## Hacking

Run with `swift run --package-path mac finito`. The simulation lives in
`mac/Sources/Finito/ConfettiScene.swift`, shapes in `Shapes.swift`, the palette in
`OpenColor.swift`, and the sound synth in `PartySound.swift`.
