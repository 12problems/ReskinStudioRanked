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
  size cap per file (proposed 8 MiB).
- `.ogg`: valid Ogg Vorbis, size cap per file (proposed 20 MiB; music tracks are large),
  total folder cap (proposed 200 MiB).
- `.json`: valid UTF-8 JSON; only strings / arrays / objects, depth <= 8, strings <= 4000
  chars, size cap (proposed 1 MiB).

## Producers

- **Reskin Studio "Export for Ranked"** (`reskin/lib/generateRanked.ts` in the website repo):
  places each edited object's art at its vanilla cell, writes vanilla-size sheets at 1x and 2x,
  and a `reskin.json` whose `keys` list exactly the edited objects. Localization edits become
  `localization/<lang>.json`. It drops soul overlays, default shaders, GIF frames after the
  first, playing-card/chip/shop-sign sheets and the mod icon (with a warning), and the bundle
  carries no project file. The Studio's "Import pack" reads such a bundle back (`importRanked.ts`:
  STORE zips only, allow-listed paths, exact vanilla sheet sizes, same size caps as the launcher),
  recovering the final art and text but not the uncropped sources or fit/edge settings.

## Out of scope for v1

Stake stickers, soul/floating layers, Malverk toggle textures, shaders. The Studio's
non-Ranked CustomReskin export is unchanged.
