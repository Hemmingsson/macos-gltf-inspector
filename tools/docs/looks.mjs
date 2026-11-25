import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const here = new URL('.', import.meta.url).pathname;
const root = path.resolve(here, '../..');
const output = path.join(here, 'looks.png');
const temp = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'gltf-looks-')), 'sheet.svg');
const esc = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const imageData = name => `data:image/png;base64,${fs.readFileSync(path.join(root, 'TestModels/References/Features', name)).toString('base64')}`;
const out = [];
const text = (x, y, value, cls = 'body', anchor = 'start') =>
  out.push(`<text x="${x}" y="${y}" class="${cls}" text-anchor="${anchor}">${esc(value)}</text>`);
const rect = (x, y, w, h, cls, r = 0) =>
  out.push(`<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" class="${cls}"/>`);
const image = (x, y, w, h, name) =>
  out.push(`<image x="${x}" y="${y}" width="${w}" height="${h}" preserveAspectRatio="xMidYMid slice" href="${imageData(name)}"/>`);

const environments = [
  ['Neutral', 'No current reference render'],
  ['Field', 'BoomBox-field.png'],
  ['Studio', 'BoomBox-studio.png']
];
const mappings = [
  ['Neutral', 'No current reference render'],
  ['Linear', 'BoomBox-linear.png'],
  ['ACES', 'BoomBox-aces-hill.png'],
  ['ACES Fast', 'BoomBox-aces-narkowicz.png']
];

out.push('<rect width="940" height="620" class="page"/>');
text(42, 42, 'Lighting and tone mapping', 'title');
text(42, 68, 'Lighting changes the environment. Tone mapping changes the final image curve.', 'subtitle');

text(42, 112, 'Environment', 'heading');
environments.forEach(([label, source], i) => {
  const x = 42 + i * 292;
  const y = 132;
  rect(x, y, 264, 198, 'card', 12);
  if (source.endsWith('.png')) image(x + 12, y + 12, 240, 150, source);
  else {
    rect(x + 12, y + 12, 240, 150, 'empty', 8);
    text(x + 132, y + 92, 'No image', 'emptyText', 'middle');
  }
  text(x + 12, y + 178, label, 'cardTitle');
  text(x + 252, y + 178, source.endsWith('.png') ? 'reference' : 'not available', 'tiny', 'end');
});

text(42, 378, 'Tone mapping', 'heading');
mappings.forEach(([label, source], i) => {
  const x = 42 + i * 218;
  const y = 398;
  rect(x, y, 194, 164, 'card', 12);
  if (source.endsWith('.png')) image(x + 10, y + 10, 174, 112, source);
  else {
    rect(x + 10, y + 10, 174, 112, 'empty', 8);
    text(x + 97, y + 72, 'No image', 'emptyText', 'middle');
  }
  text(x + 10, y + 144, label, 'cardTitle');
});
text(42, 598, 'The Lighting popover uses exact names for its environments and tone mapping options.', 'note');

const css = `
:root{color-scheme:light dark}svg{font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text',sans-serif;background:#fff}.page{fill:#fff}.title{font-size:28px;font-weight:600;fill:#050505}.subtitle,.note,.tiny{font-size:14px;fill:#626262}.tiny{font-size:11px}.heading{font-size:18px;font-weight:600;fill:#050505}.card{fill:#f3f3f3;stroke:#bebebe;stroke-width:1}.cardTitle{font-size:15px;font-weight:600;fill:#050505}.empty{fill:#e8e8e8;stroke:#bebebe;stroke-width:1;stroke-dasharray:5 4}.emptyText{font-size:14px;fill:#626262}
@media(prefers-color-scheme:dark){svg{background:#1c1c1e}.page{fill:#1c1c1e}.title,.heading,.cardTitle{fill:#f5f5f7}.subtitle,.note,.tiny,.emptyText{fill:#b5b5ba}.card{fill:#2c2c2e;stroke:#636366}.empty{fill:#3a3a3c;stroke:#636366}}
`;
fs.writeFileSync(temp, `<svg xmlns="http://www.w3.org/2000/svg" width="940" height="620" viewBox="0 0 940 620" role="img" aria-labelledby="title desc"><title id="title">Lighting and tone mapping</title><desc id="desc">Contact sheet of reference renders for lighting environments and tone mapping options.</desc><style>${css}</style>${out.join('')}</svg>\n`);
execFileSync(process.env.RESVG ?? 'resvg', [temp, output], { stdio: 'inherit' });
fs.rmSync(path.dirname(temp), { recursive: true, force: true });
