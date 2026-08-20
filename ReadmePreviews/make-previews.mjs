// Render a spinning 3D model into each macOS window mockup's green (#00FF00) area
// and write one looping animated WebP per window into ../assets/.
//
//   cd ReadmePreviews && npm i && npm start
//
// Renderer: headless Google Chrome (already installed) driving <model-viewer>.
// Compositing + WebP: sharp. Nothing here touches the app codebase.

import puppeteer from 'puppeteer-core';
import sharp from 'sharp';
import fsp from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

const HERE = import.meta.dirname;
const MOCKUPS = path.join(HERE, 'mockups');
const EXPORT_DIR = path.resolve(HERE, '../assets');
const MODELS_DIR = path.join(HERE, 'models');
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
// model-viewer bundle, injected into every render page — read once
const MV_SRC = await fsp.readFile(path.join(HERE, 'node_modules/@google/model-viewer/dist/model-viewer.min.js'), 'utf8');

// ---- knobs -------------------------------------------------------------
const FRAMES = 90;            // frames for one full 360° turn (90 @ 30fps = a smooth 3s loop)
const FPS = 30;               // playback rate. 33ms/frame (1000/30) is honoured by every viewer;
                              // delays under 20ms get clamped up to ~100ms (10fps) by some of them.
                              // (FRAMES + FPS identical across windows => same spin speed everywhere.)
const MAX_WIDTH = 1200;       // downscale the final WebP to this width (file-size lever)
const WEBP_QUALITY = 54;      // 0..100 (file-size / quality lever)
const DILATE = 3;             // grow the fill this many mockup px past the green edge, so the
                              // anti-aliased green/chrome boundary is covered (no dark seam lines)
const ORBIT = (deg) => `${deg}deg 75deg 105%`;  // theta, polar, radius (105% = a little padding)

// One model per green-masked window. Swap `model` for any local file in models/,
// or any Khronos glTF-Sample-Assets name (auto-downloaded if missing).
const JOBS = [
  { mockup: 'app_window.png',          model: 'DamagedHelmet', out: 'app_window.webp' },
  { mockup: 'finder_details_pane.png', model: 'BoomBox',       out: 'finder_details_pane.webp' },
  { mockup: 'quick_look.png',          model: 'Lantern',       out: 'quick_look.webp' },
];

// print a file's size in KB (used by the export log lines)
const kb = async (file) => ((await fsp.stat(file)).size / 1024).toFixed(0);

// ---- source models -----------------------------------------------------
async function modelPath(name) {
  if (name.endsWith('.glb') || name.endsWith('.gltf')) {   // treat as a path the user provided
    const p = path.isAbsolute(name) ? name : path.join(MODELS_DIR, name);
    if (!existsSync(p)) throw new Error(`model not found: ${p}`);
    return p;
  }
  await fsp.mkdir(MODELS_DIR, { recursive: true });
  const p = path.join(MODELS_DIR, `${name}.glb`);
  if (existsSync(p)) return p;
  const url = `https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/${name}/glTF-Binary/${name}.glb`;
  process.stdout.write(`  downloading ${name}.glb … `);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`download failed (${res.status}) for ${url}`);
  await fsp.writeFile(p, Buffer.from(await res.arrayBuffer()));
  console.log('done');
  return p;
}

// Grow a binary mask outward by `r` px (separable square dilation).
function dilate(mask, W, H, r) {
  const h = new Uint8Array(W * H);
  for (let y = 0; y < H; y++) {
    const row = y * W;
    for (let x = 0; x < W; x++) {
      let on = 0;
      for (let k = -r; k <= r && !on; k++) { const xx = x + k; if (xx >= 0 && xx < W && mask[row + xx]) on = 1; }
      h[row + x] = on;
    }
  }
  const out = new Uint8Array(W * H);
  for (let x = 0; x < W; x++) {
    for (let y = 0; y < H; y++) {
      let on = 0;
      for (let k = -r; k <= r && !on; k++) { const yy = y + k; if (yy >= 0 && yy < H && h[yy * W + x]) on = 1; }
      out[y * W + x] = on;
    }
  }
  return out;
}

// ---- green mask --------------------------------------------------------
// Returns the base mockup pixels, a dilated per-pixel fill mask, and the tight
// bbox of the big green rectangle (small tag-colour swatches are rejected).
async function greenMask(mockupFile) {
  const { data, info } = await sharp(mockupFile).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const { width: W, height: H } = info;                    // channels === 4
  const mask = new Uint8Array(W * H);
  const colSum = new Int32Array(W);
  const rowSum = new Int32Array(H);
  for (let y = 0, i = 0; y < H; y++) {
    for (let x = 0; x < W; x++, i++) {
      const p = i * 4, r = data[p], g = data[p + 1], b = data[p + 2];
      if (g > 180 && r < 150 && b < 150 && g - r > 60 && g - b > 60) {
        mask[i] = 1; colSum[x]++; rowSum[y]++;
      }
    }
  }
  let x0 = W, x1 = -1, y0 = H, y1 = -1;
  for (let x = 0; x < W; x++) if (colSum[x] > H * 0.25) { if (x < x0) x0 = x; if (x > x1) x1 = x; }
  for (let y = 0; y < H; y++) if (rowSum[y] > W * 0.15) { if (y < y0) y0 = y; if (y > y1) y1 = y; }
  if (x1 < 0 || y1 < 0) throw new Error(`no green mask found in ${mockupFile}`);
  // Dilate so the anti-aliased green→chrome edge (a thin darker ring just outside the
  // strict-green pixels) gets painted over instead of left as a dark seam line.
  const fill = dilate(mask, W, H, DILATE);
  return { W, H, base: data, fill, bbox: { x0, y0, w: x1 - x0 + 1, h: y1 - y0 + 1 } };
}

// ---- turntable frames (transparent PNG buffers, sized to the mask bbox) -
async function renderFrames(browser, glbPath, w, h) {
  const page = await browser.newPage();
  await page.setViewport({ width: w, height: h, deviceScaleFactor: 1 });
  const dataUrl = 'data:model/gltf-binary;base64,' + (await fsp.readFile(glbPath)).toString('base64');
  await page.setContent(
    `<!doctype html><meta charset=utf8>
     <style>html,body{margin:0;background:transparent}
       model-viewer{width:${w}px;height:${h}px;background:transparent;--progress-bar-color:transparent}
       /* hide the loading progress bar — it fades out after 'load' and would otherwise
          leave a thin line across the top of the first few captured frames */
       model-viewer::part(default-progress-bar){display:none}</style>
     <model-viewer id=mv shadow-intensity="0" exposure="1"
       disable-zoom interaction-prompt="none" camera-orbit="${ORBIT(0)}"></model-viewer>`
  );
  await page.addScriptTag({ content: MV_SRC, type: 'module' });
  await page.evaluate(async (src) => {
    await customElements.whenDefined('model-viewer');
    const mv = document.getElementById('mv');
    mv.src = src;
    await new Promise((res, rej) => {
      mv.addEventListener('load', res, { once: true });
      mv.addEventListener('error', () => rej(new Error('model-viewer failed to load model')), { once: true });
      setTimeout(() => rej(new Error('model load timed out')), 60000);
    });
    mv.interpolationDecay = 0;                  // camera jumps instantly, no tweening between frames
    await new Promise((r) => setTimeout(r, 200)); // let any load-time UI settle before the first capture
  }, dataUrl);

  const frames = [];
  for (let i = 0; i < FRAMES; i++) {
    await page.evaluate(async (orbit) => {
      const mv = document.getElementById('mv');
      mv.cameraOrbit = orbit;
      mv.jumpCameraToGoal();
      await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
    }, ORBIT((i / FRAMES) * 360));
    frames.push(await page.screenshot({ omitBackground: true, type: 'png' }));
  }
  await page.close();
  return frames;
}

// ---- composite frames into the mockup, encode one animated WebP --------
async function build(job, browser) {
  const mockupFile = path.join(MOCKUPS, job.mockup);
  const { W, H, base, fill, bbox } = await greenMask(mockupFile);
  console.log(`  green area ${bbox.w}×${bbox.h} at (${bbox.x0},${bbox.y0})`);

  // Render a little larger than the green rect and offset it, so the dilated fill mask
  // always samples real (white-margin) model pixels — never runs off the frame edge.
  const rx0 = Math.max(0, bbox.x0 - DILATE);
  const ry0 = Math.max(0, bbox.y0 - DILATE);
  const rw = Math.min(W, bbox.x0 + bbox.w + DILATE) - rx0;
  const rh = Math.min(H, bbox.y0 + bbox.h + DILATE) - ry0;

  const glb = await modelPath(job.model);
  const frames = await renderFrames(browser, glb, rw, rh);

  const scale = Math.min(1, MAX_WIDTH / W);
  const outW = Math.round(W * scale);
  let outH = 0;
  const pages = [];
  // scratch canvas reused across frames: every frame overwrites exactly the fill-mask
  // pixels and touches nothing else, so the untouched pixels always stay == base.
  const full = Buffer.from(base);
  for (const png of frames) {
    // model on white (the viewport colour), raw RGBA at the render-rect size
    const { data: fr } = await sharp(png).flatten({ background: '#ffffff' }).ensureAlpha()
      .raw().toBuffer({ resolveWithObject: true });
    // overwrite only the (dilated) fill-mask pixels
    for (let y = 0; y < rh; y++) {
      const my = ry0 + y;
      for (let x = 0; x < rw; x++) {
        const mx = rx0 + x;
        if (!fill[my * W + mx]) continue;
        const di = (my * W + mx) * 4, si = (y * rw + x) * 4;
        full[di] = fr[si]; full[di + 1] = fr[si + 1]; full[di + 2] = fr[si + 2]; full[di + 3] = 255;
      }
    }
    // downscale this frame now so the stacked buffer stays small
    const { data: small, info } = await sharp(full, { raw: { width: W, height: H, channels: 4 } })
      .resize({ width: outW }).raw().toBuffer({ resolveWithObject: true });
    outH = info.height;
    pages.push(small);
  }

  const outFile = path.join(EXPORT_DIR, job.out);
  await sharp(Buffer.concat(pages), { raw: { width: outW, height: outH * pages.length, channels: 4, pageHeight: outH } })
    // delay must be a per-frame array — a single number only sets frame 0, leaving the
    // rest at libwebp's 100ms default (that was the ~10fps stutter).
    .webp({ quality: WEBP_QUALITY, loop: 0, delay: Array(pages.length).fill(Math.round(1000 / FPS)), effort: 4, smartSubsample: true })
    .toFile(outFile);
  console.log(`  → ${path.relative(process.cwd(), outFile)}  (${outW}×${outH}, ${await kb(outFile)} KB)\n`);
}

// ---- main --------------------------------------------------------------
if (!existsSync(CHROME)) {
  console.error(`Google Chrome not found at:\n  ${CHROME}\nInstall Chrome or edit CHROME in this file.`);
  process.exit(1);
}
await fsp.mkdir(EXPORT_DIR, { recursive: true });
const browser = await puppeteer.launch({ headless: true, executablePath: CHROME });
try {
  for (const job of JOBS) {
    console.log(`${job.mockup}  (${job.model})`);
    await build(job, browser);
  }
} finally {
  await browser.close();
}
console.log(`all previews written to ${path.relative(process.cwd(), EXPORT_DIR)}/`);
