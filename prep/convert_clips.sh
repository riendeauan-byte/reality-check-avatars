#!/usr/bin/env bash
# Re-voice a folder of clips into the app's audio pool — entirely on your machine.
#
#   ./prep/convert_clips.sh <clips-dir> [voice-name] [reference.wav]
#
# Output lands in audio/<voice-name>/ — each voice gets its own bank, selectable
# in the dashboard's Voice dropdown. Default voice-name: "default". The reference
# sample is looked up at prep/voices/<voice-name>.wav, falling back to
# prep/reference.wav, unless given explicitly as the third argument.
#
# For each video/audio file in <clips-dir>: extract speech, convert the voice
# to the reference speaker's tone (seed-vc, zero-shot), apply the authority
# chain (EQ + compression + loudness), and write audio/local-<name>.opus.
#
# PERSONAL-USE TOOL. Output re-speaks the source words in a new voice and is
# derivative of the source material: it is gitignored (audio/local-*) and must
# never be committed or distributed. The reference voice sample is yours to
# provide (10-30s wav/mp3 at prep/reference.wav, also gitignored).
#
# Everything runs locally and free: seed-vc (zero-shot VC), ffmpeg. First run
# bootstraps a python env and downloads model checkpoints (~2.5 GB, one time).
# Settings proven by ear: 60 diffusion steps, cfg 0.6, no post pitch shift
# (post pitch stacking causes warble artifacts on shouted speech).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIPS="${1:-}"
VOICE="${2:-${VOICE_NAME:-default}}"
REF="${3:-$ROOT/prep/voices/$VOICE.wav}"
[ -f "$REF" ] || REF="$ROOT/prep/reference.wav"
SV="${SEEDVC_DIR:-$ROOT/prep/seed-vc}"
SEEDVC_REV="${SEEDVC_REV:-51383efd921027683c89e5348211d93ff12ac2a8}"
WORK="${TMPDIR:-/tmp}/rc-avatars-convert"
STEPS="${DIFFUSION_STEPS:-60}"
CFG="${CFG_RATE:-0.6}"

die() { echo "ERROR: $*" >&2; exit 1; }
[ -n "$CLIPS" ] && [ -d "$CLIPS" ] || die "usage: $0 <clips-dir> [reference.wav]"
[ -f "$REF" ] || die "reference voice not found: $REF
Drop a 10-30s sample of the target voice there (wav or mp3)."
command -v ffmpeg >/dev/null || die "ffmpeg missing — brew install ffmpeg"

# Containment guard: the gitignore rule for derivative output must be alive
# BEFORE anything is written. Safety never rests on an untested config line.
( cd "$ROOT" && git check-ignore -q "audio/$VOICE/probe.opus" ) \
  || die "audio/ is not gitignored — refusing to write derivative audio"

# Bootstrap seed-vc + env (one time). Uses uv if available, else python3.10/3.11.
if [ ! -d "$SV" ]; then
  echo "Cloning seed-vc (one time)..."
  git clone https://github.com/Plachtaa/seed-vc "$SV" && git -C "$SV" checkout -q "$SEEDVC_REV" || die "clone failed"
fi
if [ ! -x "$SV/venv310/bin/python" ]; then
  echo "Building python env (one time)..."
  command -v uv >/dev/null || die "uv missing — install from https://docs.astral.sh/uv/ (or: brew install uv)"
  cat > "$SV/req-trim.txt" <<'EOF'
torch
torchaudio
torchvision
torchcodec
numpy==1.26.4
scipy==1.13.1
librosa==0.10.2
huggingface-hub>=0.28.1
munch==4.0.0
einops==0.8.0
descript-audio-codec==1.0.0
pydub==0.25.1
transformers==4.46.3
soundfile==0.12.1
pyyaml
python-dotenv
hydra-core==1.3.2
accelerate
EOF
  (cd "$SV" && uv venv --python 3.10 venv310 && uv pip install --python venv310/bin/python -r req-trim.txt) \
    || die "env build failed"
fi

mkdir -p "$WORK/src" "$WORK/vc" "$ROOT/audio/$VOICE"
echo "voice bank: $VOICE  (reference: $REF)"
REFW="$WORK/reference.wav"
ffmpeg -y -v error -i "$REF" -ac 1 -ar 44100 "$REFW" || die "could not read reference audio"

post() { # $1 in.wav  $2 out.opus — authority chain + two-pass loudnorm
  local CH="aresample=48000,highpass=f=55,acompressor=threshold=-20dB:ratio=2.5:attack=12:release=180:makeup=3dB"
  ffmpeg -hide_banner -nostats -y -i "$1" -af "$CH,loudnorm=I=-16:TP=-1.5:print_format=json" -f null - 2>&1 \
    | sed -n '/^{/,/^}/p' > "$WORK/ln.json" || return 1
  local ARGS
  ARGS=$(LN_JSON="$WORK/ln.json" python3 - 2>/dev/null <<'PY'
import json, os
d = json.load(open(os.environ["LN_JSON"]))
print(f"measured_I={d['input_i']}:measured_TP={d['input_tp']}:"
      f"measured_LRA={d['input_lra']}:measured_thresh={d['input_thresh']}")
PY
) || return 1
  ffmpeg -y -v error -i "$1" -af "$CH,loudnorm=I=-16:TP=-1.5:linear=true:$ARGS" \
    -ar 48000 -c:a libopus -b:a 96k "$2"
}

ok=0; skip=0
shopt -s nullglob
for f in "$CLIPS"/*.webm "$CLIPS"/*.mp4 "$CLIPS"/*.mov "$CLIPS"/*.m4a "$CLIPS"/*.mp3 "$CLIPS"/*.wav; do
  name=$(basename "$f"); name="${name%.*}"
  out="$ROOT/audio/$VOICE/$name.opus"
  [ -f "$out" ] && { echo "have  $name"; ok=$((ok+1)); continue; }
  ffmpeg -y -v error -i "$f" -vn -ac 1 -ar 44100 "$WORK/src/src-$name.wav" \
    || { echo "skip  $name (extract failed)"; skip=$((skip+1)); continue; }
  (cd "$SV" && ./venv310/bin/python inference.py \
      --source "$WORK/src/src-$name.wav" --target "$REFW" --output "$WORK/vc" \
      --diffusion-steps "$STEPS" --length-adjust 1.0 --inference-cfg-rate "$CFG" --fp16 False) >/dev/null 2>&1 \
    || { echo "skip  $name (conversion failed)"; skip=$((skip+1)); continue; }
  vcw="$WORK/vc/vc_src-${name}_reference_1.0_${STEPS}_${CFG}.wav"
  [ -f "$vcw" ] || vcw=$(ls -t "$WORK/vc/vc_src-${name}_"*.wav 2>/dev/null | head -1)
  [ -f "$vcw" ] || { echo "skip  $name (no output)"; skip=$((skip+1)); continue; }
  if post "$vcw" "$out"; then echo "ok    $name"; ok=$((ok+1)); else echo "skip  $name (post failed)"; skip=$((skip+1)); fi
done

echo "----------------------------------------"
echo "done: $ok ok, $skip skipped -> $ROOT/audio/$VOICE/"
if [ "$ok" -eq 0 ]; then
  echo "########################################"
  echo "# NO AUDIO WAS PRODUCED — the app will #"
  echo "# stay silent. Fix the errors above.   #"
  echo "########################################"
  exit 1
fi
