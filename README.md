# Reality Check Avatars

A desktop pattern-interrupt for doomscrolling. When you open Instagram, YouTube, TikTok, X, Reddit, or Facebook in Chrome, a 2D avatar slides into a corner, calls you out with sound, and slides away. It can also fire on a timer (fixed interval or a ramp that grows after each interrupt). A menu-bar dashboard controls everything. macOS only.

This is the avatar fork of [reality-check](https://github.com/riendeauan-byte/reality-check). Instead of playing video clips, it animates one of five original cartoon characters (lip-synced to the audio in real time) and plays audio you generate locally from your own clip collection with a voice changed by local AI voice conversion. The repository itself contains only original assets: code, character sprites, and scripts.

The overlay is a transparent, click-through, always-on-top layer: it never steals focus or blocks your clicks. Each fire picks a random track and a random character (no repeats back to back).

## The cast

Five characters, generated with [DiceBear](https://www.dicebear.com/) (MIT) using the [Avataaars](https://avataaars.com/) style (free for personal and commercial use, design by Pablo Stanley):

`IRON` `HUSTLE` `DISCIPLE` `TOPG` `COACH`

Each has four sprite frames (idle, half-yell, full-yell, blink). The overlay swaps frames by live speech energy (Web Audio analyser), adds breathing, peak head-bobs, and blinks. Edit the roster in `prep/avatar-gen/generate.mjs` and re-run it to change anything.

## Requirements

- macOS
- Node.js (for the overlay app)
- Google Chrome (the watched browser)
- ffmpeg (`brew install ffmpeg`) and [uv](https://docs.astral.sh/uv/) (`brew install uv`) for the audio pipeline
- Optional, for the "pause during camera or mic use" feature: Xcode Command Line Tools

## Install

1. Clone and enter:
   ```
   git clone https://github.com/riendeauan-byte/reality-check-avatars.git
   cd reality-check-avatars
   ```
2. Install the app:
   ```
   cd app && npm install && cd ..
   ```
3. Generate your audio (see "Make audio" below). The repo ships no audio: the app
   stays silent (and the menu-bar tooltip tells you so) until `audio/` has tracks.
4. Start it, and have it launch at login:
   ```
   ./install-autostart.sh
   ```
5. The first time you open a watched site, macOS asks to let it control Chrome. Click Allow.

To run once in the foreground for testing: `./start.sh` (or `RC_TEST=1 ./start.sh` to fire immediately).

## Make audio

```
./prep/convert_clips.sh /path/to/your/clips [voice-name]
```

Each voice gets its own bank at `audio/<voice-name>/` (default bank: `default`), and
banks show up in the dashboard's Voice dropdown. The reference sample for a voice is
looked up at `prep/voices/<voice-name>.wav` (fallback `prep/reference.wav`) — so a
second voice is just: drop `prep/voices/gravel.wav`, run
`./prep/convert_clips.sh ~/clips gravel`, pick Gravel in the dashboard.

For every clip in the folder, the script isolates the voice from any music bed ([demucs](https://github.com/adefossez/demucs)), converts it to a reference speaker's tone with [seed-vc](https://github.com/Plachtaa/seed-vc)'s f0-conditioned model at 44.1kHz (zero-shot, pitch shifted -2 semitones inside the model, 100 diffusion steps), applies an authority chain (EQ, broadcast compression, loudness normalization), and writes into the bank.

You provide the reference voice: drop a 10 to 30 second sample at `prep/voices/<voice-name>.wav` (fallback `prep/reference.wav`). Deeper, raspier references produce more commanding output.

First run bootstraps a Python environment and downloads model checkpoints (about 4 GB, one time). After that each clip takes about two minutes on Apple Silicon.

To also keep the untouched real audio as a selectable bank (level-matched only):

```
./prep/original_bank.sh /path/to/your/clips
```

Personal use note: converted audio re-speaks your source clips' words in a new voice. It is derivative of that source material, so the pipeline writes it as `audio/local-*` which is gitignored, refuses to run if that ignore rule is missing, and nothing under `audio/` ships with the repo. Keep it local.

## Dashboard

Click the eye icon in the menu bar to open the dashboard (or pick Settings from its menu). From there you can pause/resume, play one now, toggle the social-site trigger, toggle "pause during camera or mic use", pick fixed or ramp timer mode and its knobs, **pin an avatar** (or rotate all five), **pick a voice bank** (or play all), choose the position (corners, bottom-center, center, or random corners), and see/reset the social-visit counter. Settings persist across restarts.

## How it works

- A watcher asks Chrome for its active tab URL once a second; arriving on a watched site fires the overlay (60s cooldown). The timer fires it too.
- Each fire sends a track + character to the overlay. The avatar slides in (idle pose first, never blank), lip-syncs via an analyser tapped ahead of the volume fade, returns to rest for a beat when the audio ends, then slides out. A faint vignette behind the figure adds presence.
- Audio errors never strand the overlay: a failed track logs one line to `agent.log` and hides immediately. A 75s safety timer backstops everything.
- A small Swift helper pauses interrupts while any app uses the camera or mic.
- A launchd LaunchAgent (`com.realitycheck.avatars`) keeps it alive and starts it at login. It is independent of the original reality-check agent: both apps can run side by side with separate settings.

## Configure

- `app/main.js` — `SITES` (trigger domains), `COOLDOWN_MS`, `NO_REPEAT`, `AVATARS`.
- `app/overlay.html` — sprite thresholds, blink timing, fade (`FLOOR`/`FADE`), vignette.
- `prep/avatar-gen/generate.mjs` — the cast: styles, palettes, frames.
- `prep/convert_clips.sh` — `DIFFUSION_STEPS` (default 60), `CFG_RATE` (default 0.6).

After editing source, reload:
```
launchctl kickstart -k "gui/$(id -u)/com.realitycheck.avatars"
```

## Uninstall

```
./uninstall.sh
```
Stops it and removes the login agent. Your generated audio stays in place.

## License

MIT for the code (see [LICENSE](LICENSE)). Avatar sprites are generated with DiceBear (MIT) in the Avataaars style (free for personal and commercial use). No third-party media is included in this repository, and nothing in it grants any license to media you convert locally.
