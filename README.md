# finito

Blow autumn leaves across all your displays from the command line. Celebrate a green build,
a finished task, or a merged PR with a single command.

```sh
finito            # leaves + party sound on every connected display
finito --silent   # no sound
finito --wait     # block until the show is over (useful in scripts)
```

A click-through, transparent overlay sends a cloud of photographed autumn leaves (maple, oak,
ginkgo, birch and more, 256 of them) drifting over your screen. Each leaf glides sideways on a
tilt, stalls, drops a little faster while it swings back and banks into the new direction; most
rock about their axis, some tumble right over, and a wandering breeze pushes the whole cloud.
Every launch composes a different show: the launch pattern (a steady fall, a gust sweeping in
from one side, a swirl kicked up from the bottom corners, or all of them), the wind, the
density, and a short jingle in a random key with a melodic run resolving onto a chord.
Pass `--seed N` to replay a show you liked. The command returns immediately and the show
plays out in detached background processes (one per display), so your terminal is free right
away. Pass `--wait` to block until the last leaf has left the screen and the sound has
finished, usually within four or five seconds.

Drop a file at `~/Library/Application Support/Finito/party.wav` (also `mp3`, `m4a`, `aiff`,
`caf`) to replace the built-in synthesized party sound.

macOS only.

## Install

### Homebrew (macOS)

```sh
brew tap tzador/finito https://github.com/tzador/finito
brew trust tzador/finito
brew install finito
```

Recent Homebrew versions refuse to load formulas from third-party taps until you trust
the tap once with `brew trust`.

The formula builds from source with the Rust toolchain (Homebrew installs it as a build
dependency) and needs macOS 13 or later. Locally built binaries are not quarantined, so
there is no Gatekeeper prompt.

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

With a Rust toolchain installed (<https://rustup.rs>):

```sh
cargo build --release
target/release/finito
```

## Celebrate when your coding agent finishes

finito returns immediately, ignores anything on stdin and ignores positional arguments, so it
drops straight into the hook systems of Claude Code and Codex without a wrapper script. Use the
absolute path from `which finito` if your agent runs with a reduced `PATH`.

For each agent you can either edit the hook file by hand or paste a one-off prompt that asks
the agent to do it for you. Use `finito --silent` instead of `finito` to skip the sound.

### Claude Code

**By hand.** Add a `Stop` hook to `~/.claude/settings.json` (or a project's
`.claude/settings.json`). It fires each time Claude finishes a turn and hands control back to
you:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "finito" }
        ]
      }
    ]
  }
}
```

**With a prompt.** This runs a one-off headless session that is only allowed to read and edit
files, merges the hook into your existing settings and leaves everything else untouched:

```sh
claude -p --allowedTools Read,Edit,Write "Add a Stop hook to ~/.claude/settings.json that runs the command \"finito\" (type: command). Keep every existing setting and hook; create the file with just the hooks key if it does not exist; do nothing if an equivalent Stop hook is already there. Show me the resulting file."
```

Either way the hook takes effect in new sessions; run `/hooks` inside Claude Code to review it.

### Codex

**By hand.** Codex hooks use the same schema. Add a `Stop` hook to `~/.codex/hooks.json` (or a
project's `.codex/hooks.json`):

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "finito", "timeout": 5 }
        ]
      }
    ]
  }
}
```

**With a prompt.** This runs Codex non-interactively with write access limited to `~/.codex`:

```sh
codex exec -C ~/.codex -s workspace-write "Add a Stop hook to hooks.json in this directory that runs the command \"finito\" (type: command, timeout: 5). Keep every existing setting and hook; create the file with just the hooks key if it does not exist; do nothing if an equivalent Stop hook is already there. Show me the resulting file."
```

Codex asks you to review and trust new hooks before they run; use `/hooks` inside Codex to do
that. Alternatively, the older `notify` setting in `~/.codex/config.toml` runs a program every
time a turn completes, passing a JSON payload as an argument that finito simply ignores:

```toml
notify = ["finito"]
```

## Releasing

Releases are built by GitHub Actions from git tags.

```sh
scripts/release.sh 0.2.0           # bumps Cargo.toml and the formula, commits, tags v0.2.0
git push origin main v0.2.0
```

The workflow checks that the version in `Cargo.toml` matches the tag, builds a universal
binary (Apple Silicon and Intel, joined with `lipo`), creates the GitHub release with the
tarball and checksums, then updates `Formula/finito.rb` on `main` with the tagged source
tarball's URL and SHA-256.

## Hacking

Run with `cargo run --release`. The sources are in `src/`: the simulation lives in `scene.rs`,
the transparent overlay windows in `overlay.rs` (winit plus a few AppKit calls), the sprite
renderer in `render.rs` and `shader.wgsl` (wgpu on Metal), the per-display child processes in
`detach.rs`, and the sound synth in `sound.rs`. Each display is driven by its own detached
process so every screen runs at its own refresh rate.

## Leaf artwork

The leaves come from the 4×4 sheets in `Assets/`. `build.rs` slices every sheet into single
leaves, strips the background noise, packs them into one premultiplied PNG atlas and embeds it
into the binary together with the cell rectangles, so finito stays self-contained. Cargo reruns
it whenever a sheet changes.
