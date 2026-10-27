# Confetti

A tiny macOS menu bar app that throws confetti across every connected display.

- Lives in the menu bar (party popper icon), no Dock icon.
- Starts at login (toggle in the menu).
- **Trigger Confetti**: full-screen, click-through overlay on all displays with geometric confetti
  (squares, rectangles, triangles, stars, circles, hexagons, diamonds) in
  [Open Color](https://yeun.github.io/open-color/) mid-tone colors.
- **Play Party Sound**: optional, persisted toggle. Plays a synthesized pop + fanfare, or your own
  file if you drop one at `~/Library/Application Support/Confetti/party.wav` (also `mp3`, `m4a`, `aiff`, `caf`).

## Build & install

Requires Xcode command line tools (Swift 5.9+), macOS 13+.

```sh
./build.sh            # builds build/Confetti.app
./build.sh --install  # also copies it to /Applications and launches it
```

Keep the app in `/Applications` so the login item keeps pointing at a stable location.

## Trigger from the command line

```sh
bin/confetti            # fire confetti on all displays
bin/confetti --silent   # fire without the party sound
bin/confetti --sound    # fire with the party sound, even if it is turned off in the menu
```

The script opens a `confetti://fire` URL, so it also launches the app if it is not running.
Put `bin` on your `PATH` or symlink it, e.g. `ln -s "$PWD/bin/confetti" /usr/local/bin/confetti`.

## Testing

```sh
open -n build/Confetti.app --args --fire   # launches and fires confetti immediately
```
