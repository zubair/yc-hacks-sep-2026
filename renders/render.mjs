#!/usr/bin/env node
// Postcard render pipeline.
//   node render.mjs screens  --data data/cinque-terre.json   flat screen art + animation layers (Chromium)
//   node render.mjs scenes   --data ... [--shots front,back] [--quality draft|final]   Blender/Cycles stills
//   node render.mjs anim     --data ... [--quality draft|final]   open → seal device sequence
//   node render.mjs overlays --data ...                         editorial title cards over the stills
//   node render.mjs all      --data ...
import { mkdir, writeFile, readdir, access } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { loadData, loadDevice, screenGeometry, RENDERS_ROOT } from './lib/data.mjs';

function parseArgs(argv) {
  const [cmd = 'all', ...rest] = argv;
  const opts = { cmd, data: 'data/cinque-terre.json', quality: 'final', shots: null, out: 'out' };
  for (let i = 0; i < rest.length; i++) {
    const k = rest[i].replace(/^--/, '');
    opts[k] = rest[i + 1];
    i++;
  }
  return opts;
}

async function chromium() {
  const { chromium } = await import('playwright-core');
  const candidates = [process.env.CHROMIUM_PATH, '/opt/pw-browsers/chromium-1194/chrome-linux/chrome'].filter(Boolean);
  for (const p of candidates) {
    try {
      await access(p);
      return chromium.launch({ executablePath: p });
    } catch {}
  }
  return chromium.launch(); // uses `npx playwright-core install chromium`
}

async function openTemplate(browser, file, ctx, viewport, scale) {
  const page = await browser.newPage({ viewport, deviceScaleFactor: scale });
  page.on('pageerror', (e) => console.error(`[${file}] ${e.message}`));
  page.on('console', (m) => m.type() === 'warning' && console.warn(`[${file}] ${m.text()}`));
  await page.addInitScript((c) => (window.__POSTCARD__ = c), ctx);
  await page.goto(pathToFileURL(path.join(RENDERS_ROOT, 'templates', file)).href);
  await page.waitForFunction(() => window.__READY__ || window.__ERROR__, null, { timeout: 60000 });
  const err = await page.evaluate(() => window.__ERROR__);
  if (err) throw new Error(`${file}: ${err}`);
  return page;
}

export async function renderScreens(data, device, outDir) {
  const geo = screenGeometry(device);
  const dir = path.join(outDir, 'screens');
  const layers = path.join(outDir, 'layers');
  await mkdir(dir, { recursive: true });
  await mkdir(layers, { recursive: true });
  const ctx = { data, geo, photoURL: pathToFileURL(data.photo.src).href };
  const browser = await chromium();
  const written = {};
  try {
    const cover = { width: geo.cover.width, height: geo.cover.height };
    for (const [name, file, mode] of [
      ['front', 'screens/front.html'],
      ['received', 'screens/front.html', 'received'],
      ['sealed', 'screens/sealed.html'],
      ['sent', 'screens/sent.html'],
    ]) {
      const page = await openTemplate(browser, file, { ...ctx, mode }, cover, geo.scale);
      written[name] = path.join(dir, `${name}.png`);
      await page.screenshot({ path: written[name] });
      await page.close();
    }
    const spread = { width: geo.spread.width, height: geo.spread.height };
    const page = await openTemplate(browser, 'screens/back.html', ctx, spread, geo.scale);
    written.back = path.join(dir, 'back.png');
    written.backLeft = path.join(dir, 'back-left.png');
    written.backRight = path.join(dir, 'back-right.png');
    await page.screenshot({ path: written.back });
    await page.screenshot({ path: written.backLeft, clip: { x: 0, y: 0, width: geo.pane.width, height: geo.pane.height } });
    await page.screenshot({ path: written.backRight, clip: { x: geo.pane.width + geo.spread.gap, y: 0, width: geo.pane.width, height: geo.pane.height } });
    await page.close();

    const lp = await openTemplate(browser, 'screens/layers.html', ctx, { width: 1400, height: 900 }, geo.scale);
    for (const id of ['stamp-color', 'stamp-vermilion', 'postmark-ink', 'postmark-vermilion', 'postmark-sealed', 'message', 'address', 'paper']) {
      await lp.locator(`#${id}`).screenshot({ path: path.join(layers, `${id}.png`), omitBackground: id !== 'paper' });
    }
    await lp.close();
  } finally {
    await browser.close();
  }
  const manifest = { data, device, geometry: geo, screens: written, layersDir: layers };
  await writeFile(path.join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2));
  console.log(`screens → ${dir}\nlayers  → ${layers}`);
  return manifest;
}

function blenderBin() {
  return process.env.BLENDER || 'blender';
}

function run(cmd, args) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { stdio: 'inherit' });
    p.on('error', reject);
    p.on('exit', (code) => (code === 0 ? resolve() : reject(new Error(`${cmd} exited ${code}`))));
  });
}

async function renderBlender(outDir, mode, opts) {
  const args = ['--background', '--factory-startup', '--python', path.join(RENDERS_ROOT, 'blender', 'scene.py'), '--',
    '--manifest', path.join(outDir, 'manifest.json'), '--mode', mode, '--quality', opts.quality];
  if (opts.shots) args.push('--shots', opts.shots);
  if (opts.frames) args.push('--frames', opts.frames);
  await run(blenderBin(), args);
}

async function renderOverlays(data, outDir) {
  const stills = path.join(outDir, 'stills');
  const dest = path.join(outDir, 'editorial');
  await mkdir(dest, { recursive: true });
  const files = (await readdir(stills)).filter((f) => f.endsWith('.png'));
  const browser = await chromium();
  try {
    for (const f of files) {
      const shot = f.replace(/\.png$/, '').replace(/^\d+-/, '');
      const ed = data.editorial.shots[shot];
      if (!ed) continue;
      const ctx = { data, shot, ed, background: pathToFileURL(path.join(stills, f)).href };
      const page = await openTemplate(browser, 'overlays/editorial.html', { ...ctx, geo: null, photoURL: pathToFileURL(data.photo.src).href }, { width: 1536, height: 1024 }, 2);
      await page.screenshot({ path: path.join(dest, f) });
      await page.evaluate(() => document.body.classList.add('overlay-only'));
      await page.screenshot({ path: path.join(dest, f.replace('.png', '.overlay.png')), omitBackground: true });
      await page.close();
    }
  } finally {
    await browser.close();
  }
  console.log(`editorial → ${dest}`);
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const data = await loadData(path.resolve(opts.data));
  const device = await loadDevice();
  const outDir = path.resolve(RENDERS_ROOT, opts.out, data.id);
  await mkdir(outDir, { recursive: true });
  const need = (step) => opts.cmd === step || opts.cmd === 'all';
  if (need('screens')) await renderScreens(data, device, outDir);
  if (need('scenes')) await renderBlender(outDir, 'stills', opts);
  if (need('anim')) await renderBlender(outDir, 'anim', opts);
  if (need('overlays')) await renderOverlays(data, outDir);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}
