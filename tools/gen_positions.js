// Regenerates positions.json from the Reskin Studio catalog (website repo) plus
// the few positions the catalog lacks. Usage:
//   node tools/gen_positions.js <path to reskin/data/catalog.json>
// positions.json is the single source of truth for "which vanilla cell does
// object <key> live in on sheet <file>"; the launcher importer, the Studio
// importer and the Ranked exporter must all agree with it.
const fs = require('fs')
const catalog = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))

const SHEETS = {
  Joker: ['jokers', 10, 16], Tarot: ['tarots', 10, 6], Planet: ['planets', 10, 6],
  Spectral: ['spectrals', 10, 6], Voucher: ['vouchers', 9, 4], Booster: ['boosters', 4, 9],
  Enhanced: ['enhancers', 7, 5], Back: ['decks', 7, 5], Seal: ['seals', 7, 5],
  Tag: ['tags', 6, 5], Blind: ['blinds', 21, 31],
}
// Not in the catalog. Seal cells: Enhancers.png. Stake cells: read from the
// game's own game.lua (P_STAKES), chips.png.
const SEAL_POS = { Gold: [2, 0], Red: [5, 4], Blue: [6, 4], Purple: [4, 4] }
const STAKE_POS = {
  stake_white: [0, 0], stake_red: [1, 0], stake_green: [2, 0], stake_black: [4, 0],
  stake_blue: [3, 0], stake_purple: [0, 1], stake_orange: [1, 1], stake_gold: [2, 1],
}

const out = { version: 1, sheets: {} }
for (const cat of catalog.spriteCategories) {
  const spec = SHEETS[cat.id]
  if (!spec) continue
  const cells = {}
  for (const o of catalog.spriteObjects[cat.id]) {
    const p = cat.id === 'Seal' ? SEAL_POS[o.key] : o.pos && [o.pos.x, o.pos.y]
    if (!p) throw new Error(`no position for ${cat.id}/${o.key}`)
    cells[o.key] = cat.frames > 1 ? [0, p[1]] : p
  }
  out.sheets[spec[0]] = {
    set: cat.id, cellW: cat.px, cellH: cat.py, cols: spec[1], rows: spec[2],
    ...(cat.frames > 1 ? { frames: cat.frames } : {}), cells,
  }
}
out.sheets.stakes = { set: 'Stake', cellW: 29, cellH: 29, cols: 5, rows: 2, cells: STAKE_POS }
// Explicit key order (JSON object order is not preserved by every reader, e.g. Qt).
for (const v of Object.values(out.sheets)) v.order = Object.keys(v.cells)
fs.writeFileSync(__dirname + '/../positions.json', JSON.stringify(out, null, 1) + '\n')
console.log(Object.entries(out.sheets).map(([k, v]) => `${k}: ${Object.keys(v.cells).length}`).join(', '))
