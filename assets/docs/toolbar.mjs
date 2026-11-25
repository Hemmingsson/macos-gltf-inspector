import fs from 'node:fs';

const here = new URL('.', import.meta.url).pathname;
const spec = JSON.parse(fs.readFileSync(`${here}toolbar.json`, 'utf8'));
const esc = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const out = [];
const text = (x, y, value, cls = 'body', anchor = 'start') =>
  out.push(`<text x="${x}" y="${y}" class="${cls}" text-anchor="${anchor}">${esc(value)}</text>`);
const rect = (x, y, w, h, cls, r = 0) =>
  out.push(`<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" class="${cls}"/>`);
const line = (x1, y1, x2, y2, cls = 'line') =>
  out.push(`<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" class="${cls}"/>`);
const badge = (n, x, y) => {
  out.push(`<circle cx="${x}" cy="${y}" r="14" class="badge"/>`);
  text(x, y + 5, n, 'badgeText', 'middle');
};

const margin = 52;
const bandY = 108;
const bandH = 172;
const clusterX = [margin, 356, 650, 994];
const clusterW = [280, 270, 320, 196];

out.push(`<rect width="${spec.width}" height="${spec.height}" class="page"/>`);
text(margin, 42, spec.title, 'title');
text(margin, 70, 'The toolbar keeps related controls in four named clusters.', 'subtitle');
text(margin, 94, 'Labels match the live app. Shortcuts appear only when the app binds them.', 'subtitle');

spec.clusters.forEach((cluster, index) => {
  const x = clusterX[index];
  const w = clusterW[index];
  rect(x, bandY, w, bandH, 'panel', 16);
  text(x + 18, bandY + 28, cluster.name, 'heading');
  text(x + 18, bandY + 48, cluster.purpose, 'small');
  line(x + 18, bandY + 60, x + w - 18, bandY + 60, 'separator');
  cluster.controls.forEach((control, row) => {
    const y = bandY + 82 + row * 22;
    rect(x + 18, y - 14, Math.min(w - 36, 112), 20, 'control', 10);
    text(x + 74, y, control.label, 'controlText', 'middle');
    text(x + 142, y, control.detail, 'small');
  });
  badge(cluster.number, x + w - 28, bandY + 22);
});

text(margin, 342, 'Toolbar anatomy', 'heading');
const labels = [
  ['1', 'Stage', 'Backdrop and Floor'],
  ['2', 'Look', 'View mode and Lighting'],
  ['3', 'Camera', 'Perspective, Field of view, and View'],
  ['4', 'Open in', 'Finder, Blender, exports, and Copy GLB']
];
labels.forEach(([n, name, detail], i) => {
  const y = 380 + i * 36;
  badge(n, margin + 14, y - 5);
  text(margin + 40, y, name, 'bodyStrong');
  text(margin + 170, y, detail, 'body');
});

text(620, 342, 'Keyboard shortcuts', 'heading');
spec.shortcuts.forEach((shortcut, i) => {
  const x = i < 4 ? 620 : 885;
  const y = 380 + (i % 4) * 36;
  rect(x, y - 19, 232, 24, 'shortcut', 6);
  text(x + 12, y - 2, shortcut, 'body');
});

text(margin, 604, 'Open the View menu for camera presets, selection framing, visibility, and reset actions.', 'note');
text(margin, 630, 'Open the Lighting popover for Exposure, Environment, and Tone mapping.', 'note');

const css = `
:root{color-scheme:light dark}text{font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text',sans-serif}.page{fill:#fff}.title{font-size:28px;font-weight:600;fill:#050505}.subtitle,.small,.note{font-size:14px;fill:#626262}.heading{font-size:17px;font-weight:600;fill:#050505}.body{font-size:15px;fill:#050505}.bodyStrong{font-size:15px;font-weight:600;fill:#050505}.panel{fill:#f3f3f3;stroke:#bebebe;stroke-width:1}.separator,.line{stroke:#bebebe;stroke-width:1}.control{fill:#e8e8e8;stroke:#bebebe;stroke-width:1}.controlText{font-size:13px;font-weight:500;fill:#050505}.shortcut{fill:#e8e8e8;stroke:#bebebe;stroke-width:1}.badge{fill:#050505}.badgeText{font-size:13px;font-weight:700;fill:#fff}svg{shape-rendering:geometricPrecision}
@media(prefers-color-scheme:dark){.page{fill:#1c1c1e}.title,.heading,.body,.bodyStrong,.controlText{fill:#f5f5f7}.subtitle,.small,.note{fill:#b5b5ba}.panel{fill:#2c2c2e;stroke:#636366}.separator,.line{stroke:#636366}.control,.shortcut{fill:#3a3a3c;stroke:#636366}.badge{fill:#f5f5f7}.badgeText{fill:#1c1c1e}}
`;
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${spec.width}" height="${spec.height}" viewBox="0 0 ${spec.width} ${spec.height}" role="img" aria-labelledby="title desc"><title id="title">${esc(spec.title)}</title><desc id="desc">Wireframe of the glTF Inspector toolbar clusters and their controls.</desc><style>${css}</style>${out.join('')}</svg>`;
fs.writeFileSync(`${here}toolbar.svg`, `${svg}\n`);
