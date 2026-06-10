# TODOS

- [ ] **Captions under the avatar** (P3) — show the spoken line as a one-line caption
  below the figure. What: render transcript text in the overlay, synced per track.
  Why: readable interrupts with sound off / on calls. Context: transcripts exist as a
  byproduct of the conversion pipeline (whisper step in seed-vc workflows) or can be
  generated with faster-whisper; needs a small text layout under `#stage` in
  `app/overlay.html` and a `cache/transcripts/` lookup keyed by track name.
  Effort: M (human) / S (CC). Depends on: nothing.
