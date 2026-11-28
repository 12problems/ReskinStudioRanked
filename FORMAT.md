# ReskinStudioRanked user-folder format (v1)

The approved mod (`ReskinStudioRanked`) contains **no art, sounds or text**. Everything
the player customizes lives in a separate **user folder**, which Ranked verification
never hashes. The launcher, the Reskin Studio's "Ranked" export, and the Malverk
importers all read/write exactly this layout.

## Where the folder is

- The launcher creates one per profile and passes its path to the game as the
  `BET_RESKIN_DIR` environment variable (a `Z:\...` path under Proton, like
  `LOVELY_MOD_DIR`).
- Casual/manual fallback: `<mod folder>/user/` (changes the mod's hash, so Ranked rejects it).
- No folder, or an empty one: the mod does nothing.

## Layout

```
<user folder>/
  reskin.json                optional, see below
  assets/
    1x/<sheet>.png           optional, any subset of the sheets below
    2x/<sheet>.png           optional; if only one scale exists, Steamodded scales it
    1x/custom_<name>.png     optional, see "Custom sheets" (declared in reskin.json)
    2x/custom_<name>.png
    1x/deckskin_<id>_lc.png  optional, see "Deck skins" (declared in reskin.json)
    2x/deckskin_<id>_hc.png  (and _lc / _hc at each scale)
    1x/atlas_<name>.png      optional, see "Rebinds: animations and soul layers"
    2x/atlas_<name>.png
    sounds/<key>.ogg         optional; replaces the vanilla sound/music `<key>`
  localization/<lang>.json   optional; <lang> is a game language code (en-us, fr, ...)
```

Nothing is required. Every file that is absent simply leaves vanilla in place.

## Texture sheets

A sheet is a PNG in the **same cell layout as the vanilla sheet** for that object type
(Malverk's `original_sheet`). Cell size and grid are the vanilla ones; the 2x file is
exactly twice the 1x dimensions.

| file          | Malverk set | 1x size (2x = double) | cell (1x) | vanilla sheet |
|---------------|-------------|-----------------------|-----------|---------------|
| `jokers`      | Joker       | 710x1520              | 71x95     | Jokers.png |
| `tarots`      | Tarot       | 710x570               | 71x95     | Tarots.png |
| `planets`     | Planet      | 710x570               | 71x95     | Tarots.png |
| `spectrals`   | Spectral    | 710x570               | 71x95     | Tarots.png |
| `vouchers`    | Voucher     | 639x380               | 71x95     | Vouchers.png |
| `boosters`    | Booster     | 284x855               | 71x95     | boosters.png |
| `enhancers`   | Enhanced    | 497x475               | 71x95     | Enhancers.png |
| `decks`       | Back        | 497x475               | 71x95     | Enhancers.png |
| `seals`       | Seal        | 497x475               | 71x95     | Enhancers.png |
| `tags`        | Tag         | 204x170               | 34x34     | tags.png |
| `blinds`      | Blind       | 714x1054 (21 frames)  | 34x34     | BlindChips.png |
| `stakes`      | Stake       | 145x58                | 29x29     | chips.png |

Two more sheets are **whole sheets**: they are not objects Malverk manages. They have no `keys`
list, the file must be complete (a blank cell is blank in game), and **both `assets/1x` and
`assets/2x` must be present** (the mod ignores the sheet otherwise).

| File          | 1x size               | Cell      | Vanilla file |
|---------------|-----------------------|-----------|--------------|
| `cards`       | 923x380 (13x4)        | 71x95     | 8BitDeck.png (ranks across, suits down) |
| `shopsign`    | 452x57 (4 frames)     | 113x57    | ShopSignAnimation.png |

- `cards` replaces the game's `cards_1` atlas (what the default deck skin reads). Malverk has no
  playing-card set, and deck skins that ship their own atlases, Malverk-era packs included, are
  unaffected. The same file also replaces the high-contrast sheet (`cards_2`), so players on the
  high-contrast palette see the pack too.
- `shopsign` replaces the game's `shop_sign` animation atlas in place; nothing else manages it.

Dimensions are read from the game's own `resources/textures/1x` and enforced exactly by the launcher.

`tarots`, `planets`, `spectrals`, `enhancers`, `decks` and `seals` are each laid out like
the vanilla sheet they live on (`Tarots.png`, `Enhancers.png`), and only apply to their
own object type.

### Partial sheets: `reskin.json`

A sheet applies to every object of its type unless `reskin.json` restricts it:

```json
{
  "version": 1,
  "sheets": {
    "jokers": { "keys": ["j_joker", "j_greedy_joker"] }
  }
}
```

With `keys`, only those object keys read their cell from the sheet; the rest stay
vanilla, so the sheet only has to contain those cells. Without `keys`, a missing or
transparent cell shows as missing/blank.

### Custom sheets: objects added by other mods

Objects that are not on a vanilla sheet (for example a joker added by another mod) have no
vanilla cell to reuse, so they get a **custom sheet**: a PNG laid out **packed** (the
object's key list in order, left to right then top to bottom, the way Malverk lays out a
texture that lists `keys` without `original_sheet`), declared in `reskin.json`:

```json
{
  "version": 1,
  "custom": {
    "ticket": { "set": "Joker", "keys": ["j_mp_ticket"], "px": 71, "py": 95 }
  }
}
```

- The image is `assets/1x/custom_<name>.png` (and optionally `assets/2x/custom_<name>.png`,
  exactly double). `<name>` matches `^[a-z0-9_]{1,32}$`.
- `set` is one of `Joker`, `Tarot`, `Planet`, `Spectral`, `Voucher`, `Booster`, `Enhanced`, `Back`.
- `keys`: 1 to 400 object keys, each matching `^[A-Za-z0-9_]{1,64}$`. Key *i* reads cell *i*.
  Keys that don't exist in the running game are ignored.
- `px`, `py`: cell size in 1x pixels, whole numbers 1 to 256 (default 71x95).
- The 1x image's width and height must be whole multiples of `px` and `py`, no larger than
  2048 pixels per side, and have at least as many cells as `keys`.
- At most 64 custom sheets.

## Deck skins

Selectable playing-card skins (they appear under Customize Deck; nothing is selected for the
player). Declared in `reskin.json`:

```json
{ "version": 1, "deckSkins": { "my_skin": { "name": "My skin" } } }
```

- `<id>` matches `^[a-z0-9_]{1,40}$`; `name` is plain text, at most 64 characters. At most 16 skins.
- Images: `assets/<n>x/deckskin_<id>_lc.png` (low contrast) and `deckskin_<id>_hc.png` (high
  contrast). Each is a complete 13x4 face sheet, 923x380 at 1x (the same layout as `cards`),
  and needs **both** `assets/1x` and `assets/2x`. Either contrast may be omitted; the other one
  is used for both.
- Unlike `cards`, a deck skin adds an option instead of replacing the game's default faces.

## Rebinds: animations and soul layers

Art for single objects that can't share a vanilla sheet: animated art (a strip of frames)
and the floating "soul" layer of legendary jokers, The Soul, Hologram and similar cards.
`reskin.json` declares small atlases and then points vanilla objects at cells of them:

```json
{
  "version": 1,
  "atlases": {
    "joker_anim": { "px": 71, "py": 95, "frames": 4, "fps": 10 },
    "joker_soul": { "px": 71, "py": 95 }
  },
  "objects": [
    { "registry": "P_CENTERS", "key": "j_joker", "atlas": "joker_anim", "x": 0, "y": 0 },
    { "registry": "P_CENTERS", "key": "j_perkeo", "soul_atlas": "joker_soul", "soul_x": 0, "soul_y": 0 },
    { "registry": "P_CENTERS", "key": "c_soul", "soul_atlas": "joker_soul", "soul_x": 1, "soul_y": 0, "soul_shared": true }
  ]
}
```

- Atlas image: `assets/<n>x/atlas_<name>.png`, both scales. `<name>` matches
  `^[a-z0-9_]{1,40}$`. `px`/`py` are whole numbers 1 to 256. With `frames` (1 to 64) the atlas
  is an animation strip, `frames` cells wide and one cell tall, played at `fps` (1 to 60, default
  10). Without it, it is a plain grid. Both scales exactly double; whole cells; at most 2048
  pixels per side at 1x. At most 64 atlases.
- Object: `registry` is one of `P_CENTERS`, `P_BLINDS`, `P_TAGS`, `P_SEALS`, `P_STAKES`; `key` matches
  `^[A-Za-z0-9_]{1,64}$` (a key missing from the running game is ignored). `atlas` + `x`/`y`
  replaces the object's art; `soul_atlas` + `soul_x`/`soul_y` replaces only its floating layer
  (`soul_shared: true` for The Soul, whose gem is a shared sprite). `x`/`y` default to 0 and
  are whole numbers 0 to 255. Every `atlas` / `soul_atlas` must name a declared atlas. At most 1000 objects.
- A transparent cell hides a floating layer.

## Default shaders

A purely visual shader on specific cards, by vanilla center key (no scoring effect):

```json
{ "version": 1, "shaders": [ { "key": "j_joker", "shader": "foil" } ] }
```

`shader` is one of `foil`, `holo`, `polychrome`, `negative`, `voucher`, `booster`, `hologram`,
`debuff`, `gold_seal`. Up to 1000 entries; `key` matches `^[A-Za-z0-9_]{1,64}$`.

## Sounds and music

`assets/sounds/<key>.ogg`, where `<key>` is a vanilla sound or music key (`chips1`,
`music1`, ...). Filename must match `^[A-Za-z0-9_-]+\.ogg$`.

## Localization

`localization/<lang>.json` mirrors the structure of the game's localization table, as
JSON. Strings, arrays of strings and nested objects only:

```json
{
  "descriptions": {
    "Joker": {
      "j_joker": { "name": "Clown", "text": ["{C:mult}+#1#{} Mult"] }
    }
  },
  "misc": { "dictionary": { "k_hand": "Hands" } }
}
```

The mod merges it over the game's localization after load. It never loads Lua from the
user folder.

## Validation (launcher, before every Ranked Run)

The launcher enforces these; the mod additionally ignores anything that fails them.

- Only the paths above. Any other file, any symlink/junction, any path outside the layout: reject.
- `.png`: valid PNG, exact expected dimensions for the sheet (see table; 2x = 2 * 1x),
  size cap per file (proposed 8 MiB). Deck skin images are 923x380; atlas images follow their
  declared `px`/`py`/`frames`.
- `.ogg`: valid Ogg Vorbis, size cap per file (proposed 20 MiB; music tracks are large),
  total folder cap (proposed 200 MiB).
- `.json`: valid UTF-8 JSON; only strings / arrays / objects, depth <= 8, strings <= 4000
  chars, size cap (proposed 1 MiB).

## Producers

- **Reskin Studio "Export for Ranked"** (`reskin/lib/generateRanked.ts` in the website repo):
  places each edited object's art at its vanilla cell, writes vanilla-size sheets at 1x and 2x,
  and a `reskin.json` whose `keys` list exactly the edited objects. Localization edits become
  `localization/<lang>.json`. Stake chips become the `stakes` sheet and the shop sign the
  `shopsign` sheet. Each playing-card skin becomes a deck skin. Soul layers, uploaded GIF
  animations and default shaders become rebinds and shaders. It leaves out the mod icon (with a
  warning), and the bundle carries no project file. The Studio's "Import pack" reads such a
  bundle back (`importRanked.ts`: STORE zips only, allow-listed paths, exact sizes, same size
  caps as the launcher), recovering the final art and text but not the uncropped sources or
  fit/edge settings.

## Out of scope

Stake stickers, Malverk toggle textures, custom shaders. The Studio's non-Ranked CustomReskin
export is unchanged.
