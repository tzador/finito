# finito

Throw a celebration across all your displays from the command line. Mark a green build,
a finished task, or a merged PR with confetti, fireworks, bubbles, a laser show, or whatever
finito picks for you.

```sh
finito                              # random visual with a sound that fits it
finito --visual fireworks           # pick the visual, random fitting sound
finito --sound tada                 # random visual, pick the sound
finito --visual stars --sound chime
finito --silent                     # no sound
finito --visual none --sound coin   # sound only
finito --list                       # everything available
finito --wait                       # block until the show is over (useful in scripts)
```

Every effect plays on a click-through, transparent overlay on each connected display, and the
command returns immediately while the show runs in a detached background process. Pass `--wait`
to block until the last piece has left the screen and the sound has finished.

Visuals: `confetti`, `stars`, `bubbles`, `rainbow`, `fireworks`, `snow`, `balloons`, `hearts`,
`lasers`, `matrix`, `fireflies`, `shockwave`.

Sounds: `party`, `fanfare`, `tada`, `chime`, `coin`, `powerup`, `applause`, `drumroll`, `pop`,
`sparkle`, `whoosh`. All of them are synthesized at launch; there are no bundled assets.

Drop audio files (`wav`, `mp3`, `m4a`, `aiff`, `caf`) into
`~/Library/Application Support/Finito/sounds/` to add your own. The file name becomes the sound
name and shows up under `--list`; a custom file with a built-in name replaces that sound.

macOS only.

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
scripts/release.sh 0.2.0           # bumps Version.swift and the formula, commits, tags v0.2.0
git push origin main v0.2.0
```

The workflow checks that `Version.swift` matches the tag, builds a universal binary, creates
the GitHub release with the tarball and checksums, then updates `Formula/finito.rb` on
`main` with the tagged source tarball's URL and SHA-256.

## Hacking

Run with `swift run finito --visual stars --wait`. Visuals live in `Sources/Finito/Visuals/`,
one scene per effect on top of `EffectScene`, which provides timers, spawners and the idle
detection that ends the process. Sounds live in `Sources/Finito/Sounds/`: `Mixer.swift` holds
the DSP building blocks and `Sound.swift` one recipe per sound. `Visual.pairedSounds` is the
table a random pick draws from.
