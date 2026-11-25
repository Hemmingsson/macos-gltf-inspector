import fs from 'node:fs';

const here = new URL('.', import.meta.url).pathname;
const spec = JSON.parse(fs.readFileSync(`${here}inspector.json`, 'utf8'));
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

out.push(`<rect width="${spec.width}" height="${spec.height}" class="page"/>`);
text(48, 46, spec.title, 'title');
text(48, 74, 'The inspector follows the selected outliner row.', 'subtitle');
text(48, 98, 'The app hides sections that do not apply to the selected glTF entry.', 'subtitle');

rect(48, 132, 266, 620, 'pane', 14);
text(72, 166, 'OUTLINER', 'label');
rect(68, 186, 226, 42, 'file', 8);
text(82, 205, 'BoomBox', 'bodyStrong');
text(82, 222, 'glTF Binary', 'small');
text(72, 260, 'SCENE', 'label');
const rows = [
  ['⌄', 'Root', 0], ['⌄', 'Body', 1], ['·', 'Mesh', 2], ['·', 'Material', 2],
  ['·', 'Camera', 1], ['·', 'Animation', 0]
];
rows.forEach(([icon, name, depth], i) => {
  const y = 292 + i * 34;
  if (name === 'Mesh') rect(68, y - 20, 226, 28, 'selected', 6);
  text(82 + depth * 18, y, icon, 'glyph');
  text(104 + depth * 18, y, name, 'body');
  text(278, y, name === 'Mesh' ? '⚠' : '○', 'status', 'middle');
});
line(68, 516, 294, 516);
text(72, 548, 'VALIDATION', 'label');
rect(68, 566, 226, 54, 'issue', 8);
text(82, 589, '1 error · 2 warnings', 'bodyStrong');
text(82, 608, 'Select an issue to find its row.', 'small');
badge(1, 38, 132);
badge(5, 318, 566);

text(370, 140, 'Selection changes the inspector', 'heading');
line(370, 154, 1118, 154);
const cardW = 350;
const cardH = spec.layout.cardHeight;
spec.selectionTypes.forEach((item, index) => {
  const col = index % 2;
  const row = Math.floor(index / 2);
  const x = 370 + col * 380;
  const y = 180 + row * spec.layout.cardRowPitch;
  rect(x, y, cardW, cardH, 'panel', 14);
  badge(item.number + 1, x - 14, y - 12);
  text(x + 22, y + 32, item.name, 'heading');
  text(x + cardW - 22, y + 32, 'selected row', 'small', 'end');
  line(x + 22, y + 48, x + cardW - 22, y + 48);
  item.sections.forEach((section, sectionIndex) => {
    const sy = y + 78 + sectionIndex * spec.layout.rowPitch;
    rect(x + 22, sy - 20, cardW - 44, 28, section === 'Issues' ? 'issue' : 'section', 6);
    text(x + 34, sy, section, 'body');
    if (section === 'Transform · authored') text(x + cardW - 34, sy, 'P · R · S', 'small', 'end');
    if (section === 'Geometry') text(x + cardW - 34, sy, 'tris · verts · UVs', 'small', 'end');
    if (section === 'Material') text(x + cardW - 34, sy, 'maps · factors', 'small', 'end');
    if (section === 'Animation') text(x + cardW - 34, sy, 'duration · channels', 'small', 'end');
    if (section === 'Issues') text(x + cardW - 34, sy, 'linked findings', 'small', 'end');
  });
});

text(370, spec.height - 12, 'Issues appear at the end of the selected entry and match validator findings in the outliner.', 'note');

const css = `
:root{color-scheme:light dark}svg{font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text',sans-serif;background:#fff}.page{fill:#fff}.title{font-size:28px;font-weight:600;fill:#050505}.subtitle,.small,.note{font-size:14px;fill:#626262}.heading{font-size:17px;font-weight:600;fill:#050505}.body{font-size:15px;fill:#050505}.bodyStrong{font-size:15px;font-weight:600;fill:#050505}.label{font-size:11px;font-weight:600;letter-spacing:1.2px;fill:#626262}.glyph{font-size:15px;fill:#050505}.status{font-size:14px;fill:#f5a623}.pane,.panel{fill:#f3f3f3;stroke:#bebebe;stroke-width:1}.file,.section{fill:#e8e8e8;stroke:#bebebe;stroke-width:1}.selected{fill:#0a84ff;fill-opacity:.16}.issue{fill:#f5a623;fill-opacity:.18;stroke:#f5a623;stroke-width:1}.line{stroke:#bebebe;stroke-width:1}.badge{fill:#050505}.badgeText{font-size:13px;font-weight:700;fill:#fff}
@media(prefers-color-scheme:dark){svg{background:#1c1c1e}.page{fill:#1c1c1e}.title,.heading,.body,.bodyStrong,.glyph{fill:#f5f5f7}.subtitle,.small,.note,.label{fill:#b5b5ba}.pane,.panel{fill:#2c2c2e;stroke:#636366}.file,.section{fill:#3a3a3c;stroke:#636366}.line{stroke:#636366}.badge{fill:#f5f5f7}.badgeText{fill:#1c1c1e}}
`;
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${spec.width}" height="${spec.height}" viewBox="0 0 ${spec.width} ${spec.height}" role="img" aria-labelledby="title desc"><title id="title">${esc(spec.title)}</title><desc id="desc">Wireframe of the glTF Inspector outliner and selection-driven inspector sections.</desc><style>${css}</style>${out.join('')}</svg>`;
fs.writeFileSync(`${here}inspector.svg`, `${svg}\n`);
