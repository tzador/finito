# confetti

Throw confetti across all your displays from the command line.

```sh
confetti            # confetti + party sound on every connected display
confetti --silent   # no sound
```

A click-through, transparent overlay fires geometric confetti (squares, rectangles, triangles,
stars, circles, hexagons, diamonds) in [Open Color](https://yeun.github.io/open-color/) mid-tones
from both bottom corners, followed by a short rain from the top. The process exits once the last
piece has left the screen and the sound has finished, usually around five seconds.

Drop a file at `~/Library/Application Support/Confetti/party.wav` (also `mp3`, `m4a`, `aiff`,
`caf`) to replace the built-in synthesized party sound.

## Install

### Homebrew

```sh
brew tap tzador/confetti https://github.com/tzador/confetti
brew install confetti
```

The formula builds from source with the Swift toolchain, so it needs Xcode or the
Command Line Tools and macOS 13 or later. Locally built binaries are not quarantined,
so there is no Gatekeeper prompt.

### Prebuilt binary

Each [release](https://github.com/tzador/confetti/releases) ships a universal (Apple Silicon
and Intel) `confetti-vX.Y.Z-macos-universal.tar.gz`. The binary is not notarized, so after
downloading you may need to clear the quarantine flag:

```sh
tar -xzf confetti-v*-macos-universal.tar.gz
xattr -d com.apple.quarantine confetti
mv confetti /usr/local/bin/
```

### From source

```sh
swift build -c release
.build/release/confetti
```

## Releasing

Releases are built by GitHub Actions from git tags.

```sh
scripts/release.sh 0.2.0           # bumps Version.swift and the formula, commits, tags v0.2.0
git push origin main v0.2.0
```

The workflow checks that `Version.swift` matches the tag, builds a universal binary, creates
the GitHub release with the tarball and checksums, then updates `Formula/confetti.rb` on
`main` with the tagged source tarball's URL and SHA-256.

## Hacking

Run from a terminal with `swift run confetti`. The simulation lives in
`Sources/Confetti/ConfettiScene.swift`, shapes in `Shapes.swift`, the palette in
`OpenColor.swift`, and the sound synth in `PartySound.swift`.
