# Postcard renders

Template-driven production renders for animation and marketing. Enter the card's details once in `data/<card>.json`, and every output is regenerated from them:

| Output | Path (`out/<id>/…`) | Use |
|---|---|---|
| Screen art at native display resolution (3×) | `screens/front.png`, `back.png` (+ `back-left/right.png`), `sealed.png`, `sent.png`, `received.png` | UI animation keyframes, device comps |
| Transparent animation layers | `layers/stamp-*.png`, `postmark-*.png`, `message.png`, `address.png`, `paper.png` | Stamp drop, postmark thump, handwriting write-on |
| Cycles device stills | `stills/00-hero … 05-received.png` | Marketing and title cards |
| Editorial title cards | `editorial/*.png` + `*.overlay.png` (alpha) | "Postcard. 01 / The front" slides |
| Open → seal device take (8 s, 24 fps) | `anim/open-seal/frame_*.png`, `anim/open-seal.mp4`, `anim/open-seal.blend` | Product film |

`samples/cinque-terre/` holds downsized previews of the default card.

## Setup

- Node 20+, then `npm install` (installs `playwright-core` 1.56.1). Set `CHROMIUM_PATH` or run `npx playwright-core install chromium`.
- Blender 4.5 LTS. Set `BLENDER=/path/to/blender` if it is not on your `PATH`.

## Render

```sh
node render.mjs screens  --data data/cinque-terre.json            # ~40 s, no Blender needed
node render.mjs scenes   --data data/cinque-terre.json --quality preview --shots hero,front
node render.mjs anim     --data data/cinque-terre.json --quality preview [--frames 1-192]
node render.mjs overlays --data data/cinque-terre.json
node render.mjs all      --data data/cinque-terre.json --quality final
npm test
```

Quality presets are defined in `blender/scene.py` (`QUALITY`). `draft` is 900×600 at 24 samples, `preview` is 1536×1024 at 96 samples, and `final` is 3072×2048 at 384 samples. On a 4-core CPU, a `preview` still takes a few minutes and a `final` still takes about 30 minutes, so use a GPU machine for `final`. To enable a GPU, set `bpy.context.scene.cycles.device = 'GPU'` in `configure_render`. `--mode blend` saves editable `.blend` files instead of rendering.

## Template fields

Required fields: `id`, `sender.name`, `recipient.name`, `place.name`, `place.country`, `date` (YYYY-MM-DD), `message.body`, and `photo.src` (a path relative to the data file).

All other fields are optional and have sensible defaults:

| Field | Default |
|---|---|
| `locale` | `en-US`; sets the postmark month (`14 MAG 2024` in `it-IT`) |
| `photo.focus` / `photo.stampFocus` | `[0.5, 0.5]`; crop focal point for the card and the stamp |
| `message.salutation` / `message.signoff` | `{recipient},` / `Love, {sender}` |
| `stamp.country` / `stamp.value` | Upper-cased country / `1,20` |
| `postmark.top` / `.bottom` / `.motto` | Place / country / empty |
| `delivery.channel` / `.options` | `Messages` / `[channel]` |
| `copy.*` | Every UI string; `{sender}`, `{recipient}`, `{place}`, `{country}` and `{channel}` are interpolated |
| `theme.handwriting` | `NothingYouCouldDo` (or `Caveat`) |
| `editorial.shots.<shot>` | Title-card kicker and lines |
| `scene.finish` | `champagne`, `titanium` or `graphite` |

Long messages shrink to fit and are never truncated. The renderer warns if a message would still overflow at the minimum size.

## How it fits together

- `device.json` defines the fictional, unbranded dual-screen foldable in millimetres. Templates use 10 CSS px per mm and rasterise at 3×, so screen art lands 1:1 on the modelled displays. When the device is closed, the cover display shows the postcard front in landscape. When it is open, the two inner displays show the back: the message on the left and the address on the right, with the hinge acting as the card's centre line.
- `templates/screens/*.html` are plain HTML/SVG. They include the perforated stamp generated from the card photo, the worn-ink postmark with locale-formatted arc text, and paper grain. Rendering is deterministic.
- `blender/scene.py` builds everything procedurally: the device, the travertine and plaster set, warm sun (AgX) with olive-branch leaf shadows that are only visible in shadows, and depth of field. It downloads nothing.

## Scope notes

- "Printed card" appears in the default `delivery.options` because it matches the design reference. It is not in the v1 scope (see `docs/PRODUCT.md`), so remove it from the data file for v1-accurate material.
- The sent screen says the card is waiting in the recipient's inbox, which means it is stored. It does not claim delivery or a read receipt.
- Fonts are licensed under OFL (`assets/fonts/OFL-*.txt`). The sample photo is CC0 (`assets/photos/CREDITS.md`).
