import fs from 'node:fs';
import { badge, esc, line, rect, text } from './svg-helpers.mjs';

const here = new URL('.', import.meta.url).pathname;
const spec = JSON.parse(fs.readFileSync(`${here}export.json`, 'utf8'));
const out = [];
const emitText = (x, y, value, cls = 'body', anchor = 'start') =>
  text(out, x, y, value, cls, anchor);
const emitRect = (x, y, w, h, cls, r = 0) => rect(out, x, y, w, h, cls, r);
const emitLine = (x1, y1, x2, y2, cls = 'line') => line(out, x1, y1, x2, y2, cls);
const emitBadge = (n, x, y) => badge(out, n, x, y);

out.push(`<rect width="${spec.width}" height="${spec.height}" class="page"/>`);
emitText(48, 46, spec.title, 'title');
emitText(48, 74, 'Choose an export action, then choose a destination in the save panel.', 'subtitle');

emitRect(48, 116, 286, 286, 'menu', 14);
emitText(72, 152, 'File menu', 'heading');
emitLine(72, 170, 310, 170);
spec.actions.forEach((action, i) => {
  const y = 212 + i * 58;
  if (i === 0) emitRect(68, y - 24, 246, 40, 'selected', 7);
  emitText(84, y, action.label, 'body');
  emitText(292, y, action.shortcut, 'small', 'end');
});
emitBadge(1, 38, 116);

emitLine(334, 260, 438, 260, 'arrow');
out.push('<path d="M430 252 L444 260 L430 268" class="arrowHead"/>');
emitBadge(2, 392, 242);

emitRect(458, 116, 280, 286, 'panel', 14);
emitText(482, 152, 'Save panel', 'heading');
emitText(482, 184, 'Name', 'small');
emitRect(482, 194, 232, 30, 'field', 6);
emitText(494, 214, 'BoomBox.png', 'body');
emitText(482, 258, 'Format', 'small');
emitRect(482, 268, 232, 30, 'field', 6);
emitText(494, 288, 'PNG', 'body');
emitRect(602, 342, 112, 34, 'primary', 17);
emitText(658, 364, 'Export', 'primaryText', 'middle');
emitBadge(3, 448, 104);

emitLine(738, 260, 842, 260, 'arrow');
out.push('<path d="M834 252 L848 260 L834 268" class="arrowHead"/>');
emitBadge(4, 796, 242);

emitRect(858, 116, 214, 286, 'panel', 14);
emitText(882, 152, 'File result', 'heading');
spec.actions.forEach((action, i) => {
  const y = 198 + i * 64;
  emitRect(882, y - 20, 166, 42, 'file', 7);
  emitText(894, y - 2, action.result, 'bodyStrong');
  emitText(894, y + 14, action.detail, 'tiny');
});
emitBadge(5, 848, 104);

emitText(48, 456, 'PNG uses the current canvas pose. Turntable exports orbit the model once from that pose.', 'note');
emitText(48, 480, 'MP4 uses a 1080-pixel long edge. GIF uses a 540-pixel long edge.', 'note');

const css = `
:root{color-scheme:light dark}svg{font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text',sans-serif;background:#fff}.page{fill:#fff}.title{font-size:28px;font-weight:600;fill:#050505}.subtitle,.small,.note,.tiny{font-size:14px;fill:#626262}.tiny{font-size:11px}.heading{font-size:17px;font-weight:600;fill:#050505}.body{font-size:15px;fill:#050505}.bodyStrong{font-size:13px;font-weight:600;fill:#050505}.menu,.panel{fill:#f3f3f3;stroke:#bebebe;stroke-width:1}.field,.file{fill:#e8e8e8;stroke:#bebebe;stroke-width:1}.selected{fill:#0a84ff;fill-opacity:.16}.primary{fill:#0a84ff}.primaryText{font-size:14px;font-weight:600;fill:#fff}.line{stroke:#bebebe;stroke-width:1}.arrow{stroke:#050505;stroke-width:1.5}.arrowHead{fill:none;stroke:#050505;stroke-width:1.5}.badge{fill:#050505}.badgeText{font-size:13px;font-weight:700;fill:#fff}
@media(prefers-color-scheme:dark){svg{background:#1c1c1e}.page{fill:#1c1c1e}.title,.heading,.body,.bodyStrong{fill:#f5f5f7}.subtitle,.small,.note,.tiny{fill:#b5b5ba}.menu,.panel{fill:#2c2c2e;stroke:#636366}.field,.file{fill:#3a3a3c;stroke:#636366}.line{stroke:#636366}.arrow,.arrowHead{stroke:#f5f5f7}.badge{fill:#f5f5f7}.badgeText{fill:#1c1c1e}}
`;
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${spec.width}" height="${spec.height}" viewBox="0 0 ${spec.width} ${spec.height}" role="img" aria-labelledby="title desc"><title id="title">${esc(spec.title)}</title><desc id="desc">Wireframe of PNG and turntable export choices and resulting files.</desc><style>${css}</style>${out.join('')}</svg>`;
fs.writeFileSync(`${here}export.svg`, `${svg}\n`);
