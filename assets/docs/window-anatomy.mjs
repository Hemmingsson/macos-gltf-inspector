// Renders window-anatomy.json to window-anatomy.svg: node window-anatomy.mjs window-anatomy.json window-anatomy.svg
import fs from 'node:fs';
const [, , inPath, outPath] = process.argv;
const S = JSON.parse(fs.readFileSync(inPath, 'utf8'));
const out = [];
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
const el = (t, a, body) => { const at = Object.entries(a).filter(([, v]) => v != null).map(([k, v]) => `${k}="${v}"`).join(' '); out.push(body == null ? `<${t} ${at}/>` : `<${t} ${at}>${body}</${t}>`); };
const tx = (x, y, s, c = 'dt', a = {}) => el('text', { x, y, class: c, ...a }, esc(s));

const WW = S.window.w, WH = S.window.h;
const OX = 130, OY = 170;
const X = v => OX + v, Y = v => OY + v;
const SW = S.sidebar.w, IW = S.inspector.w, CL = SW, CR = WW - IW, CC = (CL + CR) / 2;
const TB = S.titleBar.h, CY = S.titleBar.centreY;
const C = S.canvas, IS = C.island, IN = C.inset;

const KEY_Y = OY + WH + 70;
const TOTAL_W = OX + WW + 60, TOTAL_H = KEY_Y + 170;

// helpers
const badges = [];
const badge = (n, x, y) => badges.push([n, x, y]);
function hdim(x1, x2, y, label, ext = 0, extTo) { // horizontal dimension (window coords)
  el('line', { x1: X(x1), y1: Y(y), x2: X(x2), y2: Y(y), class: 'dim' });
  for (const x of [x1, x2]) {
    el('line', { x1: X(x) , y1: Y(y) - 4, x2: X(x), y2: Y(y) + 4, class: 'dim' });
    if (extTo != null) el('line', { x1: X(x), y1: Y(y), x2: X(x), y2: Y(extTo), class: 'ext' });
  }
  tx(X((x1 + x2) / 2), Y(y) - 4 + ext, label, 'dv', { 'text-anchor': 'middle' });
}
function vdim(y1, y2, x, label, side = -1, extTo) {
  el('line', { x1: X(x), y1: Y(y1), x2: X(x), y2: Y(y2), class: 'dim' });
  for (const y of [y1, y2]) {
    el('line', { x1: X(x) - 4, y1: Y(y), x2: X(x) + 4, y2: Y(y), class: 'dim' });
    if (extTo != null) el('line', { x1: X(x), y1: Y(y), x2: X(extTo), y2: Y(y), class: 'ext' });
  }
  tx(X(x) + side * 6, Y((y1 + y2) / 2) + 3, label, 'dv', { 'text-anchor': side < 0 ? 'end' : 'start' });
}
const slot = (x, y, w, h, label) => { el('rect', { x: X(x), y: Y(y), width: w, height: h, rx: 2, class: 'slot' }); if (label) tx(X(x + w / 2), Y(y + h / 2) + 3, label, 'sl', { 'text-anchor': 'middle' }); };
const bar = (x, y, w, h = 6, c = 'bar') => el('rect', { x: X(x), y: Y(y), width: w, height: h, rx: h / 2, class: c });
const glyph = (x, y, s = 16) => { el('rect', { x: X(x), y: Y(y), width: s, height: s, rx: 3, class: 'hug' }); };
const chev = (x, y) => el('path', { d: `M${X(x) - 3},${Y(y) - 1.5} l3,3 l3,-3`, class: 'thin' });
const eye = (x, y) => { el('path', { d: `M${X(x) - 7},${Y(y)} q7,-7 14,0 q-7,7 -14,0z`, class: 'thin' }); el('circle', { cx: X(x), cy: Y(y), r: 2, class: 'dot' }); };
const header = (x, y, s) => tx(X(x), Y(y), s.toUpperCase(), 'hd');

// page chrome
out.push(`<rect class="bg" x="0" y="0" width="${TOTAL_W}" height="${TOTAL_H}"/>`);
tx(OX, 34, `${S.id} · 1 / 1`, 'eb');
tx(OX, 60, S.title, 'ti');

// ---- canvas (full window) ----
el('clipPath', { id: 'win' }, `<rect x="${X(0)}" y="${Y(0)}" width="${WW}" height="${WH}" rx="${S.window.radius}"/>`);
el('rect', { x: X(0), y: Y(0), width: WW, height: WH, rx: S.window.radius, class: 'canvas' });
out.push(`<g clip-path="url(#win)">`);
el('rect', { x: X(0), y: Y(0), width: WW, height: WH, fill: 'url(#grid)' });
// floor ellipse + model (iso box) centred in visible area
const MX = CC, MY = (TB + WH) / 2 + 10;
el('ellipse', { cx: X(MX), cy: Y(MY + 78), rx: 170, ry: 34, class: 'rel' });
{
  const a = 110, b = 70, h = 70; // iso box
  const p = (dx, dy, dz) => [X(MX + (dx - dy) * 0.866), Y(MY + 40 + (dx + dy) * 0.5 - dz)];
  const P = (...pts) => pts.map(q => q.join(',')).join(' ');
  const A = p(-a / 2, -b / 2, 0), B = p(a / 2, -b / 2, 0), Cc = p(a / 2, b / 2, 0), D = p(-a / 2, b / 2, 0);
  const A2 = p(-a / 2, -b / 2, h), B2 = p(a / 2, -b / 2, h), C2 = p(a / 2, b / 2, h), D2 = p(-a / 2, b / 2, h);
  el('polygon', { points: P(A2, B2, C2, D2), class: 'face1' });
  el('polygon', { points: P(B, Cc, C2, B2), class: 'face2' });
  el('polygon', { points: P(D, Cc, C2, D2), class: 'face3' });
  el('polyline', { points: P(A, B, Cc, D, A), class: 'hidden' });
}
// visible-area centre crosshair
el('line', { x1: X(MX), y1: Y(TB + 8), x2: X(MX), y2: Y(WH - 130), class: 'rel' });
el('line', { x1: X(CL + 24), y1: Y(MY), x2: X(CR - 24), y2: Y(MY), class: 'rel' });
tx(X(CL + 28), Y(MY) - 6, 'VISIBLE-AREA CENTRE', 'dts');
out.push(`</g>`);

// ---- sidebar pane ----
el('rect', { x: X(0), y: Y(0), width: SW, height: WH, class: 'pane', 'clip-path': 'url(#win)' });
el('line', { x1: X(SW), y1: Y(0), x2: X(SW), y2: Y(WH), class: 'edge' });
// file card
{
  const f = S.sidebar.fileCard, x = f.inset, w = SW - 2 * f.inset;
  el('rect', { x: X(x), y: Y(f.y), width: w, height: f.h, rx: 10, class: 'card' });
  el('rect', { x: X(x + 10), y: Y(f.y + 12), width: 30, height: 36, rx: 4, class: 'hug' });
  tx(X(x + 25), Y(f.y + 34), 'GLB', 'sl', { 'text-anchor': 'middle' });
  tx(X(x + 50), Y(f.y + 24), 'BoomBox', 'btn');
  tx(X(x + 50), Y(f.y + 45), 'glTF Binary', 'lab');
  badge(4, x + w - 2, f.y + 2);
}
// scene outliner
{
  const s = S.sidebar.scene;
  const sectionHeaders = s.sectionHeaders ?? ['Scene'];
  header(14, s.headerY, sectionHeaders[1] ?? 'Scene');
  tx(X(SW - 24), Y(s.headerY), 'EYE', 'dts', { 'text-anchor': 'middle' });
  const nameW = [96, 70, 84, 58, 66, 74, 52, 90, 62, 70, 80, 64, 60, 88];
  s.levels.forEach((lv, i) => {
    const y = s.rowY + i * s.rowH, cy = y + s.rowH / 2;
    if (i === s.selected) el('rect', { x: X(8), y: Y(y + 1), width: SW - 16, height: s.rowH - 2, rx: 5, class: 'sel' });
    const ix = 22 + lv * s.indent;
    const next = s.levels[i + 1] ?? -1;
    if (next > lv) chev(ix - 8, cy);
    glyph(ix, cy - 8, s.icon);
    if (i === 0) tx(X(ix + 22), Y(cy) + 4, 'Root', 'btn');
    else bar(ix + 22, cy - 3, nameW[i] - lv * 6);
    eye(SW - 24, cy);
  });
  const extraSections = (s.sectionHeaders ?? []).slice(2);
  extraSections.forEach((name, i) => {
    const y = s.rowY + s.levels.length * s.rowH + 40 + i * 30;
    header(14, y, name);
    bar(22, y + 10, 78 + (i % 2) * 24);
  });
  // indent + icon dims on rows 1→2
  const y1 = s.rowY + 1 * s.rowH, y2 = s.rowY + 2 * s.rowH;
  const lx = 22 + 1 * s.indent, lx2 = 22 + 2 * s.indent;
  el('line', { x1: X(lx), y1: Y(y1 + 4), x2: X(lx), y2: Y(y2 + 22), class: 'ext' });
  el('line', { x1: X(lx2), y1: Y(y2 + 4), x2: X(lx2), y2: Y(y2 + 22), class: 'ext' });
  hdim(lx, lx2, y2 + 22, '');
  tx(X(lx2) + 4, Y(y2 + 22) + 3, 'indent 16', 'dv');
  badge(5, 70, s.headerY - 4);
  const ly = s.rowY + s.levels.length * s.rowH, lx3 = 22 + s.levels.at(-1) * s.indent;
  hdim(lx3, lx3 + s.icon, ly + 14, '', 0, ly - 4);
  tx(X(lx3 + s.icon) + 4, Y(ly + 14) + 3, 'icon 16', 'dv');
}
// validation
{
  const v = S.sidebar.validation;
  el('line', { x1: X(14), y1: Y(v.headerY - 18), x2: X(SW - 14), y2: Y(v.headerY - 18), class: 'sep' });
  header(14, v.headerY, 'Validation');
  tx(X(SW - 14), Y(v.headerY), v.summary ?? '1 error · 2 warnings', 'cnt', { 'text-anchor': 'end' });
  for (let i = 0; i < v.rows; i++) {
    const cy = v.headerY + 22 + i * 26;
    el(i === 2 ? 'circle' : 'path', i === 2 ? { cx: X(30), cy: Y(cy), r: 7, class: 'hug' } : { d: `M${X(30)},${Y(cy) - 7} l7.5,13 h-15z`, class: 'hug' });
    bar(44, cy - 3, [150, 120, 96][i]);
    tx(X(SW - 14), Y(cy) + 3, ['3', '1', '12'][i], 'mono', { 'text-anchor': 'end' });
  }
  badge(6, 98, v.headerY - 4);
}
badge(3, 120, WH - 22);

// ---- inspector pane ----
el('rect', { x: X(CR), y: Y(0), width: IW, height: WH, class: 'pane', 'clip-path': 'url(#win)' });
el('line', { x1: X(CR), y1: Y(0), x2: X(CR), y2: Y(WH), class: 'edge' });
{
  const L = CR + 16, R = WW - 16, I = S.inspector.identity;
  el('rect', { x: X(L), y: Y(I.y + 4), width: 24, height: 24, rx: 5, class: 'hug' });
  slot(L + 34, I.y + 4, 150, 13, 'Node name · flex');
  bar(L + 34, I.y + 22, 70, 5, 'bar2');
  badge(15, WW + 16, I.y + 16);
  let y = I.y + I.h + 26;
  let firstVec = null, firstFact = null;
  for (const sec of S.inspector.sections) {
    el('line', { x1: X(L), y1: Y(y - 18), x2: X(R), y2: Y(y - 18), class: 'sep' });
    header(L, y, sec.header);
    chev(R - 4, y - 4);
    y += 12;
    if (sec.kind === 'chips') {
      const cy = y + 13;
      let chipX = L;
      for (const chip of sec.rows) {
        const chipW = Math.max(54, chip.length * 5.2 + 16);
        el('rect', { x: X(chipX), y: Y(cy - 10), width: chipW, height: 20, rx: 10, class: 'hug' });
        tx(X(chipX + chipW / 2), Y(cy) + 4, chip, 'sl', { 'text-anchor': 'middle' });
        chipX += chipW + 5;
      }
      if (!firstFact) firstFact = cy;
      y += 28;
      y += 34;
      continue;
    }
    for (const r of sec.rows) {
      const cy = y + 13;
      if (sec.kind === 'vector') {
        tx(X(L), Y(cy) + 4, r, 'lab');
        const fx = L + 64, fw = (R - fx - 8) / 3;
        ['X', 'Y', 'Z'].forEach((a, k) => {
          const x = fx + k * (fw + 4);
          el('rect', { x: X(x), y: Y(cy - 10), width: fw, height: 20, rx: 5, class: 'field' });
          tx(X(x + 6), Y(cy) + 3.5, a, 'axis');
          tx(X(x + fw - 6), Y(cy) + 4, r === 'Scale' ? '1.000' : '0.000', 'mono', { 'text-anchor': 'end' });
        });
        if (!firstVec) firstVec = cy;
        y += 28;
      } else if (sec.kind === 'shape') {
        el('rect', { x: X(L), y: Y(cy - 10), width: 120, height: 20, rx: 5, class: 'slotbox' });
        tx(X(L + 60), Y(cy) + 4, 'Shape preview', 'sl', { 'text-anchor': 'middle' });
        y += 28;
      } else if (sec.kind === 'issue') {
        el('rect', { x: X(L), y: Y(cy - 11), width: R - L, height: 22, rx: 6, class: 'issue' });
        tx(X(L + 8), Y(cy) + 4, r, 'lab');
        y += 30;
      } else {
        tx(X(L), Y(cy) + 4, r[0], 'lab');
        if (r[1] === 'swatch') { el('rect', { x: X(R - 40), y: Y(cy - 7), width: 40, height: 14, rx: 3, class: 'swatch' }); }
        else tx(X(R), Y(cy) + 4, r[1], 'mono', { 'text-anchor': 'end' });
        if (!firstFact) firstFact = cy;
        y += 24;
      }
    }
    y += 34;
  }
  badge(16, WW + 16, firstVec);
  badge(17, WW + 16, firstFact);
}

// ---- title bar band ----
el('rect', { x: X(0), y: Y(0), width: WW, height: TB, class: 'band', 'clip-path': 'url(#win)' });
el('line', { x1: X(0), y1: Y(TB), x2: X(WW), y2: Y(TB), class: 'rel' });
el('line', { x1: X(0), y1: Y(CY), x2: X(WW), y2: Y(CY), class: 'axisline' });
// traffic lights
const T = S.titleBar.trafficLights;
for (let i = 0; i < 3; i++) el('circle', { cx: X(T.firstX + i * T.pitch), cy: Y(CY), r: T.d / 2, class: 'light' });
badge(2, T.firstX + 2 * T.pitch + 18, CY - 14);
// clusters
function island(x, parts) {
  let w = 0;
  const widths = parts.map(p => p === 'icon' ? IS.button : p === 'menu' ? IS.menuButton : p === 'divider' ? 1 : 112);
  w = widths.reduce((a, b) => a + b, 0);
  el('rect', { x: X(x), y: Y(CY - IS.h / 2), width: w, height: IS.h, rx: IS.h / 2, class: 'glass' });
  let cx = x;
  parts.forEach((p, k) => {
    const pw = widths[k];
    if (p === 'icon') glyph(cx + 8, CY - 8);
    if (p === 'menu') { glyph(cx + 8, CY - 8); chev(cx + 34, CY); }
    if (p === 'divider') el('line', { x1: X(cx), y1: Y(CY - 9), x2: X(cx), y2: Y(CY + 9), class: 'thin' });
    if (p === 'swatches') for (let s = 0; s < 4; s++) el('circle', { cx: X(cx + 20 + s * 24), cy: Y(CY), r: 8, class: s === 0 ? 'swsel' : ['', 'sw1', 'sw2', 'sw3', 'sw4'][s + 1] });
    cx += pw;
  });
  return w;
}
const islandW = parts => parts.reduce((a, p) => a + (p === 'icon' ? IS.button : p === 'menu' ? IS.menuButton : p === 'divider' ? 1 : 112), 0);
const clusterW = c => c.islands.reduce((a, i) => a + islandW(i), 0) + (c.islands.length - 1) * IS.gap;
function cluster(c, x0) { let x = x0; const xs = []; c.islands.forEach(i => { xs.push(x); x += island(x, i) + IS.gap; }); return xs; }
const st = C.clusters.stage, lk = C.clusters.look, cm = C.clusters.camera;
const stX = CL + IN, lkX = CC - clusterW(lk) / 2, cmX = CR - IN - clusterW(cm);
const stXs = cluster(st, stX); const lkXs = cluster(lk, lkX); const cmXs = cluster(cm, cmX);
badge(7, stX + clusterW(st) / 2, CY + 26);
badge(8, CC, CY + 26);
badge(9, cmX + clusterW(cm) / 2, CY + 26);
// Open in
{
  const o = C.openIn, x = WW - IN - o.w;
  el('rect', { x: X(x), y: Y(CY - o.h / 2), width: o.w, height: o.h, rx: o.h / 2, class: 'glass' });
  tx(X(x + 14), Y(CY) + 4, 'Open in', 'btn');
  chev(x + o.w - 16, CY);
  badge(10, x - 12, CY);
}
badge(1, 150, CY + 2);
// cluster dims
hdim(CL, CL + IN, TB + 14, '14', 0, CY);
hdim(CR - IN, CR, TB + 14, '14', 0, CY);
{ // camera: menu 46, gap 8, icon 32, island h 32
  hdim(cmXs[0], cmXs[0] + IS.menuButton, CY - IS.h / 2 - 7, '46');
  hdim(cmXs[1] - IS.gap, cmXs[1], CY - IS.h / 2 - 7, '8');
  hdim(cmXs[1], cmXs[1] + IS.button, CY - IS.h / 2 - 7, '32');
  vdim(CY - IS.h / 2, CY + IS.h / 2, lkX - 10, '32', -1);
}
tx(X(CC + 14), Y(CY + 29), 'VIEW MODE │ LIGHTING', 'dts');

// ---- bottom HUDs + gizmo ----
const DH = C.dimensionsHud, TL = C.timelineHud, G = C.gizmo;
{
  const y = WH - IN - DH.h, x = CC - DH.w / 2;
  el('rect', { x: X(x), y: Y(y), width: DH.w, height: DH.h, rx: DH.h / 2, class: 'glass' });
  tx(X(CC), Y(y + DH.h / 2) + 4, DH.text, 'mono', { 'text-anchor': 'middle' });
  badge(13, x + DH.w + 12, y + DH.h / 2);
  vdim(y + DH.h, WH, x - 14, '14', -1);
  const ty = y - TL.gap - TL.h, tx0 = CC - TL.w / 2;
  el('rect', { x: X(tx0), y: Y(ty), width: TL.w, height: TL.h, rx: TL.h / 2, class: 'glassdash' });
  el('path', { d: `M${X(tx0 + 18)},${Y(ty + 13)} l12,7 l-12,7z`, class: 'dotp' });
  el('line', { x1: X(tx0 + 44), y1: Y(ty + 20), x2: X(tx0 + 300), y2: Y(ty + 20), class: 'track' });
  el('line', { x1: X(tx0 + 44), y1: Y(ty + 20), x2: X(tx0 + 130), y2: Y(ty + 20), class: 'trackon' });
  el('circle', { cx: X(tx0 + 130), cy: Y(ty + 20), r: 5, class: 'knob' });
  tx(X(tx0 + 312), Y(ty + 24), '0:01.2', 'mono');
  el('rect', { x: X(tx0 + 356), y: Y(ty + 10), width: 52, height: 20, rx: 10, class: 'hug' });
  chev(tx0 + 396, ty + 20);
  tx(X(tx0), Y(ty) - 6, 'IF ANIMATIONS', 'dts');
  badge(12, tx0 - 12, ty + TL.h / 2);
  const gx = CR - IN - G.size, gy = WH - IN - G.size, gc = [gx + G.size / 2, gy + G.size / 2];
  el('rect', { x: X(gx), y: Y(gy), width: G.size, height: G.size, rx: 10, class: 'slotbox' });
  el('circle', { cx: X(gc[0]), cy: Y(gc[1]), r: 30, class: 'rel' });
  const ax = [['X', 24, 10, 'axX'], ['Y', 0, -26, 'axY'], ['Z', -18, 18, 'axZ']];
  for (const [n, dx, dy, c] of ax) {
    el('line', { x1: X(gc[0]), y1: Y(gc[1]), x2: X(gc[0] + dx), y2: Y(gc[1] + dy), class: c });
    el('circle', { cx: X(gc[0] + dx), cy: Y(gc[1] + dy), r: 7, class: 'axend' });
    tx(X(gc[0] + dx), Y(gc[1] + dy) + 3, n, 'axl', { 'text-anchor': 'middle' });
  }
  hdim(gx, gx + G.size, gy - 8, '76');
  badge(14, gx - 12, gy + 10);
}
badge(11, MX + 120, MY - 40);

// window outline last
el('rect', { x: X(0), y: Y(0), width: WW, height: WH, rx: S.window.radius, class: 'win' });

// ---- outer dimensions ----
hdim(0, SW, -44, `${SW}  (${S.sidebar.min}–${S.sidebar.max})`, 0, 0);
hdim(SW, CR, -44, 'canvas visible area · model centred here', 0, 0);
hdim(CR, WW, -44, `${IW}  (${S.inspector.min}–${S.inspector.max})`, 0, 0);
hdim(0, WW, -76, 'canvas · Metal 3D view fills the whole window, behind both panes', 0);
vdim(0, CY, -12, `${CY}`, -1, 0);
vdim(0, TB, -36, `${TB}`, -1, 0);
vdim(0, S.sidebar.fileCard.y, -60, `${S.sidebar.fileCard.y}`, -1, S.sidebar.fileCard.inset);
// resize affordances
for (const [x, s] of [[SW, '↔'], [CR, '↔']]) tx(X(x), Y(WH) + 16, s + ' resizable', 'dts', { 'text-anchor': 'middle' });

// badges on top
for (const [n, x, y] of badges) {
  el('circle', { cx: X(x), cy: Y(y), r: 8, class: 'badge' });
  tx(X(x), Y(y) + 3, n, 'bn', { 'text-anchor': 'middle' });
}

// ---- key ----
{
  const cols = 3, colW = (WW - 250) / cols, perCol = Math.ceil(S.key.length / cols);
  tx(OX, KEY_Y - 14, 'ELEMENTS', 'hd');
  S.key.forEach((k, i) => {
    const c = Math.floor(i / perCol), r = i % perCol;
    const x = OX + c * colW, y = KEY_Y + r * 24;
    el('circle', { cx: x + 8, cy: y, r: 8, class: 'badge' });
    tx(x + 8, y + 3, i + 1, 'bn', { 'text-anchor': 'middle' });
    tx(x + 22, y + 4, k, 'kt');
  });
}
// ---- variant inset: sidebar closed ----
{
  const VX = OX + WW - 236, VY = KEY_Y - 14, sc = 1, w = 236, h = 80;
  tx(VX, VY, S.variant.name.toUpperCase(), 'hd');
  const by = VY + 14;
  el('rect', { x: VX, y: by, width: w, height: 52, rx: 10, class: 'canvas' });
  el('line', { x1: VX, y1: by + 26, x2: VX + w, y2: by + 26, class: 'axisline' });
  for (let i = 0; i < 3; i++) el('circle', { cx: VX + T.firstX + i * T.pitch, cy: by + 26, r: 6, class: 'light' });
  const sx = VX + S.variant.stageX;
  el('rect', { x: sx, y: by + 10, width: 32, height: 32, rx: 16, class: 'glass' });
  el('rect', { x: sx + 8, y: by + 18, width: 16, height: 16, rx: 3, class: 'hug' });
  el('rect', { x: sx + 40, y: by + 10, width: 46, height: 32, rx: 16, class: 'glass' });
  el('rect', { x: sx + 48, y: by + 18, width: 16, height: 16, rx: 3, class: 'hug' });
  el('line', { x1: VX + T.clearance, y1: by - 2, x2: VX + T.clearance, y2: by + 52, class: 'ext' });
  const dy = by + 66;
  const d = (a, b, l) => { el('line', { x1: a, y1: dy, x2: b, y2: dy, class: 'dim' }); for (const q of [a, b]) el('line', { x1: q, y1: dy - 4, x2: q, y2: dy + 4, class: 'dim' }); tx((a + b) / 2, dy + 13, l, 'dv', { 'text-anchor': 'middle' }); };
  d(VX, VX + T.firstX, '26');
  d(VX + T.firstX, VX + T.clearance, '78 clear');
  d(VX + T.clearance, sx, '14');
  el('line', { x1: VX, y1: dy + 24, x2: sx, y2: dy + 24, class: 'dim' });
  for (const q of [VX, sx]) el('line', { x1: q, y1: dy + 20, x2: q, y2: dy + 28, class: 'dim' });
  tx(sx + 6, dy + 27, `Stage x = ${S.variant.stageX}`, 'dv');
}

const css = `
:root{color-scheme:light dark;--paper:#fff;--ink:#050505;--muted:#626262;--soft:#878787;--canvas:#fbfbfb;--pane:#f3f3f3;--fill:#e8e8e8;--fill2:#cfcfcf;--line:#bebebe;--wash:#050505}
@media(prefers-color-scheme:dark){:root{--paper:#1c1c1e;--ink:#f5f5f7;--muted:#b5b5ba;--soft:#8e8e93;--canvas:#242426;--pane:#2c2c2e;--fill:#3a3a3c;--fill2:#48484a;--line:#636366;--wash:#fff}}
.bg{fill:#fff}.eb{font:500 9px 'SF Mono',ui-monospace,Menlo,monospace;letter-spacing:.12em;fill:#626262}
.ti{font:500 20px '.New York','New York',ui-serif,Georgia,serif;fill:#050505}.canvas{fill:#fbfbfb;stroke:none}.pane{fill:#f3f3f3;fill-opacity:.94}.edge{stroke:#050505;stroke-width:.8}.band{fill:#050505;fill-opacity:.025}.win{fill:none;stroke:#050505;stroke-width:1.6}.card{fill:#fff;stroke:#050505;stroke-width:1}.hug{fill:#e8e8e8;stroke:#050505;stroke-width:.9}.slot{fill:none;stroke:#626262;stroke-width:.8;stroke-dasharray:4 3}.slotbox{fill:#fff;fill-opacity:.6;stroke:#626262;stroke-width:.8;stroke-dasharray:4 3}.sl{font:500 8px 'SF Mono',ui-monospace,Menlo,monospace;letter-spacing:.06em;text-transform:uppercase;fill:#626262}.bar{fill:#cfcfcf}.bar2{fill:#e8e8e8}.sel{fill:#050505;fill-opacity:.08}.thin{fill:none;stroke:#050505;stroke-width:.9}.dot{fill:#050505}.dotp{fill:#050505}.hd{font:600 10px 'SF Pro',-apple-system,system-ui,sans-serif;letter-spacing:.06em;fill:#626262}.cnt{font:400 10px 'SF Pro',-apple-system,system-ui,sans-serif;fill:#878787}.lab{font:400 11px 'SF Pro',-apple-system,system-ui,sans-serif;fill:#626262}.mono{font:400 11px 'SF Mono',ui-monospace,Menlo,monospace;fill:#050505}.btn{font:500 11px 'SF Pro',-apple-system,system-ui,sans-serif;fill:#050505}.axis{font:600 9px 'SF Pro',-apple-system,system-ui,sans-serif;fill:#878787}.field{fill:#fff;stroke:#bebebe;stroke-width:.8}.swatch{fill:#878787;stroke:#050505;stroke-width:.8}.sep{stroke:#bebebe;stroke-width:1}.glass{fill:#fff;fill-opacity:.85;stroke:#050505;stroke-width:1.1}.glassdash{fill:#fff;fill-opacity:.85;stroke:#050505;stroke-width:1.1;stroke-dasharray:5 3}.light{fill:#e8e8e8;stroke:#050505;stroke-width:.9}.swsel{fill:#fff;stroke:#050505;stroke-width:2}.sw2{fill:#bebebe;stroke:#050505;stroke-width:.8}.sw3{fill:#626262;stroke:#050505;stroke-width:.8}.sw4{fill:#050505}.rel{fill:none;stroke:#878787;stroke-width:.7;stroke-dasharray:8 3 2 3}.axisline{stroke:#050505;stroke-width:.6;stroke-dasharray:2 3;opacity:.55}.lead{stroke:#050505;stroke-width:.7}.face1{fill:#e8e8e8;stroke:#050505;stroke-width:1.2}.face2{fill:#cfcfcf;stroke:#050505;stroke-width:1.2}.face3{fill:#f3f3f3;stroke:#050505;stroke-width:1.2}.hidden{fill:none;stroke:#878787;stroke-width:.7;stroke-dasharray:3 3}.track{stroke:#bebebe;stroke-width:3;stroke-linecap:round}.trackon{stroke:#050505;stroke-width:3;stroke-linecap:round}.knob{fill:#fff;stroke:#050505;stroke-width:1.2}.axX{stroke:#e2564a;stroke-width:2.4}.axY{stroke:#34c759;stroke-width:1.6}.axZ{stroke:#0a84ff;stroke-width:1;stroke-dasharray:3 2}.axend{fill:#fff;stroke:#050505;stroke-width:1}.axl{font:700 8px 'SF Pro',-apple-system,system-ui,sans-serif;fill:#050505}.dim{stroke:#050505;stroke-width:.6}.ext{stroke:#878787;stroke-width:.5;stroke-dasharray:2 2}.dv{font:500 9px 'SF Mono',ui-monospace,Menlo,monospace;fill:#050505;paint-order:stroke;stroke:#fff;stroke-width:3px}.dts{font:500 8px 'SF Mono',ui-monospace,Menlo,monospace;letter-spacing:.08em;fill:#626262;paint-order:stroke;stroke:#fff;stroke-width:3px}.badge{fill:#050505}.bn{font:600 8.5px 'SF Mono',ui-monospace,Menlo,monospace;fill:#fff}.kt{font:400 11.5px 'SF Pro',-apple-system,system-ui,sans-serif;fill:#050505}.issue{fill:#f5a623;fill-opacity:.18;stroke:#f5a623;stroke-width:.8}
@media(prefers-color-scheme:dark){.bg{fill:#1c1c1e}.eb,.hd,.sl,.lab,.cnt,.axis,.dts{fill:#b5b5ba}.ti,.mono,.btn,.axl,.dv,.kt{fill:#f5f5f7}.canvas{fill:#242426}.pane{fill:#2c2c2e}.edge,.win,.thin,.axisline,.lead,.dim{stroke:#f5f5f7}.band{fill:#f5f5f7}.card{fill:#1c1c1e;stroke:#f5f5f7}.hug,.bar,.bar2,.light,.face1,.face2,.face3{fill:#3a3a3c;stroke:#f5f5f7}.slot,.slotbox{stroke:#b5b5ba}.field,.glass,.glassdash,.swsel,.axend,.knob{fill:#1c1c1e;stroke:#f5f5f7}.swatch{fill:#8e8e93;stroke:#f5f5f7}.sep,.track{stroke:#636366}.rel,.ext,.hidden{stroke:#8e8e93}.trackon{stroke:#f5f5f7}.sw2{fill:#636366;stroke:#f5f5f7}.sw3{fill:#b5b5ba;stroke:#f5f5f7}.sw4{fill:#f5f5f7}.badge{fill:#f5f5f7}.bn{fill:#1c1c1e}.issue{fill:#ffc04d;stroke:#ffc04d}}
`;
const defs = `<defs><pattern id="grid" width="24" height="24" patternUnits="userSpaceOnUse"><path d="M24 0H0V24" fill="none" stroke="#050505" stroke-opacity=".05" stroke-width=".7"/></pattern></defs>`;
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${TOTAL_W}" height="${TOTAL_H}" viewBox="0 0 ${TOTAL_W} ${TOTAL_H}" role="img" aria-labelledby="t d" data-sc-type="wireframe"><title id="t">${esc(S.title)} anatomy</title><desc id="d">Wireframe of the glTF Inspector document window: 52 pt title-bar band, 248 pt sidebar, Metal canvas with glass clusters and HUDs, 288 pt inspector, with measurements in points.</desc><style>${css}</style>${defs}${out.join('\n')}</svg>`;
fs.writeFileSync(outPath, svg);
console.log('ok', TOTAL_W, TOTAL_H);
