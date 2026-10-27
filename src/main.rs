//! finito: blow autumn leaves across all your displays from the command line.
mod atlas;
mod detach;
mod overlay;
mod render;
mod rng;
mod scene;
mod sound;

use objc2::MainThreadMarker;
use objc2_app_kit::NSScreen;
use objc2_foundation::{NSNumber, NSString};
use std::process::exit;
use std::time::{SystemTime, UNIX_EPOCH};

const VERSION: &str = env!("CARGO_PKG_VERSION");

// MARK: - Options

#[derive(Default)]
struct Options {
    silent: bool,
    wait: bool,
    seed: Option<u32>,
    /// Internal: drive only this display. Set by the parent on each drawing child it spawns.
    display: Option<u32>,
    /// Internal: play the sound and nothing else. Set by the parent on the sound child.
    sound_only: bool,
}

fn usage() -> String {
    format!(
        "finito {VERSION} — blow autumn leaves across all your displays

Usage: finito [options]

Options:
  -s, --silent      do not play the party sound
  --seed N          replay a particular show (each run composes a new one)
  -w, --wait        stay in the foreground until the animation and sound finish
  -v, --version     print the version and exit
  -h, --help        show this help and exit

Positional arguments are ignored, so finito works as-is as a hook or
notify command for Claude Code and Codex (see the README).

Drop a file at ~/Library/Application Support/Finito/party.wav
(or .mp3, .m4a, .aiff, .caf) to replace the built-in party sound."
    )
}

impl Options {
    fn parse(args: impl Iterator<Item = String>) -> Options {
        let mut options = Options::default();
        let mut args = args.peekable();
        while let Some(raw) = args.next() {
            let (arg, inline) = match raw.split_once('=') {
                Some((a, v)) => (a.to_string(), Some(v.to_string())),
                None => (raw.clone(), None),
            };
            let mut value = |what: &str| -> String {
                match inline.clone().or_else(|| args.next()) {
                    Some(v) => v,
                    None => {
                        eprintln!("finito: {arg} needs {what}");
                        exit(2);
                    }
                }
            };
            match arg.as_str() {
                "-s" | "--silent" | "--no-sound" => options.silent = true,
                "--seed" => {
                    let v = value("a number");
                    options.seed = Some(v.parse().unwrap_or_else(|_| {
                        eprintln!("finito: --seed needs a number");
                        exit(2);
                    }));
                }
                "--display" => {
                    let v = value("a display ID");
                    options.display = Some(v.parse().unwrap_or_else(|_| {
                        eprintln!("finito: --display needs a display ID");
                        exit(2);
                    }));
                    options.wait = true;
                }
                "--sound-only" => {
                    options.sound_only = true;
                    options.wait = true;
                }
                "-w" | "--wait" => options.wait = true,
                "-v" | "--version" => {
                    println!("{VERSION}");
                    exit(0);
                }
                "-h" | "--help" => {
                    println!("{}", usage());
                    exit(0);
                }
                // Positional arguments are ignored so finito can be used directly as a
                // Codex `notify` program, which passes a JSON payload as the first argument.
                _ if !arg.starts_with('-') => continue,
                _ => {
                    eprintln!("finito: unknown option '{arg}'\n{}", usage());
                    exit(2);
                }
            }
        }
        options
    }
}

/// The Core Graphics display IDs of every connected screen, in `NSScreen.screens` order.
/// Stable across processes, unlike the index in that list.
fn connected_displays() -> Vec<u32> {
    let mtm = MainThreadMarker::new().expect("finito starts on the main thread");
    let key = NSString::from_str("NSScreenNumber");
    NSScreen::screens(mtm)
        .iter()
        .filter_map(|screen| {
            let number = screen.deviceDescription().objectForKey(&key)?;
            let number = number.downcast::<NSNumber>().ok()?;
            Some(number.unsignedIntValue())
        })
        .collect()
}

fn main() {
    let options = Options::parse(std::env::args().skip(1));

    // Compose a different show every launch unless a seed was given. The seed is passed on to
    // the detached children so what plays is what this process chose.
    let seed = options.seed.unwrap_or_else(|| {
        let millis = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0);
        (millis as u32) ^ std::process::id()
    });

    // Every display gets a process of its own, and so does the sound. One window per process
    // keeps every display at its own refresh rate instead of the slowest one starving the rest.
    // The parent spawns one detached drawing child per display plus one child that only plays
    // the sound, and either returns right away or, with `--wait`, waits for all of them.
    let mut displays: Option<Vec<u32>> = options.display.map(|d| vec![d]);
    if options.sound_only {
        displays = Some(Vec::new());
    }
    if options.display.is_none() && !options.sound_only {
        let connected = connected_displays();
        let mut children: Vec<libc::pid_t> = Vec::new();
        let mut failure: Option<String> = None;
        for display in &connected {
            let args = [
                "--display",
                &display.to_string(),
                "--seed",
                &seed.to_string(),
                "--silent",
            ]
            .map(String::from);
            match detach::spawn_detached(&args) {
                Ok(pid) => children.push(pid),
                Err(error) => {
                    failure = Some(error);
                    break;
                }
            }
        }
        if failure.is_none() && !options.silent {
            let args = ["--sound-only", "--seed", &seed.to_string()].map(String::from);
            match detach::spawn_detached(&args) {
                Ok(pid) => children.push(pid),
                Err(error) => failure = Some(error),
            }
        }
        match failure {
            None => {
                if options.wait {
                    for pid in children {
                        detach::wait_for(pid);
                    }
                }
                exit(0);
            }
            Some(error) => {
                eprintln!("finito: {error}; running in the foreground");
                // The drawing children spawned before the failure cover their displays; the
                // sound child is spawned last, so it never got started. Do the rest here.
                displays = Some(connected[children.len().min(connected.len())..].to_vec());
            }
        }
    }

    let sound = (!options.silent).then(|| std::thread::spawn(move || sound::play(seed)));
    let show = match &displays {
        Some(ids) if ids.is_empty() => Ok(()),
        _ => overlay::run(seed, displays),
    };
    if let Err(error) = show {
        eprintln!("finito: {error}");
    }
    if let Some(sound) = sound {
        let _ = sound.join();
    }
}
