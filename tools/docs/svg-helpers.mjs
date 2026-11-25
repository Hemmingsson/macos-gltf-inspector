export const esc = value =>
  String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

export const text = (out, x, y, value, cls = 'body', anchor = 'start') =>
  out.push(`<text x="${x}" y="${y}" class="${cls}" text-anchor="${anchor}">${esc(value)}</text>`);

export const rect = (out, x, y, w, h, cls, r = 0) =>
  out.push(`<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" class="${cls}"/>`);

export const line = (out, x1, y1, x2, y2, cls = 'line') =>
  out.push(`<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" class="${cls}"/>`);

export const badge = (out, n, x, y) => {
  out.push(`<circle cx="${x}" cy="${y}" r="14" class="badge"/>`);
  text(out, x, y + 5, n, 'badgeText', 'middle');
};
