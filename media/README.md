# Houra README media

Turns real screen recordings into the calm, monochrome GIFs used in `../README.md`.

1. `npm install` (once). Remotion fetches its own headless Chromium on first render;
   to use a local one instead: `REMOTION_BROWSER=/usr/bin/brave node render.mjs`.
2. `zsh record/make_media.sh` records every scenario from the running plugin on sample data
   into `public/clips/<name>.mp4`, takes the panel screenshots and renders the GIFs
   (needs `wf-recorder` and `ydotool`; see the header of the script for its screen assumptions).
3. Edit `scenes.json`: one entry per GIF (`flow`, `widgets`, `snap`, `rest`, `stats`).
   `trim` picks the clip range; `camera` keyframes are crop rectangles in source pixels,
   timed in seconds from the trim start, eased in-out between them. Keep each rect's w/h
   close to the frame's aspect. `captions` are optional; `fade: false` disables the 0.4 s fades;
   `gif` overrides `fps` (12) and palette `colors` (192).
4. Preview with `npx remotion studio src/index.ts`.
5. Render: `node render.mjs` (all) or `node render.mjs flow snap`.
   MP4s land in `out/`, GIFs in `../assets/<name>.gif`, with their size printed.
