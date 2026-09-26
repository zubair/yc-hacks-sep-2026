# Handoff: production renders

**Status:** Implemented on branch `claude/vigilant-hypatia-r7k61c`. This is a self-contained tool under `renders/`. It changes no app, backend or package code.

**What it does:** Renders production screen art, transparent animation layers, Blender/Cycles device stills, and an open → seal animation. Everything comes from one data file (`renders/data/*.json`), so the user details are templated.

**Commands and results (this container: 4 CPU cores, Blender 4.5.14 LTS, Chromium 141)**
- `npm test`: 5 tests pass (defaults, interpolation, locale postmark dates, validation, geometry).
- `node render.mjs screens`: all 5 screens and 8 layers rendered in about 40 s.
- `blender … --quality draft`: 4 stills rendered in about 80 s. `preview` stills and the animation run in the background, and their samples are committed as they finish.

**For Barrat and Pranav:** `out/<id>/layers/` has the stamp, postmark and handwriting layers as separate transparent PNGs for the seal animation. Colours match the tokens in `docs/PRODUCT.md` (cream paper, deep green ink, vermilion).

**Integration:** No action is required. The `renders/` path is unowned in `docs/OWNERSHIP.md`, so the integration agent may move it under `design/` if preferred.

**Known limits:**
- The device is fictional and unbranded, and it is not a verified model of any real Duo hardware.
- `final` quality needs a GPU to finish in reasonable time.
