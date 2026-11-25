// Builds GLTFInspector/DesignSystem/Icons/InspectorIcons.xcassets from the SVGs beside this file.
//
//   node assets/icons/inspector/build-catalog.mjs
//
// The sources are 24 × 24 line art: 2px stroke, round caps and joins, fill none,
// stroke currentColor. Each copy here swaps currentColor for #000 and is marked as a template
// image, so SwiftUI tints it from the surrounding foregroundStyle. See STYLEGUIDE.md for drawing rules.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.resolve(here, '../../../GLTFInspector/DesignSystem/Icons/InspectorIcons.xcassets');

fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'Contents.json'),
  JSON.stringify({ info: { author: 'xcode', version: 1 } }, null, 2) + '\n');

let kept = 0;
for (const file of fs.readdirSync(here).filter(f => f.endsWith('.svg')).sort()) {
  const name = file.slice(0, -4);
  const svg = fs.readFileSync(path.join(here, file), 'utf8').replace(/currentColor/g, '#000');
  const asset = `inspector.${name}`;
  const dir = path.join(out, `${asset}.imageset`);
  fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir, `${asset}.svg`), svg);
  fs.writeFileSync(path.join(dir, 'Contents.json'), JSON.stringify({
    images: [{ filename: `${asset}.svg`, idiom: 'universal' }],
    info: { author: 'xcode', version: 1 },
    properties: { 'preserves-vector-representation': true, 'template-rendering-intent': 'template' },
  }, null, 2) + '\n');
  kept++;
}
console.log(`${kept} icons → ${path.relative(process.cwd(), out)}`);
