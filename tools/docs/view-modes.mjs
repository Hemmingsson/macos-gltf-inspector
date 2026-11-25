import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { rect as pushRect, text as pushText } from './svg-helpers.mjs';

const here = new URL('.', import.meta.url).pathname;
const root = path.resolve(here, '../..');
const output = path.join(here, 'view-modes.png');
const temp = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'gltf-view-modes-')), 'sheet.svg');
const imageData = name => `data:image/png;base64,${fs.readFileSync(path.join(root, 'TestModels/References/Features', name)).toString('base64')}`;
const out = [];
const text = (x, y, value, cls = 'body', anchor = 'start') =>
  pushText(out, x, y, value, cls, anchor);
const rect = (x, y, w, h, cls, r = 0) => pushRect(out, x, y, w, h, cls, r);
const image = (x, y, w, h, name) =>
  out.push(`<image x="${x}" y="${y}" width="${w}" height="${h}" preserveAspectRatio="xMidYMid slice" href="${imageData(name)}"/>`);

const main = [
  ['Shaded', 'BoomBox-aces-narkowicz.png', 'Reference render'],
  ['Clay', null, 'No current reference render'],
  ['X-Ray', null, 'No current reference render'],
  ['Wireframe', 'wireframe.png', 'Reference render'],
  ['Wireframe on Shaded', null, 'No current reference render']
];
const channels = [
  ['Base Color', 'BoomBox-baseColor.png'],
  ['Metallic', 'BoomBox-metallic.png'],
  ['Roughness', 'BoomBox-roughness.png'],
  ['Normals', 'BoomBox-normals.png'],
  ['Tangents', 'BoomBox-tangents.png'],
  ['UVs', 'BoomBox-textureCoordinates.png'],
  ['Ambient Occlusion', 'BoomBox-ambientOcclusion.png'],
  ['Emissive', 'BoomBox-emissive.png'],
  ['Alpha', 'BoomBox-alpha.png'],
  ['Specular', 'BoomBox-specular.png'],
  ['Clearcoat', 'BoomBox-clearcoat.png'],
  ['Clearcoat Roughness', 'BoomBox-clearcoatRoughness.png'],
  ['Clearcoat Normal', 'BoomBox-clearcoatNormal.png']
];

out.push('<rect width="1160" height="930" class="page"/>');
text(42, 42, 'View modes', 'title');
text(42, 68, 'The menu shows Shaded and the display modes that the open file supports.', 'subtitle');
text(42, 90, 'These reference renders show the available modes and channels without changing the model.', 'subtitle');

const cardW = 204;
const cardH = 190;
main.forEach(([label, file, detail], i) => {
  const x = 42 + i * 222;
  const y = 112;
  rect(x, y, cardW, cardH, 'card', 12);
  if (file) image(x + 12, y + 12, 180, 140, file);
  else {
    rect(x + 12, y + 12, 180, 140, 'empty', 8);
    text(x + 102, y + 76, 'No image', 'emptyText', 'middle');
  }
  text(x + 12, y + 170, label, 'cardTitle');
  text(x + 12, y + 187, detail, 'tiny');
});

text(42, 342, 'Material channels', 'heading');
text(42, 366, 'Channel names match the View mode menu.', 'subtitle');
channels.forEach(([label, file], i) => {
  const col = i % 5;
  const row = Math.floor(i / 5);
  const x = 42 + col * 222;
  const y = 392 + row * 168;
  rect(x, y, cardW, 148, 'card', 12);
  image(x + 12, y + 12, 180, 108, file);
  text(x + 12, y + 134, label, 'cardTitle');
});
text(42, 900, 'Clay, X-Ray, and Wireframe on Shaded have menu names but no current reference render in TestModels/References/Features.', 'note');

const css = `
:root{color-scheme:light dark}svg{font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text',sans-serif;background:#fff}.page{fill:#fff}.title{font-size:28px;font-weight:600;fill:#050505}.subtitle,.note{font-size:14px;fill:#626262}.heading{font-size:18px;font-weight:600;fill:#050505}.card{fill:#f3f3f3;stroke:#bebebe;stroke-width:1}.cardTitle{font-size:14px;font-weight:600;fill:#050505}.tiny{font-size:11px;fill:#626262}.empty{fill:#e8e8e8;stroke:#bebebe;stroke-width:1;stroke-dasharray:5 4}.emptyText{font-size:14px;fill:#626262}
@media(prefers-color-scheme:dark){svg{background:#1c1c1e}.page{fill:#1c1c1e}.title,.heading,.cardTitle{fill:#f5f5f7}.subtitle,.note,.tiny,.emptyText{fill:#b5b5ba}.card{fill:#2c2c2e;stroke:#636366}.empty{fill:#3a3a3c;stroke:#636366}}
`;
fs.writeFileSync(temp, `<svg xmlns="http://www.w3.org/2000/svg" width="1160" height="930" viewBox="0 0 1160 930" role="img" aria-labelledby="title desc"><title id="title">View modes</title><desc id="desc">Contact sheet of glTF Inspector view modes and material channels from reference renders.</desc><style>${css}</style>${out.join('')}</svg>\n`);
execFileSync(process.env.RESVG ?? 'resvg', [temp, output], { stdio: 'inherit' });
fs.rmSync(path.dirname(temp), { recursive: true, force: true });
