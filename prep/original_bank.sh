#!/usr/bin/env bash
# Build the "original" voice bank: your clips' real audio, untouched except
# loudness-matching so it sits at the same level as converted banks.
#
#   ./prep/original_bank.sh <clips-dir> [bank-name]
#
# Output: audio/<bank-name>/<clip>.opus (default bank: "original"). Like every
# audio bank this is personal media — gitignored, never committed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIPS="${1:-}"
BANK="${2:-original}"
die() { echo "ERROR: $*" >&2; exit 1; }
[ -n "$CLIPS" ] && [ -d "$CLIPS" ] || die "usage: $0 <clips-dir> [bank-name]"
command -v ffmpeg >/dev/null || die "ffmpeg missing — brew install ffmpeg"
( cd "$ROOT" && git check-ignore -q "audio/$BANK/probe.opus" ) \
  || die "audio/ is not gitignored — refusing to write media"
mkdir -p "$ROOT/audio/$BANK"
WORK="${TMPDIR:-/tmp}/rc-avatars-original"; mkdir -p "$WORK"
ok=0; skip=0
shopt -s nullglob
for f in "$CLIPS"/*.webm "$CLIPS"/*.mp4 "$CLIPS"/*.mov "$CLIPS"/*.m4a "$CLIPS"/*.mp3 "$CLIPS"/*.wav; do
  name=$(basename "$f"); name="${name%.*}"
  out="$ROOT/audio/$BANK/$name.opus"
  [ -f "$out" ] && { echo "have  $name"; ok=$((ok+1)); continue; }
  ffmpeg -hide_banner -nostats -y -i "$f" -vn -af "loudnorm=I=-16:TP=-1.5:print_format=json" -f null - 2>&1 \
    | sed -n '/^{/,/^}/p' > "$WORK/ln.json" || { echo "skip  $name"; skip=$((skip+1)); continue; }
  ARGS=$(LN_JSON="$WORK/ln.json" python3 - 2>/dev/null <<'PY'
import json, os
d = json.load(open(os.environ["LN_JSON"]))
print(f"measured_I={d['input_i']}:measured_TP={d['input_tp']}:"
      f"measured_LRA={d['input_lra']}:measured_thresh={d['input_thresh']}")
PY
) || { echo "skip  $name"; skip=$((skip+1)); continue; }
  if ffmpeg -y -v error -i "$f" -vn -af "loudnorm=I=-16:TP=-1.5:linear=true:$ARGS" \
       -ar 48000 -c:a libopus -b:a 96k "$out"; then
    echo "ok    $name"; ok=$((ok+1))
  else
    echo "skip  $name"; skip=$((skip+1))
  fi
done
echo "done: $ok ok, $skip skipped -> $ROOT/audio/$BANK/"
[ "$ok" -gt 0 ] || exit 1
