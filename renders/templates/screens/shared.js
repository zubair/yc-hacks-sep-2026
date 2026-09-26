// Shared builders for Postcard screen templates. Classic script (not a module)
// so templates also work from file:// URLs. The renderer injects
// window.__POSTCARD__ = { data, geo, photoURL } before any page script runs.
(function () {
  const NS = 'http://www.w3.org/2000/svg';
  let uid = 0;
  const nextId = (p) => `${p}${++uid}`;
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  const INKS = {
    ink: { color: '#23241f', opacity: 0.82 },
    vermilion: { color: '#b8402a', opacity: 0.9 },
  };

  // Deterministic PRNG so every render of the same data is pixel-identical.
  function rng(seed) {
    let s = seed >>> 0 || 1;
    return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
  }
  function hash(str) {
    let h = 2166136261;
    for (const ch of String(str)) h = Math.imul(h ^ ch.codePointAt(0), 16777619);
    return h >>> 0;
  }

  function grainURI() {
    const svg = `<svg xmlns="${NS}" width="480" height="480"><filter id="g"><feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="3" seed="7" stitchTiles="stitch"/><feColorMatrix values="0 0 0 0 0.42  0 0 0 0 0.36  0 0 0 0 0.27  0 0 0 0.55 0"/></filter><rect width="100%" height="100%" filter="url(#g)"/><filter id="f"><feTurbulence type="fractalNoise" baseFrequency="0.012 0.2" numOctaves="2" seed="3" stitchTiles="stitch"/><feColorMatrix values="0 0 0 0 0.5  0 0 0 0 0.43  0 0 0 0 0.33  0 0 0 0.16 -0.05"/></filter><rect width="100%" height="100%" filter="url(#f)"/></svg>`;
    return `url("data:image/svg+xml;utf8,${encodeURIComponent(svg)}")`;
  }

  async function imageSize(url) {
    const img = new Image();
    img.src = url;
    await img.decode();
    return { w: img.naturalWidth, h: img.naturalHeight };
  }

  // object-fit: cover with an arbitrary focal point, in SVG user units.
  function coverRect(nat, box, focus) {
    const s = Math.max(box.w / nat.w, box.h / nat.h);
    const w = nat.w * s;
    const h = nat.h * s;
    const x = box.x - (w - box.w) * focus[0];
    const y = box.y - (h - box.h) * focus[1];
    return { x, y, w, h };
  }

  function perforationMask(id, w, h, r, pitch) {
    const holes = [];
    const along = (len) => {
      const n = Math.max(2, Math.round(len / pitch));
      const step = len / n;
      return Array.from({ length: n + 1 }, (_, i) => i * step);
    };
    for (const x of along(w)) holes.push([x, 0], [x, h]);
    for (const y of along(h)) holes.push([0, y], [w, y]);
    return `<mask id="${id}" maskUnits="userSpaceOnUse" x="-10" y="-10" width="${w + 20}" height="${h + 20}"><rect width="${w}" height="${h}" fill="#fff"/>${holes
      .map(([x, y]) => `<circle cx="${x.toFixed(2)}" cy="${y.toFixed(2)}" r="${r}" fill="#000"/>`)
      .join('')}</mask>`;
  }

  // A perforated postage stamp that reuses the card's own photograph.
  // tone: 'color' (printed photo stamp) or 'vermilion' (single-ink engraving).
  function stampSVG({ w, h, photoURL, nat, focus, country, value, tone = 'color' }) {
    const mask = nextId('perf');
    const clip = nextId('clip');
    const duo = nextId('duo');
    const border = Math.round(w * 0.075);
    const inner = { x: border, y: border, w: w - 2 * border, h: h - 2 * border };
    const img = coverRect(nat, inner, focus);
    const fs = Math.max(10, Math.round(w * 0.1));
    const paper = tone === 'vermilion' ? '#f7e9dc' : '#fbf8f1';
    const textFill = tone === 'vermilion' ? '#fbeee3' : '#ffffff';
    const duoFilter =
      tone === 'vermilion'
        ? `<filter id="${duo}" color-interpolation-filters="sRGB"><feColorMatrix type="saturate" values="0"/><feComponentTransfer><feFuncR type="table" tableValues="0.52 0.80 0.93 0.99"/><feFuncG type="table" tableValues="0.17 0.36 0.62 0.90"/><feFuncB type="table" tableValues="0.11 0.24 0.46 0.82"/></feComponentTransfer></filter>`
        : `<filter id="${duo}" color-interpolation-filters="sRGB"><feColorMatrix type="saturate" values="0.92"/><feComponentTransfer><feFuncR type="linear" slope="0.94" intercept="0.05"/><feFuncG type="linear" slope="0.93" intercept="0.045"/><feFuncB type="linear" slope="0.9" intercept="0.05"/></feComponentTransfer></filter>`;
    return `<svg xmlns="${NS}" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
      <defs>${perforationMask(mask, w, h, w * 0.034, w * 0.105)}<clipPath id="${clip}"><rect x="${inner.x}" y="${inner.y}" width="${inner.w}" height="${inner.h}"/></clipPath>${duoFilter}
        <linearGradient id="${clip}g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000" stop-opacity="0.18"/><stop offset="0.28" stop-color="#000" stop-opacity="0"/><stop offset="0.75" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.22"/></linearGradient></defs>
      <g mask="url(#${mask})">
        <rect width="${w}" height="${h}" fill="${paper}"/>
        <g clip-path="url(#${clip})">
          <image href="${esc(photoURL)}" x="${img.x}" y="${img.y}" width="${img.w}" height="${img.h}" preserveAspectRatio="none" filter="url(#${duo})"/>
          <rect x="${inner.x}" y="${inner.y}" width="${inner.w}" height="${inner.h}" fill="url(#${clip}g)"/>
        </g>
        <rect x="${inner.x + 0.5}" y="${inner.y + 0.5}" width="${inner.w - 1}" height="${inner.h - 1}" fill="none" stroke="rgba(0,0,0,0.12)"/>
        <text x="${inner.x + fs * 0.55}" y="${inner.y + fs * 1.35}" font-family="Jost" font-weight="560" font-size="${fs}" letter-spacing="${fs * 0.06}" fill="${textFill}" style="paint-order:stroke" stroke="rgba(0,0,0,0.18)" stroke-width="${fs * 0.08}">${esc(country)}</text>
        <text x="${inner.x + inner.w - fs * 0.5}" y="${inner.y + inner.h - fs * 0.6}" text-anchor="end" font-family="Jost" font-weight="560" font-size="${fs * 1.12}" fill="${textFill}" style="paint-order:stroke" stroke="rgba(0,0,0,0.18)" stroke-width="${fs * 0.08}">${esc(value)}</text>
      </g>
    </svg>`;
  }

  function wavePath(x0, x1, y, amp, wavelength, phase) {
    const pts = [];
    const dir = x1 >= x0 ? 1 : -1;
    for (let x = x0; dir > 0 ? x <= x1 : x >= x1; x += dir * 3) {
      pts.push(`${x.toFixed(1)},${(y + amp * Math.sin(((x - x0) / wavelength) * Math.PI * 2 + phase)).toFixed(2)}`);
    }
    return `M${pts.join(' L')}`;
  }

  function heartPath(cx, cy, s) {
    return `M${cx},${cy + s * 0.9} C${cx - s * 1.4},${cy - s * 0.05} ${cx - s * 0.75},${cy - s * 1.05} ${cx},${cy - s * 0.35} C${cx + s * 0.75},${cy - s * 1.05} ${cx + s * 1.4},${cy - s * 0.05} ${cx},${cy + s * 0.9} Z`;
  }

  // A hand-cancel postmark: double ring, arc text, centre lines, wavy bars.
  // waves: 'left' | 'right' | 'none'. center: array of lines. heart: bool.
  function postmarkSVG({ r = 86, top = '', bottom = '', center = [], ink = 'ink', waves = 'right', waveLength = 240, heart = false, seed = 1, rotate = -8 }) {
    const color = INKS[ink] ?? INKS.ink;
    const rand = rng(seed + hash(top + bottom + center.join('|')));
    const pad = 8;
    const waveSpan = waves === 'none' ? 0 : waveLength;
    const W = 2 * r + waveSpan + 2 * pad;
    const H = 2 * r + 2 * pad;
    const cx = waves === 'left' ? pad + waveSpan + r : pad + r;
    const cy = pad + r;
    const inner = r * 0.62;
    const band = (r + inner) / 2;
    const fs = r * 0.165;
    const cap = fs * 0.7;
    const topId = nextId('arcT');
    const botId = nextId('arcB');
    const worn = nextId('worn');
    const fade = nextId('fade');
    const tR = band - cap / 2;
    const bR = band + cap / 2;
    const arcTop = `M${cx - tR},${cy} A${tR},${tR} 0 0 1 ${cx + tR},${cy}`;
    const arcBot = `M${cx - bR},${cy} A${bR},${bR} 0 0 0 ${cx + bR},${cy}`;

    let bars = '';
    if (waves !== 'none') {
      const n = 5;
      const gap = r * 0.2;
      const x0 = waves === 'left' ? cx - r * 0.72 : cx + r * 0.72;
      const x1 = waves === 'left' ? cx - r - waveSpan : cx + r + waveSpan;
      for (let i = 0; i < n; i++) {
        const y = cy - ((n - 1) / 2) * gap + i * gap;
        bars += `<path d="${wavePath(x0, x1, y, r * 0.055, r * 0.62, rand() * 0.6)}" fill="none" stroke-width="${r * 0.034}" stroke-linecap="round"/>`;
      }
    }

    const lines = center.filter(Boolean);
    const lineGap = r * 0.2;
    const centerText = lines
      .map((t, i) => {
        const primary = i === Math.floor((lines.length - 1) / 2) && lines.length !== 2;
        const size = primary ? r * 0.19 : r * 0.13;
        const y = cy + (i - (lines.length - 1) / 2) * lineGap + size * 0.36 - (heart ? r * 0.1 : 0);
        return `<text x="${cx}" y="${y.toFixed(1)}" text-anchor="middle" font-family="Jost" font-weight="${primary ? 560 : 520}" font-size="${size.toFixed(1)}" letter-spacing="${(size * 0.08).toFixed(1)}" stroke="none">${esc(t)}</text>`;
      })
      .join('');
    const heartMark = heart ? `<path d="${heartPath(cx, cy + r * 0.33, r * 0.085)}" stroke="none"/>` : '';

    return `<svg xmlns="${NS}" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" style="transform:rotate(${rotate}deg)">
      <defs>
        <path id="${topId}" d="${arcTop}"/><path id="${botId}" d="${arcBot}"/>
        <filter id="${worn}" x="-5%" y="-5%" width="110%" height="110%">
          <feTurbulence type="fractalNoise" baseFrequency="0.75" numOctaves="2" seed="${seed}" result="n"/>
          <feColorMatrix in="n" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 -3.2 2.45" result="holes"/>
          <feComposite in="SourceGraphic" in2="holes" operator="in" result="w"/>
          <feTurbulence type="fractalNoise" baseFrequency="0.05" numOctaves="2" seed="${seed + 3}" result="d"/>
          <feDisplacementMap in="w" in2="d" scale="${(r * 0.03).toFixed(2)}" xChannelSelector="R" yChannelSelector="G"/>
        </filter>
        <linearGradient id="${fade}" x1="${rand() * 0.3}" y1="0" x2="1" y2="${0.6 + rand() * 0.4}"><stop offset="0" stop-color="#fff" stop-opacity="1"/><stop offset="1" stop-color="#fff" stop-opacity="0.55"/></linearGradient>
        <mask id="${fade}m"><rect width="${W}" height="${H}" fill="url(#${fade})"/></mask>
      </defs>
      <g filter="url(#${worn})" mask="url(#${fade}m)" fill="${color.color}" stroke="${color.color}" opacity="${color.opacity}">
        <circle cx="${cx}" cy="${cy}" r="${r - r * 0.025}" fill="none" stroke-width="${r * 0.042}"/>
        <circle cx="${cx}" cy="${cy}" r="${inner}" fill="none" stroke-width="${r * 0.022}"/>
        <text font-family="Jost" font-weight="560" font-size="${fs.toFixed(1)}" letter-spacing="${(fs * 0.16).toFixed(1)}" stroke="none"><textPath href="#${topId}" startOffset="50%" text-anchor="middle">${esc(top)}</textPath></text>
        <text font-family="Jost" font-weight="560" font-size="${fs.toFixed(1)}" letter-spacing="${(fs * 0.16).toFixed(1)}" stroke="none"><textPath href="#${botId}" startOffset="50%" text-anchor="middle">${esc(bottom)}</textPath></text>
        ${centerText}${heartMark}${bars}
      </g>
    </svg>`;
  }

  function arrowSVG(color = 'currentColor') {
    return `<svg class="arrow" viewBox="0 0 26 14"><path d="M0 7 H24 M18 1 L25 7 L18 13" fill="none" stroke="${color}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  }

  function pencilSVG() {
    return `<svg width="30" height="30" viewBox="0 0 30 30"><path d="M5 25 L7 18 L20 5 L25 10 L12 23 Z M7 18 L12 23 M17 8 L22 13" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/></svg>`;
  }

  // Shrinks font-size until the element fits its own box. Never truncates.
  function fitText(el, { max, min }) {
    let size = max;
    el.style.fontSize = `${size}px`;
    while (size > min && (el.scrollHeight > el.clientHeight + 1 || el.scrollWidth > el.clientWidth + 1)) {
      size -= 1;
      el.style.fontSize = `${size}px`;
    }
    if (el.scrollHeight > el.clientHeight + 1) {
      el.style.overflow = 'visible';
      el.dataset.overflow = 'true';
      console.warn(`text does not fit at ${min}px: ${el.textContent.slice(0, 40)}…`);
    }
    return size;
  }

  // Positions a postmark element so its ring is centred on (cx, cy).
  function placePostmark(el, { cx, cy, r, waves = 'right', waveLength = 240 }) {
    const pad = 8;
    const left = waves === 'left' ? cx - r - waveLength - pad : cx - r - pad;
    el.style.left = `${left}px`;
    el.style.top = `${cy - r - pad}px`;
    el.style.right = 'auto';
  }

  function set(root, sel, text) {
    root.querySelectorAll(sel).forEach((n) => (n.textContent = text));
  }

  async function boot(render) {
    const ctx = window.__POSTCARD__;
    if (!ctx) {
      document.body.innerHTML = '<p style="font:16px sans-serif;padding:24px">Render through <code>node render.mjs screens</code>; this template needs injected data.</p>';
      return;
    }
    document.documentElement.style.setProperty('--grain', grainURI());
    document.documentElement.style.setProperty('--hand', `'${ctx.data.theme.handwriting}', cursive`);
    const nat = await imageSize(ctx.photoURL);
    try {
      await document.fonts.load('20px Newsreader');
      await document.fonts.load('italic 20px Newsreader');
      await document.fonts.load('20px Jost');
      await document.fonts.load(`20px ${ctx.data.theme.handwriting}`);
      await render({ ...ctx, nat });
      await document.fonts.ready;
      await Promise.all([...document.images].map((i) => i.decode().catch(() => {})));
      window.__READY__ = true;
    } catch (err) {
      window.__ERROR__ = String(err && err.stack ? err.stack : err);
      throw err;
    }
  }

  window.PC = { placePostmark, stampSVG, postmarkSVG, arrowSVG, pencilSVG, fitText, set, boot, esc, grainURI };
})();
