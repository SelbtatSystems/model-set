# Screenshots — capture with agent-browser, annotate with ffmpeg

## Capture

- Always against the Docker containers (login URL and creds in `memory/AgCore/TEST-LOGIN.md` at the repo
  root — resolve it from there, not the current directory), never a dev server.
- `export AGENT_BROWSER_SESSION=docs-loop` before the first command and reuse that one logged-in
  session for the whole run — repeated logins trip the auth throttle (429). Never `close --all`.
- Viewport 1440×900, light theme. Dark theme is checked during verification, not screenshotted.
- Raw shots go to `/tmp/docs-shots/<unit-id>/raw-NN.png`; only processed finals enter the repo.
- Shoot real-looking sample data, not empty states — create data through the UI first if the
  worktree DB is bare. Never capture a TFN, bank detail, or signature field with a value in it.

Before keeping an existing image, recreate the state it claims to show and compare it with the live
surface. A screenshot is stale when its labels, controls, layout, state, density, or visible styling
would make a reader look for the wrong thing. An invisible refactor does not make it stale.

Known traps in this app: re-run `snapshot -i` after any navigation (refs invalidate); div-onClick
cards, hover-revealed buttons, and save buttons low on long settings pages often need DOM
`.click()` via JS eval rather than `click @ref`; the eForm super-fund combobox commits on
ArrowDown+Enter, not click; Mapbox tiles sometimes don't paint in this environment — if a map stays
black, document the surface with the panels/data around it and note the tile issue in the queue row
rather than blocking.

To find pixel coordinates for cropping and annotation, eval
`JSON.stringify(document.querySelector('<sel>').getBoundingClientRect())` in the page and use those
numbers directly (screenshots are taken at CSS-pixel scale).

## Annotate

ImageMagick 6, all verified on this machine. The binary is `convert` (this box has IM6, so there
is no `magick` command). Font: `/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf`.

Everything chains in one command; each `-draw` inherits the `-stroke`/`-fill`/`-strokewidth`
set before it. Coordinates are relative to the image *after* `-crop`.

```bash
convert raw-01.png \
  -crop WxH+X+Y +repage \
  -stroke '#FF0000' -strokewidth 4 -fill none -draw "rectangle x1,y1 x2,y2" \
  -draw "ellipse cx,cy r,r 0,360" \
  -strokewidth 5 -draw "line x1,y1 x2,y2" \
  -fill '#FF0000' -stroke none -draw "polygon tipx,tipy bx1,by1 bx2,by2" \
  -font /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf -pointsize 32 \
  -fill '#FF0000' -annotate +x+y 'Click here' \
  final.png
```

Piece by piece:

- **Crop** — `-crop WxH+X+Y +repage` (never drop the `+repage`; it resets the canvas offset so
  later coordinates behave). Leave ~40 px of breathing room around the region that matters.
- **Highlight box** — `-fill none` first, or the rectangle paints solid over the UI.
- **Circle** — `ellipse cx,cy r,r 0,360` with `-fill none` still active.
- **Arrow** — a line plus a small filled polygon for the head: put the polygon's first point on
  the line's end (the tip), and the two base points ~20 px back, offset ~8 px either side.
- **Label** — `-annotate +x+y` positions the text baseline; single-quote the text.

## Conventions

- Consistent marks everywhere: pure red (#FF0000), box thickness 4, fontsize 28–34, ring ~7 px.
- One idea per image, at most three marks. If you need more, that is two images.
- Numbered walkthroughs: annotate the *next* click, so the reader's screen matches the picture.
- Final name: `NN-<verb-object>.png` (e.g. `02-approve-correction.png`) under
  `apps/<app>/public/docs/<page-slug>/`, referenced as `/docs/<page-slug>/NN-....png`.
- Alt text says what the reader is doing or seeing ("The Clock on button on the kiosk, circled"),
  never "screenshot of...".
- If a shot needs to be bigger or sharper, retake it — never upscale.

Record each final in the selected page's `MAINTENANCE.md` notes: image path, page section, route,
fixture/account state, role, viewport, density, theme, annotation purpose, and verified
`origin/main` commit. Keep the existing filename when the teaching point is unchanged. A new teaching
point gets a new numbered filename.
