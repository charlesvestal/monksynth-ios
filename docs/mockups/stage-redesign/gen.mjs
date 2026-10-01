// Sticker-cartoon mockup generator for MonkSynth characters + scenes.
// Characters are drawn in a 300x300 "stage"; scenes at any W x H.
import fs from 'node:fs';

const INK = '#2b1d1a';
const W_BOLD = 7, W_MED = 5, W_FINE = 3.5;

let uid = 0;
const nid = (p) => `${p}${++uid}`;

// Shade a hex colour by multiplying brightness.
function shade(hex, k) {
  const n = parseInt(hex.slice(1), 16);
  const c = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => Math.max(0, Math.min(255, Math.round(v * k))));
  return '#' + c.map((v) => v.toString(16).padStart(2, '0')).join('');
}

// Fill + hard lower-right shadow + ink outline. `el` is an SVG shape tag body
// without fill/stroke, e.g. `circle cx="1" cy="2" r="3"`.
function toon(el, base, { sw = W_BOLD, shadow = shade(base, 0.8), off = [-9, -8], noShadow = false } = {}) {
  const id = nid('s');
  const clip = nid('c');
  const tag = el.split(' ')[0];
  return `<defs><${el} id="${id}"/><clipPath id="${clip}"><use href="#${id}"/></clipPath></defs>` +
    (noShadow
      ? `<use href="#${id}" fill="${base}"/>`
      : `<g clip-path="url(#${clip})"><use href="#${id}" fill="${shadow}"/><use href="#${id}" fill="${base}" transform="translate(${off[0]} ${off[1]})"/></g>`) +
    `<use href="#${id}" fill="none" stroke="${INK}" stroke-width="${sw}" stroke-linejoin="round" stroke-linecap="round"/>`;
}
const P = (d) => `path d="${d}"`;
const C = (cx, cy, r) => `circle cx="${cx}" cy="${cy}" r="${r}"`;
const E = (cx, cy, rx, ry) => `ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}"`;
const line = (d, w = W_MED, col = INK) => `<path d="${d}" fill="none" stroke="${col}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`;
const hl = (cx, cy, r) => `<circle cx="${cx}" cy="${cy}" r="${r}" fill="#fff"/>`;

function eyeOpen(x, y, r, iris = INK, look = [2, 1]) {
  return toon(C(x, y, r), '#ffffff', { sw: W_MED, noShadow: true }) +
    `<circle cx="${x + look[0]}" cy="${y + look[1]}" r="${r * 0.55}" fill="${iris}"/>` +
    (iris !== INK ? `<circle cx="${x + look[0]}" cy="${y + look[1]}" r="${r * 0.28}" fill="${INK}"/>` : '') +
    hl(x + look[0] - r * 0.2, y + look[1] - r * 0.22, r * 0.18);
}
function eyeClosed(x, y, w) {
  return line(`M${x - w} ${y} Q${x} ${y + w * 0.75} ${x + w} ${y}`, W_MED);
}
function cheek(x, y, r = 11, col = '#f28b9b') {
  return `<ellipse cx="${x}" cy="${y}" rx="${r}" ry="${r * 0.65}" fill="${col}" opacity="0.75"/>`;
}

// ---------------------------------------------------------------- the mouth
// Five anchors: OO OH AH EH EE. Width/height in stage units at scale 1.
const ANCHORS = [
  { w: 24, h: 26, round: 1.0, tongue: 0.0, top: 0.0, bot: 0.0 }, // OO
  { w: 34, h: 40, round: 1.0, tongue: 0.3, top: 0.0, bot: 0.0 }, // OH
  { w: 50, h: 56, round: 0.9, tongue: 1.0, top: 0.0, bot: 0.0 }, // AH
  { w: 64, h: 34, round: 0.45, tongue: 0.8, top: 1.0, bot: 0.0 }, // EH
  { w: 74, h: 18, round: 0.12, tongue: 0.0, top: 1.0, bot: 1.0 }, // EE
];
export const VOWELS = ['OO', 'OH', 'AH', 'EH', 'EE'];
function mouthParams(v) {
  const t = Math.max(0, Math.min(1, v)) * 4;
  const i = Math.min(3, Math.floor(t));
  const f = t - i;
  const a = ANCHORS[i], b = ANCHORS[i + 1];
  const o = {};
  for (const k of Object.keys(a)) o[k] = a[k] + (b[k] - a[k]) * f;
  return o;
}
function mouthPath(cx, cy, w, h, round) {
  const L = cx - w / 2, R = cx + w / 2;
  const T = cy - h * 0.42, B = cy + h * 0.58; // bottom drops more
  const kx = (w / 2) * 0.552, kyT = (h * 0.42) * 0.552 * round, kyB = (h * 0.58) * 0.552 * round;
  return `M${L} ${cy} C${L} ${cy - kyT} ${cx - kx} ${T} ${cx} ${T} C${cx + kx} ${T} ${R} ${cy - kyT} ${R} ${cy} ` +
    `C${R} ${cy + kyB} ${cx + kx} ${B} ${cx} ${B} C${cx - kx} ${B} ${L} ${cy + kyB} ${L} ${cy} Z`;
}
function mouth(m, vowel, loud = 0) {
  const p = mouthParams(vowel);
  const s = m.scale ?? 1;
  const w = p.w * s, h = p.h * s * (1 + loud * 0.3);
  const d = mouthPath(m.x, m.y, w, h, p.round);
  const clip = nid('m');
  let out = '';
  if (m.variant === 'lips') {
    out += `<path d="${d}" fill="none" stroke="${INK}" stroke-width="${17 * s}" stroke-linejoin="round"/>`;
    out += `<path d="${d}" fill="none" stroke="${m.lip}" stroke-width="${10 * s}" stroke-linejoin="round"/>`;
  }
  out += `<defs><clipPath id="${clip}"><path d="${d}"/></clipPath></defs>`;
  out += `<path d="${d}" fill="#4a1622"/>`;
  out += `<g clip-path="url(#${clip})">`;
  if (p.tongue > 0.02) {
    out += `<ellipse cx="${m.x + w * 0.08}" cy="${m.y + h * 0.58}" rx="${w * 0.38}" ry="${h * 0.42 * p.tongue}" fill="#e8607a"/>`;
  }
  if (p.top > 0.02) out += `<rect x="${m.x - w}" y="${m.y - h}" width="${w * 2}" height="${h * 0.42 + h * 0.3 * p.top - h * 0.12}" fill="#fffaf0"/>`;
  if (p.bot > 0.02) out += `<rect x="${m.x - w}" y="${m.y + h * 0.58 - h * 0.28 * p.bot}" width="${w * 2}" height="${h}" fill="#fffaf0"/>`;
  out += `</g>`;
  out += `<path d="${d}" fill="none" stroke="${INK}" stroke-width="${(m.variant === 'lips' ? 3.5 : W_MED) * Math.max(0.8, s)}" stroke-linejoin="round"/>`;
  return out;
}

// ---------------------------------------------------------------- characters
// Each returns { body, face(blink), mouth: {x,y,scale,variant,lip}, over }
const CH = {};

CH.monk = {
  name: 'Monk',
  palette: { accent: '#f0a020', skyTop: '#f7b57a', skyBot: '#fbe6c4', ground: '#b98a55' },
  body: () =>
    toon(P('M126 168 L174 168 L176 234 L124 234 Z'), '#e4b085', { sw: W_MED }) +
    toon(P('M30 300 C40 246 78 214 116 209 C128 230 172 230 184 209 C222 214 260 246 270 300 Z'), '#a8322a') +
    toon(P('M98 216 C104 212 110 210 116 209 C150 238 204 266 232 300 L188 300 C166 272 134 248 98 216 Z'), '#f2a51f', { sw: W_MED }) +
    Array.from({ length: 9 }, (_, i) => { const t = i / 8; const x = (1 - t) * (1 - t) * 104 + 2 * t * (1 - t) * 150 + t * t * 196; const y = (1 - t) * (1 - t) * 214 + 2 * t * (1 - t) * 268 + t * t * 214; return toon(C(x, y, 6), '#6e3f22', { sw: 3 }); }).join('') +
    toon(C(84, 128, 15), '#e4b085', { sw: W_MED }) + toon(C(216, 128, 15), '#e4b085', { sw: W_MED }) +
    toon(E(150, 118, 68, 72), '#e9bb8f') +
    `<ellipse cx="128" cy="70" rx="16" ry="9" fill="#fff" opacity="0.45"/>`,
  face: (blink) =>
    line('M112 102 Q124 96 136 101', W_FINE) + line('M164 101 Q176 96 188 102', W_FINE) +
    eyeClosed(124, 120, 13) + eyeClosed(176, 120, 13) +
    line('M148 128 Q144 142 152 146', W_FINE) + cheek(108, 146) + cheek(192, 146),
  mouth: { x: 150, y: 165, scale: 0.8, variant: 'lips', lip: '#c8735f' },
};

CH.fish = {
  name: 'Fish',
  palette: { accent: '#ffb02e', skyTop: '#2b8fbe', skyBot: '#155a86', ground: '#e8cf8f' },
  body: () =>
    toon(P('M60 158 C16 116 -2 196 16 250 C36 230 54 214 70 206 Z'), '#ff9a3c') +
    line('M52 170 L28 160 M50 190 L20 200 M54 206 L28 234', W_FINE, '#d4651a') +
    toon(P('M240 158 C284 116 302 196 284 250 C264 230 246 214 230 206 Z'), '#ff9a3c') +
    line('M248 170 L272 160 M250 190 L280 200 M246 206 L272 234', W_FINE, '#d4651a') +
    toon(P('M108 92 C100 34 150 4 200 16 C188 40 192 66 200 92 Z'), '#ff9a3c') +
    line('M128 70 C130 46 146 28 166 20 M150 66 C156 48 168 34 184 26', W_FINE, '#d4651a') +
    toon(E(150, 168, 108, 112), '#f57f22') +
    `<ellipse cx="150" cy="225" rx="62" ry="40" fill="#ffc27a"/>` +
    [[110, 210], [150, 214], [190, 210], [130, 240], [170, 240]].map(([x, y]) => line(`M${x - 12} ${y} Q${x} ${y + 12} ${x + 12} ${y}`, W_FINE, '#d4651a')).join('') +
    `<ellipse cx="102" cy="88" rx="22" ry="12" fill="#fff" opacity="0.4" transform="rotate(-30 102 88)"/>`,
  face: (blink) => blink
    ? eyeClosed(108, 128, 20) + eyeClosed(192, 128, 20)
    : eyeOpen(108, 126, 28, INK, [3, 2]) + eyeOpen(192, 126, 28, INK, [-3, 2]),
  mouth: { x: 150, y: 182, scale: 0.85, variant: 'lips', lip: '#ff6f61' },
};

CH.unicorn = {
  name: 'Unicorn',
  palette: { accent: '#b77cf2', skyTop: '#bfe3ff', skyBot: '#ffe6f4', ground: '#9edc8b' },
  body: () =>
    toon(P('M50 300 C58 250 90 220 150 220 C210 220 242 250 250 300 Z'), '#fbf6ff') +
    toon(P('M124 48 C74 56 36 118 40 244 C56 214 74 196 98 186 C92 140 98 92 124 48 Z'), '#ff8fc7') +
    toon(P('M112 74 C80 112 66 172 76 252 C90 224 104 208 122 198 C108 160 104 116 112 74 Z'), '#8fb8ff') +
    toon(P('M100 60 L86 14 L124 46 Z'), '#fbf6ff', { sw: W_MED }) +
    toon(P('M200 60 L214 14 L176 46 Z'), '#fbf6ff', { sw: W_MED }) +
    toon(E(150, 112, 64, 70), '#fbf6ff') +
    toon(P('M108 66 C114 40 140 36 156 50 C142 54 130 62 122 76 C116 72 112 70 108 66 Z'), '#c78cff', { sw: W_MED }) +
    toon(P('M138 52 L150 4 L162 52 Z'), '#f8c94a', { sw: W_MED }) +
    line('M141 40 L159 34 M144 27 L157 22', W_FINE) +
    toon(E(150, 178, 54, 42), '#f8cfd8'),
  face: (blink) => (blink ? eyeClosed(120, 118, 15) + eyeClosed(180, 118, 15)
    : eyeOpen(120, 116, 18, '#6b3fa0') + eyeOpen(180, 116, 18, '#6b3fa0')) +
    line('M104 100 L98 94 M108 96 L104 88 M196 100 L202 94 M192 96 L196 88', W_FINE) +
    `<ellipse cx="132" cy="160" rx="5" ry="7" fill="${INK}"/><ellipse cx="168" cy="160" rx="5" ry="7" fill="${INK}"/>` +
    cheek(100, 142) + cheek(200, 142),
  mouth: { x: 150, y: 190, scale: 0.75, variant: 'muzzle' },
};

CH.girl = {
  name: 'Little Girl',
  palette: { accent: '#ff5fa2', skyTop: '#8fd3f7', skyBot: '#e6f7ff', ground: '#7cc96a' },
  body: () =>
    toon(C(72, 78, 34), '#7a4425') + toon(C(228, 78, 34), '#7a4425') +
    toon(P('M40 300 C48 248 88 222 150 222 C212 222 252 248 260 300 Z'), '#ff6fa8') +
    toon(P('M150 226 C130 236 108 236 98 226 C110 214 130 212 150 220 C170 212 190 214 202 226 C192 236 170 236 150 226 Z'), '#ffffff', { sw: W_MED }) +
    toon(P('M132 186 L168 186 L170 222 L130 222 Z'), '#f2c39d', { sw: W_MED }) +
    toon(C(150, 128, 66), '#f6cba6') +
    toon(P('M84 124 C80 64 120 46 150 46 C180 46 220 64 216 124 C200 104 186 96 176 84 C160 100 128 104 100 104 C94 110 88 116 84 124 Z'), '#8a4d2a') +
    toon(C(100, 96, 9), '#ff5fa2', { sw: W_FINE }) + toon(C(200, 96, 9), '#ff5fa2', { sw: W_FINE }),
  face: (blink) => (blink ? eyeClosed(124, 132, 14) + eyeClosed(176, 132, 14)
    : eyeOpen(124, 130, 16, '#2f7d5b') + eyeOpen(176, 130, 16, '#2f7d5b')) +
    line('M110 108 Q122 102 134 106', W_FINE) + line('M166 106 Q178 102 190 108', W_FINE) +
    cheek(106, 156, 13) + cheek(194, 156, 13),
  mouth: { x: 150, y: 170, scale: 0.7, variant: 'lips', lip: '#e2557a' },
};

CH.oldman = {
  name: 'Old Man',
  palette: { accent: '#e0a84a', skyTop: '#e9d3a3', skyBot: '#e2c690', ground: '#8a5a3b' },
  body: () =>
    toon(P('M30 300 C38 246 80 214 150 212 C220 214 262 246 270 300 Z'), '#5f6e8c') +
    toon(P('M118 214 L150 270 L182 214 Z'), '#e8e2d2', { sw: W_MED }) +
    line('M150 270 L150 300', W_MED) + `<circle cx="160" cy="284" r="4" fill="${INK}"/>` +
    toon(P('M100 92 C72 90 60 116 68 138 C58 152 70 170 90 164 L104 120 Z'), '#f4f3ee', { sw: W_MED }) +
    toon(P('M200 92 C228 90 240 116 232 138 C242 152 230 170 210 164 L196 120 Z'), '#f4f3ee', { sw: W_MED }) +
    toon(C(84, 124, 14), '#e2b08a', { sw: W_MED }) + toon(C(216, 124, 14), '#e2b08a', { sw: W_MED }) +
    toon(E(150, 116, 66, 72), '#e8b991') +
    toon(P('M92 140 C90 200 110 252 150 262 C190 252 210 200 208 140 C190 150 170 150 150 148 C130 150 110 150 92 140 Z'), '#f4f3ee') +
    line('M128 72 Q150 66 172 72', W_FINE, '#c99a74') + line('M132 84 Q150 79 168 84', W_FINE, '#c99a74'),
  face: (blink) =>
    toon(P('M100 104 C108 88 132 90 140 102 C126 98 112 100 100 104 Z'), '#f4f3ee', { sw: W_FINE }) +
    toon(P('M200 104 C192 88 168 90 160 102 C174 98 188 100 200 104 Z'), '#f4f3ee', { sw: W_FINE }) +
    eyeClosed(122, 116, 11) + eyeClosed(178, 116, 11) +
    toon(E(150, 138, 14, 12), '#d99a7a', { sw: W_MED }),
  mouth: { x: 150, y: 178, scale: 0.72, variant: 'lips', lip: '#c47f6f' },
  over: () => toon(P('M108 162 C120 148 140 150 150 158 C160 150 180 148 192 162 C176 166 162 166 150 162 C138 166 124 166 108 162 Z'), '#f4f3ee', { sw: W_MED }),
};

CH.cow = {
  name: 'Cow',
  palette: { accent: '#5aa7d8', skyTop: '#9fd6f2', skyBot: '#e3f4fb', ground: '#86cd66' },
  body: () =>
    toon(P('M36 300 C44 250 86 222 150 222 C214 222 256 250 264 300 Z'), '#fbf5ea') +
    toon(P('M200 240 C230 246 252 270 258 300 L200 300 C196 280 188 262 200 240 Z'), '#2f2a2a', { sw: W_MED }) +
    toon(P('M92 66 C70 60 64 36 76 26 C82 44 96 50 108 54 Z'), '#efe3c4', { sw: W_MED }) +
    toon(P('M208 66 C230 60 236 36 224 26 C218 44 204 50 192 54 Z'), '#efe3c4', { sw: W_MED }) +
    toon(E(62, 108, 30, 14), '#f2c4b8', { sw: W_MED }) + toon(E(238, 108, 30, 14), '#f2c4b8', { sw: W_MED }) +
    toon(E(150, 112, 72, 66), '#fbf5ea') +
    toon(P('M96 74 C110 58 140 64 138 90 C136 116 112 130 92 122 C82 108 84 86 96 74 Z'), '#2f2a2a', { sw: W_MED }) +
    toon(E(150, 180, 72, 48), '#f6b9b0') +
    `<ellipse cx="124" cy="160" rx="7" ry="10" fill="#9a5a55"/><ellipse cx="176" cy="160" rx="7" ry="10" fill="#9a5a55"/>` +
    toon(P('M136 228 L164 228 L170 262 L130 262 Z'), '#f2bd3a', { sw: W_MED }),
  face: (blink) => blink ? eyeClosed(118, 104, 13) + eyeClosed(182, 104, 13)
    : eyeOpen(118, 102, 15, INK) + eyeOpen(182, 102, 15, INK),
  mouth: { x: 150, y: 196, scale: 0.8, variant: 'muzzle' },
};

CH.firefighter = {
  name: 'Fire Fighter',
  palette: { accent: '#ff5a3c', skyTop: '#c9644a', skyBot: '#b4523c', ground: '#8d8f96' },
  body: () =>
    toon(P('M30 300 C38 246 80 218 150 216 C220 218 262 246 270 300 Z'), '#f2b33a') +
    `<defs><clipPath id="ffcoat"><path d="M30 300 C38 246 80 218 150 216 C220 218 262 246 270 300 Z"/></clipPath></defs>` +
    `<g clip-path="url(#ffcoat)"><rect x="0" y="258" width="300" height="18" fill="#e9eef2" stroke="${INK}" stroke-width="3.5"/><rect x="0" y="265" width="300" height="4" fill="#c9d1d8"/></g>` +
    `<path d="M30 300 C38 246 80 218 150 216 C220 218 262 246 270 300 Z" fill="none" stroke="${INK}" stroke-width="${W_BOLD}" stroke-linejoin="round"/>` +
    toon(P('M108 214 L130 238 L150 222 L170 238 L192 214 Z'), '#d79a2a', { sw: W_MED }) +
    toon(P('M130 184 L170 184 L172 220 L128 220 Z'), '#e8b48c', { sw: W_MED }) +
    toon(C(150, 136, 62), '#eebd93') +
    toon(P('M70 92 C66 70 110 64 150 64 C190 64 234 70 230 92 C200 98 100 98 70 92 Z'), '#d8372d') +
    toon(P('M96 82 C96 30 204 30 204 82 Z'), '#e2433a') +
    toon(P('M136 40 L164 40 L168 76 L132 76 Z'), '#f6cf4a', { sw: W_MED }) +
    `<circle cx="150" cy="58" r="7" fill="#d8372d" stroke="${INK}" stroke-width="3"/>`,
  face: (blink) => (blink ? eyeClosed(126, 128, 12) + eyeClosed(174, 128, 12)
    : eyeOpen(126, 126, 13, INK) + eyeOpen(174, 126, 13, INK)) +
    line('M110 108 L138 110', W_MED) + line('M162 110 L190 108', W_MED) +
    toon(E(150, 150, 12, 10), '#e0a07c', { sw: W_MED }),
  mouth: { x: 150, y: 178, scale: 0.75, variant: 'lips', lip: '#c86a5a' },
  over: () => toon(P('M118 166 C128 156 144 158 150 164 C156 158 172 156 182 166 C170 172 158 170 150 166 C142 170 130 172 118 166 Z'), '#7a3d22', { sw: W_FINE }),
};

CH.punk = {
  name: 'Punk',
  palette: { accent: '#7dff3a', skyTop: '#2a1f44', skyBot: '#130d20', ground: '#3b2f2b' },
  body: () =>
    toon(P('M30 300 C38 246 80 216 150 214 C220 216 262 246 270 300 Z'), '#2b2a35') +
    toon(P('M110 216 L150 280 L190 216 L172 216 L150 250 L128 216 Z'), '#45434f', { sw: W_MED }) +
    toon(P('M128 216 L150 250 L172 216 Z'), '#f2f2f2', { sw: W_MED }) +
    [[64, 262], [80, 244], [236, 262], [220, 244], [100, 290], [200, 290]].map(([x, y]) => `<circle cx="${x}" cy="${y}" r="5" fill="#d9dde3" stroke="${INK}" stroke-width="2.5"/>`).join('') +
    toon(P('M132 184 L168 184 L170 220 L130 220 Z'), '#e7b590', { sw: W_MED }) +
    toon(C(84, 134, 14), '#e7b590', { sw: W_MED }) + toon(C(216, 134, 14), '#e7b590', { sw: W_MED }) +
    `<circle cx="80" cy="146" r="4" fill="#d9dde3" stroke="${INK}" stroke-width="2"/><circle cx="220" cy="146" r="4" fill="#d9dde3" stroke="${INK}" stroke-width="2"/>` +
    toon(E(150, 132, 66, 68), '#edbe97') +
    toon(P('M118 76 L112 26 L130 62 L134 10 L146 58 L152 2 L160 58 L170 12 L172 62 L188 28 L184 78 C164 70 136 70 118 76 Z'), '#7dff3a', { sw: W_MED }),
  face: (blink) => (blink ? eyeClosed(124, 128, 13) + eyeClosed(176, 128, 13)
    : toon(E(124, 128, 15, 12), '#fff', { sw: W_MED, noShadow: true }) + `<circle cx="126" cy="129" r="7" fill="${INK}"/>` + hl(123, 126, 2.5) +
      toon(E(176, 128, 15, 12), '#fff', { sw: W_MED, noShadow: true }) + `<circle cx="174" cy="129" r="7" fill="${INK}"/>` + hl(171, 126, 2.5)) +
    line('M106 106 L140 116', W_BOLD) + line('M194 106 L160 116', W_BOLD) +
    line('M146 150 Q150 156 156 150', W_FINE) +
    `<circle cx="160" cy="154" r="5" fill="none" stroke="#d9dde3" stroke-width="3"/>`,
  mouth: { x: 150, y: 180, scale: 0.75, variant: 'lips', lip: '#6b3a6a' },
};

CH.dog = {
  name: 'Dog',
  palette: { accent: '#ff7a3d', skyTop: '#9fd6f2', skyBot: '#e9f6ff', ground: '#8bcf68' },
  body: () =>
    toon(P('M36 300 C44 248 86 216 150 216 C214 216 256 248 264 300 Z'), '#c98a4a') +
    toon(P('M114 166 L186 166 L190 228 L110 228 Z'), '#c98a4a', { sw: W_MED }) +
    toon(P('M108 210 C130 222 170 222 192 210 L194 228 C170 240 130 240 106 228 Z'), '#e0413a', { sw: W_MED }) +
    toon(C(150, 246, 12), '#f6cf4a', { sw: W_MED }) +
    toon(E(150, 118, 70, 68), '#d49452') +
    toon(P('M86 80 C50 84 42 150 56 200 C70 206 88 190 96 170 C100 140 104 104 86 80 Z'), '#7a4a26') +
    toon(P('M214 80 C250 84 258 150 244 200 C230 206 212 190 204 170 C200 140 196 104 214 80 Z'), '#7a4a26') +
    toon(E(150, 172, 50, 40), '#f3dcb8'),
  face: (blink) => (blink ? eyeClosed(124, 118, 13) + eyeClosed(176, 118, 13)
    : eyeOpen(124, 116, 15, '#5a3315') + eyeOpen(176, 116, 15, '#5a3315')) +
    line('M110 96 Q122 88 134 94', W_MED) + line('M166 94 Q178 88 190 96', W_MED) +
    toon(P('M134 140 C134 130 166 130 166 140 C166 152 156 158 150 158 C144 158 134 152 134 140 Z'), '#2b1d1a', { sw: W_FINE, noShadow: true }) + hl(144, 138, 3.5),
  mouth: { x: 150, y: 186, scale: 0.72, variant: 'muzzle' },
};

CH.pizza = {
  name: 'Pizza',
  palette: { accent: '#ff4b3a', skyTop: '#f6e4c4', skyBot: '#efd5aa', ground: '#e04b3c' },
  body: () =>
    toon(P('M47.1 64.2 A250 250 0 0 1 252.9 64.2 L150 292 Z'), '#f8c948') +
    `<path d="M44 68 A250 250 0 0 1 256 68" fill="none" stroke="${INK}" stroke-width="34" stroke-linecap="round"/>` +
    `<path d="M44 68 A250 250 0 0 1 256 68" fill="none" stroke="#d9913e" stroke-width="25" stroke-linecap="round"/>` +
    `<path d="M60 58 A250 250 0 0 1 240 58" fill="none" stroke="#eab36a" stroke-width="5" stroke-linecap="round"/>` +
    [[82, 94, 13], [218, 96, 13], [176, 214, 13], [124, 222, 11]].map(([x, y, r]) => toon(C(x, y, r), '#d8402f', { sw: W_MED }) + `<circle cx="${x - r * 0.3}" cy="${y - r * 0.2}" r="${r * 0.18}" fill="#8a2318"/><circle cx="${x + r * 0.35}" cy="${y + r * 0.25}" r="${r * 0.15}" fill="#8a2318"/>`).join('') +
    `<path d="M138 250 L144 236 L150 252 Z" fill="#7ab648" stroke="${INK}" stroke-width="2.5" stroke-linejoin="round"/>`,
  face: (blink) => (blink ? eyeClosed(128, 122, 13) + eyeClosed(172, 122, 13)
    : eyeOpen(128, 120, 15, INK) + eyeOpen(172, 120, 15, INK)) +
    line('M114 98 Q126 92 138 98', W_FINE) + line('M162 98 Q174 92 186 98', W_FINE) +
    cheek(108, 146, 10, '#f08a5a') + cheek(192, 146, 10, '#f08a5a'),
  mouth: { x: 150, y: 168, scale: 0.75, variant: 'bare' },
};

CH.ghost = {
  name: 'Ghost',
  palette: { accent: '#9ae6ff', skyTop: '#1c2250', skyBot: '#3a3f7c', ground: '#2c4a3e' },
  body: () =>
    toon(P('M62 290 L62 140 C62 54 238 54 238 140 L238 290 C224 270 214 300 200 282 C186 266 174 300 160 282 C146 266 134 300 120 282 C106 266 94 300 80 282 C72 274 68 280 62 290 Z'), '#f4f2ff', { shadow: '#cfcaf2' }),
  face: (blink) => (blink ? eyeClosed(122, 130, 15) + eyeClosed(178, 130, 15)
    : `<ellipse cx="122" cy="128" rx="14" ry="19" fill="${INK}"/><ellipse cx="178" cy="128" rx="14" ry="19" fill="${INK}"/>` + hl(117, 120, 4.5) + hl(173, 120, 4.5)) +
    cheek(100, 158, 12) + cheek(200, 158, 12),
  mouth: { x: 150, y: 178, scale: 0.85, variant: 'bare' },
};

CH.cat = {
  name: 'Cat',
  palette: { accent: '#7ee07e', skyTop: '#2e2546', skyBot: '#4a3b66', ground: '#c79a6a' },
  body: () =>
    toon(P('M238 300 C270 280 290 240 270 210 C260 196 244 204 252 214 C264 232 248 270 222 286 Z'), '#ee9a45', { sw: W_MED }) +
    toon(P('M40 300 C46 252 84 224 118 216 C120 200 118 184 116 170 L184 170 C182 184 180 200 182 216 C216 224 254 252 260 300 Z'), '#ee9a45') +
    line('M84 252 C92 244 100 242 108 244 M72 276 C82 266 92 264 100 266 M216 252 C208 244 200 242 192 244 M228 276 C218 266 208 264 200 266', W_MED, '#c46a1e') +
    toon(P('M84 96 L80 30 L132 64 Z'), '#ee9a45', { sw: W_MED }) + toon(P('M216 96 L220 30 L168 64 Z'), '#ee9a45', { sw: W_MED }) +
    `<path d="M92 82 L90 46 L120 66 Z" fill="#f6a3ad"/><path d="M208 82 L210 46 L180 66 Z" fill="#f6a3ad"/>` +
    toon(E(150, 128, 78, 72), '#f2a14c') +
    line('M150 62 L150 82 M134 64 L136 80 M166 64 L164 80', W_MED, '#c46a1e') +
    line('M80 128 L94 128 M78 140 L92 138 M220 128 L206 128 M222 140 L208 138', W_MED, '#c46a1e') +
    toon(C(135, 152, 16), '#fff6ea', { sw: W_MED, noShadow: true }) + toon(C(165, 152, 16), '#fff6ea', { sw: W_MED, noShadow: true }),
  face: (blink) => '<g transform="translate(0 -8)">' + ((blink ? eyeClosed(120, 120, 15) + eyeClosed(180, 120, 15)
    : toon(P('M102 120 C110 104 132 104 138 120 C132 134 110 134 102 120 Z'), '#9ae86a', { sw: W_MED, noShadow: true }) +
      toon(P('M162 120 C168 104 190 104 198 120 C190 134 168 134 162 120 Z'), '#9ae86a', { sw: W_MED, noShadow: true }) +
      `<ellipse cx="120" cy="120" rx="4" ry="11" fill="${INK}"/><ellipse cx="180" cy="120" rx="4" ry="11" fill="${INK}"/>` + hl(116, 114, 2.5) + hl(176, 114, 2.5)) +
    toon(P('M141 141 L159 141 L150 151 Z'), '#f48a9a', { sw: W_FINE, noShadow: true })) + '</g>',
  mouth: { x: 150, y: 172, scale: 0.6, variant: 'muzzle' },
  over: () => line('M120 148 L70 140 M120 158 L72 162 M180 148 L230 140 M180 158 L228 162', 2.5),
};

export const ORDER = ['monk', 'fish', 'unicorn', 'girl', 'oldman', 'cow', 'firefighter', 'punk', 'dog', 'pizza', 'ghost', 'cat'];

export function character(id, { vowel = 0.5, blink = false, loud = 0 } = {}) {
  const c = CH[id];
  return c.body() + c.face(blink) + mouth(c.mouth, vowel, loud) + (c.over ? c.over() : '');
}

// ---------------------------------------------------------------- scenes
function sky(W, H, top, bot) {
  const g = nid('g');
  return `<defs><linearGradient id="${g}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${top}"/><stop offset="1" stop-color="${bot}"/></linearGradient></defs><rect width="${W}" height="${H}" fill="url(#${g})"/>`;
}
function ground(W, H, gy, col) {
  return `<rect x="-10" y="${gy}" width="${W + 20}" height="${H - gy + 10}" fill="${col}" stroke="${INK}" stroke-width="${W_MED}"/>`;
}
// Small sticker props, drawn at an anchor (x,y = bottom centre) and size k.
const prop = {
  mountain: (x, y, k) => toon(P(`M${x - 90 * k} ${y} L${x} ${y - 110 * k} L${x + 90 * k} ${y} Z`), '#8c8fb8', { sw: W_MED }) +
    toon(P(`M${x - 30 * k} ${y - 73 * k} L${x} ${y - 110 * k} L${x + 30 * k} ${y - 73 * k} L${x + 14 * k} ${y - 80 * k} L${x} ${y - 70 * k} L${x - 14 * k} ${y - 80 * k} Z`), '#ffffff', { sw: W_FINE, noShadow: true }),
  sun: (x, y, r) => Array.from({ length: 12 }, (_, i) => { const a = i * Math.PI / 6; const x1 = x + Math.cos(a) * r * 1.3, y1 = y + Math.sin(a) * r * 1.3, x2 = x + Math.cos(a) * r * 1.7, y2 = y + Math.sin(a) * r * 1.7; return line(`M${x1} ${y1} L${x2} ${y2}`, 9) + line(`M${x1} ${y1} L${x2} ${y2}`, 4.5, '#ffd35a'); }).join('') + toon(C(x, y, r), '#ffd35a', { sw: W_MED, noShadow: true }),
  moon: (x, y, r) => toon(C(x, y, r), '#fff3c4', { sw: W_MED, noShadow: true }) + `<circle cx="${x + r * 0.3}" cy="${y - r * 0.2}" r="${r * 0.2}" fill="#efe0a8"/>`,
  cloud: (x, y, k) => toon(P(`M${x - 40 * k} ${y} C${x - 50 * k} ${y - 20 * k} ${x - 26 * k} ${y - 32 * k} ${x - 14 * k} ${y - 22 * k} C${x - 8 * k} ${y - 44 * k} ${x + 24 * k} ${y - 42 * k} ${x + 24 * k} ${y - 20 * k} C${x + 46 * k} ${y - 26 * k} ${x + 52 * k} ${y} ${x + 40 * k} ${y} Z`), '#ffffff', { sw: W_MED, noShadow: true }),
  flags: (x0, x1, y) => {
    const cols = ['#3b82f6', '#ffffff', '#e5463a', '#3fb56b', '#f5c33b'];
    let s = line(`M${x0} ${y} Q${(x0 + x1) / 2} ${y + 26} ${x1} ${y}`, 2.5);
    const n = Math.max(4, Math.floor((x1 - x0) / 34));
    for (let i = 1; i < n; i++) {
      const t = i / n, x = x0 + (x1 - x0) * t, yy = y + 26 * 4 * t * (1 - t) * 0.5 * 2 / 2 * 1;
      const yq = y + 52 * t * (1 - t);
      s += `<path d="M${x - 10} ${yq} L${x + 10} ${yq} L${x + 8} ${yq + 22} L${x - 8} ${yq + 22} Z" fill="${cols[i % 5]}" stroke="${INK}" stroke-width="2.5" stroke-linejoin="round"/>`;
    }
    return s;
  },
  bubble: (x, y, r) => `<circle cx="${x}" cy="${y}" r="${r}" fill="#ffffff" fill-opacity="0.25" stroke="#e6f6ff" stroke-width="3"/>` + `<circle cx="${x - r * 0.35}" cy="${y - r * 0.35}" r="${r * 0.22}" fill="#fff"/>`,
  kelp: (x, y, h) => line(`M${x} ${y} C${x - 18} ${y - h * 0.3} ${x + 18} ${y - h * 0.6} ${x} ${y - h}`, 9, INK) + line(`M${x} ${y} C${x - 18} ${y - h * 0.3} ${x + 18} ${y - h * 0.6} ${x} ${y - h}`, 5, '#3fae6a'),
  tree: (x, y, k) => toon(P(`M${x - 10 * k} ${y} L${x - 8 * k} ${y - 60 * k} L${x + 8 * k} ${y - 60 * k} L${x + 10 * k} ${y} Z`), '#8a5a33', { sw: W_MED }) + toon(C(x, y - 90 * k, 44 * k), '#3fae5a', { sw: W_MED }),
  kite: (x, y, k) => toon(P(`M${x} ${y - 30 * k} L${x + 20 * k} ${y} L${x} ${y + 34 * k} L${x - 20 * k} ${y} Z`), '#ffcf3a', { sw: W_FINE }) + line(`M${x} ${y + 34 * k} C${x - 20} ${y + 70 * k} ${x + 20} ${y + 90 * k} ${x - 10} ${y + 130 * k}`, 2),
  rainbow: (x, y, r) => ['#ff7aa8', '#ffcf5a', '#7ed98a', '#7ab8ff', '#b78cff'].map((c, i) => `<path d="M${x - r + i * 10} ${y} A${r - i * 10} ${r - i * 10} 0 0 1 ${x + r - i * 10} ${y}" fill="none" stroke="${c}" stroke-width="10"/>`).join('') + `<path d="M${x - r - 5} ${y} A${r + 5} ${r + 5} 0 0 1 ${x + r + 5} ${y}" fill="none" stroke="${INK}" stroke-width="3"/><path d="M${x - r + 45} ${y} A${r - 45} ${r - 45} 0 0 1 ${x + r - 45} ${y}" fill="none" stroke="${INK}" stroke-width="3"/>`,
  fence: (x0, x1, y) => { let s = toon(`rect x="${x0}" y="${y - 34}" width="${x1 - x0}" height="9"`, '#f1e3c6', { sw: W_FINE, noShadow: true }); for (let x = x0 + 10; x < x1; x += 34) s += toon(`rect x="${x}" y="${y - 50}" width="12" height="50"`, '#f1e3c6', { sw: W_FINE, noShadow: true }); return s; },
  barn: (x, y, k) => toon(P(`M${x - 50 * k} ${y} L${x - 50 * k} ${y - 60 * k} L${x} ${y - 95 * k} L${x + 50 * k} ${y - 60 * k} L${x + 50 * k} ${y} Z`), '#d6453a', { sw: W_MED }) + toon(`rect x="${x - 18 * k}" y="${y - 44 * k}" width="${36 * k}" height="${44 * k}"`, '#f6efe0', { sw: W_FINE, noShadow: true }),
  bricks: (W, gy) => { let s = ''; for (let y = 14, r = 0; y < gy; y += 26, r++) { s += `<line x1="0" y1="${y}" x2="${W}" y2="${y}" stroke="#8a3b2a" stroke-width="3"/>`; for (let x = (r % 2) * 30; x < W; x += 60) s += `<line x1="${x}" y1="${y}" x2="${x}" y2="${y + 26}" stroke="#8a3b2a" stroke-width="3"/>`; } return s; },
  hydrant: (x, y, k) => toon(P(`M${x - 14 * k} ${y} L${x - 14 * k} ${y - 46 * k} C${x - 14 * k} ${y - 66 * k} ${x + 14 * k} ${y - 66 * k} ${x + 14 * k} ${y - 46 * k} L${x + 14 * k} ${y} Z`), '#e2433a', { sw: W_MED }) + toon(`rect x="${x - 22 * k}" y="${y - 40 * k}" width="${44 * k}" height="${10 * k}"`, '#c9302a', { sw: W_FINE, noShadow: true }),
  amp: (x, y, k) => toon(`rect x="${x - 34 * k}" y="${y - 70 * k}" width="${68 * k}" height="${70 * k}"`, '#1e1c22', { sw: W_MED }) + `<rect x="${x - 26 * k}" y="${y - 62 * k}" width="${52 * k}" height="${54 * k}" fill="#3a3640"/>` + `<circle cx="${x}" cy="${y - 35 * k}" r="${18 * k}" fill="#222" stroke="#555" stroke-width="3"/>` + toon(`rect x="${x - 34 * k}" y="${y - 96 * k}" width="${68 * k}" height="${26 * k}"`, '#1e1c22', { sw: W_MED }) + `<circle cx="${x - 20 * k}" cy="${y - 83 * k}" r="${4 * k}" fill="#7dff3a"/>`,
  spot: (x, W, H, col) => `<path d="M${x - 14} 0 L${x + 14} 0 L${x + 120} ${H} L${x - 120} ${H} Z" fill="${col}" opacity="0.18"/>`,
  doghouse: (x, y, k) => toon(P(`M${x - 46 * k} ${y} L${x - 46 * k} ${y - 50 * k} L${x} ${y - 88 * k} L${x + 46 * k} ${y - 50 * k} L${x + 46 * k} ${y} Z`), '#5aa0d8', { sw: W_MED }) + toon(P(`M${x - 16 * k} ${y} L${x - 16 * k} ${y - 26 * k} C${x - 16 * k} ${y - 44 * k} ${x + 16 * k} ${y - 44 * k} ${x + 16 * k} ${y - 26 * k} L${x + 16 * k} ${y} Z`), '#2b1d1a', { sw: W_FINE, noShadow: true }) + toon(P(`M${x - 56 * k} ${y - 46 * k} L${x} ${y - 96 * k} L${x + 56 * k} ${y - 46 * k} L${x + 46 * k} ${y - 40 * k} L${x} ${y - 82 * k} L${x - 46 * k} ${y - 40 * k} Z`), '#d6453a', { sw: W_FINE }),
  bone: (x, y, k) => toon(P(`M${x - 22 * k} ${y - 4 * k} L${x + 22 * k} ${y - 4 * k} C${x + 26 * k} ${y - 16 * k} ${x + 38 * k} ${y - 10 * k} ${x + 32 * k} ${y} C${x + 38 * k} ${y + 10 * k} ${x + 26 * k} ${y + 16 * k} ${x + 22 * k} ${y + 4 * k} L${x - 22 * k} ${y + 4 * k} C${x - 26 * k} ${y + 16 * k} ${x - 38 * k} ${y + 10 * k} ${x - 32 * k} ${y} C${x - 38 * k} ${y - 10 * k} ${x - 26 * k} ${y - 16 * k} ${x - 22 * k} ${y - 4 * k} Z`), '#fbf3e0', { sw: W_FINE, noShadow: true }),
  checker: (W, H, gy) => { let s = `<rect x="0" y="${gy}" width="${W}" height="${H - gy}" fill="#ffffff"/>`; const sz = 30; for (let y = gy, r = 0; y < H; y += sz, r++) for (let x = (r % 2) * sz; x < W; x += sz * 2) s += `<rect x="${x}" y="${y}" width="${sz}" height="${sz}" fill="#e04b3c"/>`; return s + `<line x1="0" y1="${gy}" x2="${W}" y2="${gy}" stroke="${INK}" stroke-width="${W_MED}"/>`; },
  candle: (x, y, k) => toon(P(`M${x - 16 * k} ${y} L${x - 16 * k} ${y - 40 * k} C${x - 16 * k} ${y - 54 * k} ${x - 6 * k} ${y - 56 * k} ${x - 6 * k} ${y - 70 * k} L${x + 6 * k} ${y - 70 * k} C${x + 6 * k} ${y - 56 * k} ${x + 16 * k} ${y - 54 * k} ${x + 16 * k} ${y - 40 * k} L${x + 16 * k} ${y} Z`), '#3b7a4a', { sw: W_MED }) + toon(`rect x="${x - 5 * k}" y="${y - 100 * k}" width="${10 * k}" height="${32 * k}"`, '#fff6e0', { sw: W_FINE, noShadow: true }) + toon(P(`M${x} ${y - 124 * k} C${x + 9 * k} ${y - 112 * k} ${x + 7 * k} ${y - 102 * k} ${x} ${y - 102 * k} C${x - 7 * k} ${y - 102 * k} ${x - 9 * k} ${y - 112 * k} ${x} ${y - 124 * k} Z`), '#ffcf3a', { sw: W_FINE, noShadow: true }),
  tomb: (x, y, k) => toon(P(`M${x - 22 * k} ${y} L${x - 22 * k} ${y - 40 * k} C${x - 22 * k} ${y - 66 * k} ${x + 22 * k} ${y - 66 * k} ${x + 22 * k} ${y - 40 * k} L${x + 22 * k} ${y} Z`), '#8f97b8', { sw: W_MED }),
  star: (x, y, r) => `<path d="M${x} ${y - r} L${x + r * 0.3} ${y - r * 0.3} L${x + r} ${y} L${x + r * 0.3} ${y + r * 0.3} L${x} ${y + r} L${x - r * 0.3} ${y + r * 0.3} L${x - r} ${y} L${x - r * 0.3} ${y - r * 0.3} Z" fill="#fff3c4"/>`,
  window: (x, y, w, h) => toon(`rect x="${x - w / 2}" y="${y - h}" width="${w}" height="${h}"`, '#26315e', { sw: W_BOLD, noShadow: true }) + prop.moon(x + w * 0.2, y - h * 0.68, Math.min(w, h) * 0.13) + prop.star(x - w * 0.25, y - h * 0.75, 6) + prop.star(x - w * 0.1, y - h * 0.4, 4) + line(`M${x} ${y - h} L${x} ${y} M${x - w / 2} ${y - h / 2} L${x + w / 2} ${y - h / 2}`, W_MED, '#c79a6a') + `<rect x="${x - w / 2}" y="${y - h}" width="${w}" height="${h}" fill="none" stroke="${INK}" stroke-width="${W_BOLD}"/>`,
  lamp: (x, y, k) => line(`M${x} ${y} L${x} ${y - 120 * k}`, 6) + toon(P(`M${x - 30 * k} ${y - 120 * k} L${x - 20 * k} ${y - 160 * k} L${x + 20 * k} ${y - 160 * k} L${x + 30 * k} ${y - 120 * k} Z`), '#f6d27a', { sw: W_MED }) + toon(E(x, y, 26 * k, 7 * k), '#6b4a33', { sw: W_FINE, noShadow: true }),
  stripes: (W, gy) => { let s = ''; for (let x = 0; x < W; x += 36) s += `<rect x="${x}" y="0" width="14" height="${gy}" fill="#dfc58f"/>`; return s; },
};

function scene(id, W, H) {
  const p = CH[id].palette;
  const gy = Math.round(H * 0.72);
  const cx = W / 2;
  const L = W * 0.12, R = W * 0.88;
  let s = sky(W, H, p.skyTop, p.skyBot);
  switch (id) {
    case 'monk':
      s += prop.sun(R - W * 0.06, gy - H * 0.3, Math.min(30, H * 0.08)) + prop.mountain(L + 20, gy, H / 300) + prop.mountain(R, gy, H / 380) + prop.mountain(cx + W * 0.3, gy, H / 460);
      s += ground(W, H, gy, p.ground) + prop.flags(-10, W + 10, H * 0.08);
      break;
    case 'fish':
      s += prop.kelp(L, H, H * 0.6) + prop.kelp(L + 30, H, H * 0.45) + prop.kelp(R, H, H * 0.55);
      s += ground(W, H, Math.round(H * 0.86), p.ground) + prop.bubble(R - 30, H * 0.3, 14) + prop.bubble(R - 10, H * 0.18, 9) + prop.bubble(L + 40, H * 0.22, 11);
      break;
    case 'unicorn':
      s += prop.rainbow(cx, gy, Math.min(W * 0.48, H * 0.62)) + prop.cloud(L + 10, H * 0.24, 0.8) + prop.cloud(R - 10, H * 0.34, 0.65);
      s += ground(W, H, gy, p.ground);
      break;
    case 'girl':
      s += prop.cloud(cx - W * 0.2, H * 0.18, 0.6) + ground(W, H, gy, p.ground) + prop.tree(L + 6, gy + 6, H / 330) + prop.kite(R - 6, H * 0.2, 0.8);
      break;
    case 'oldman':
      s += prop.stripes(W, gy) + prop.window(L + 34, gy - H * 0.2, Math.min(90, W * 0.2), H * 0.32) + ground(W, H, gy, p.ground) + prop.lamp(R - 6, gy + 4, H / 300);
      break;
    case 'cow':
      s += prop.cloud(cx + W * 0.25, H * 0.2, 0.6) + prop.barn(L + 20, gy, H / 330) + ground(W, H, gy, p.ground) + prop.fence(R - 110, W + 10, gy + 4);
      break;
    case 'firefighter':
      s += prop.bricks(W, gy) + ground(W, H, gy, p.ground) + prop.hydrant(R - 10, gy + 14, H / 300);
      break;
    case 'punk':
      s += prop.spot(L + 30, W, gy, '#ff4fd8') + prop.spot(R - 30, W, gy, '#7dff3a') + ground(W, H, gy, p.ground) + prop.amp(L, gy + 2, H / 300) + prop.amp(R, gy + 2, H / 300);
      break;
    case 'dog':
      s += prop.cloud(L + 20, H * 0.2, 0.6) + ground(W, H, gy, p.ground) + prop.doghouse(R - 16, gy + 6, H / 300) + prop.bone(L + 10, gy + 30, 0.8);
      break;
    case 'pizza':
      s += prop.checker(W, H, gy) + prop.candle(R - 10, gy + 10, H / 300);
      break;
    case 'ghost':
      s += prop.moon(R - 20, H * 0.2, Math.min(34, H * 0.09)) + prop.star(L + 10, H * 0.14, 6) + prop.star(cx - W * 0.2, H * 0.08, 4) + prop.star(cx + W * 0.15, H * 0.12, 5);
      s += ground(W, H, gy, p.ground) + prop.tomb(L + 10, gy + 6, H / 300) + prop.tomb(R - 10, gy + 8, H / 360);
      break;
    case 'cat':
      s += prop.window(cx, gy - 6, W * 0.7, gy - H * 0.08) + ground(W, H, gy, p.ground);
      break;
  }
  return s;
}

// Composite: scene + character anchored bottom-centre.
export function composite(id, W, H, opts = {}) {
  const s = Math.round(Math.min(H * (opts.charScale ?? 0.94), W * 0.8));
  const x = (W - s) / 2, y = H - s;
  let out = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">`;
  out += scene(id, W, H);
  out += `<g transform="translate(${x} ${y}) scale(${s / 300})">${character(id, opts)}</g>`;
  if (opts.touch) {
    const [tx, ty] = opts.touch;
    const acc = CH[id].palette.accent;
    // pitch ticks along the bottom and a vowel scale on the right edge
    for (let i = 0; i <= 24; i++) {
      const xx = 12 + (W - 24) * i / 24;
      out += `<line x1="${xx}" y1="${H - 4}" x2="${xx}" y2="${H - (i % 12 === 0 ? 16 : i % 2 ? 7 : 11)}" stroke="#ffffff" stroke-opacity="0.75" stroke-width="2"/>`;
    }
    VOWELS.forEach((v, i) => {
      const yy = 22 + (H - 50) * (1 - i / 4);
      out += `<text x="${W - 8}" y="${yy}" text-anchor="end" font-family="ui-rounded, 'SF Pro Rounded', system-ui" font-weight="800" font-size="11" fill="#fff" fill-opacity="0.85" stroke="${INK}" stroke-width="3" paint-order="stroke">${v}</text>`;
    });
    out += `<circle cx="${tx}" cy="${ty}" r="30" fill="none" stroke="#fff" stroke-opacity="0.45" stroke-width="3"/>`;
    out += `<circle cx="${tx}" cy="${ty}" r="20" fill="none" stroke="#fff" stroke-opacity="0.8" stroke-width="3"/>`;
    out += `<circle cx="${tx}" cy="${ty}" r="10" fill="${acc}" stroke="${INK}" stroke-width="4"/>`;
  }
  return out + '</svg>';
}

export function mouthOnly(id, vowel) {
  // Head crop around the mouth for the mouth sheet.
  return `<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" viewBox="50 60 200 200">${scene(id, 300, 300).replace(/^/, '')}${character(id, { vowel })}</svg>`;
}

export const palettes = Object.fromEntries(ORDER.map((id) => [id, { name: CH[id].name, ...CH[id].palette }]));

// ---- CLI: write files
if (process.argv[1].endsWith('gen.mjs')) {
  const out = new URL('./out/', import.meta.url).pathname;
  fs.mkdirSync(out, { recursive: true });
  for (const id of ORDER) {
    fs.writeFileSync(`${out}card-${id}.svg`, composite(id, 300, 300, { vowel: 0.5 }));
  }
  for (const id of ['monk', 'dog', 'ghost']) {
    VOWELS.forEach((v, i) => fs.writeFileSync(`${out}mouth-${id}-${v}.svg`, mouthOnly(id, i / 4)));
  }
  fs.writeFileSync(`${out}scene-portrait.svg`, composite('monk', 374, 470, { vowel: 0.62, touch: [92, 160], loud: 0.4 }));
  fs.writeFileSync(`${out}scene-landscape.svg`, composite('fish', 812, 226, { vowel: 0.3, touch: [600, 120] }));
  fs.writeFileSync(`${out}scene-strip.svg`, composite('punk', 359, 104, { vowel: 0.8, touch: [250, 40], charScale: 1.0 }));
  fs.writeFileSync(`${out}palettes.json`, JSON.stringify(palettes, null, 1));
  // contact sheet for local review
  const files = fs.readdirSync(out).filter((f) => f.endsWith('.svg'));
  const html = `<html><body style="margin:0;background:#222;display:flex;flex-wrap:wrap;gap:8px;padding:8px">${files.map((f) => `<div style="color:#ccc;font:10px sans-serif"><img src="${f}"><br>${f}</div>`).join('')}</body></html>`;
  fs.writeFileSync(`${out}sheet.html`, html);
  console.log('wrote', files.length);
}
