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

## Testing

```sh
open -n build/Confetti.app --args --fire   # launches and fires confetti immediately
```
