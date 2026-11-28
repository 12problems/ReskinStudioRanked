# Reskin Studio Ranked

Customize Balatro's textures, sounds and text **in Ranked**.

This mod contains **no art, sounds or text of its own**, and it never runs code from your files. It loads plain data files (PNG, OGG and JSON) from a separate **reskin pack** folder that lives *outside* the mod. Ranked verification checks the mod folder, so the same approved mod works for everyone, whatever pack they use.

## How to use it

1. Install the mod with the **Balatro Essentials Toolkit** launcher and add it to your profile.
2. Make a pack:
   - in the **Custom Reskin Studio** on the Balatro Multiplayer website (*Export for Ranked*), or
   - convert an existing **Malverk** texture pack in the launcher: *Tools → Manage Reskin Packs → Convert Malverk Pack*.
3. Pick the pack for your profile (*Tools → Manage Reskin Packs*, or the **Textures** button on the Mods page) and launch.

The launcher checks every file in your pack before a Ranked launch, and tells the game where the pack is through the `BET_RESKIN_DIR` environment variable. Without a pack, the mod does nothing.

## What a pack can contain

- Textures for jokers, tarots, planets, spectrals, vouchers, boosters, enhancers, decks, seals, tags, blinds and stakes.
- Playing card faces: as selectable deck skins (low and high contrast), or replacing the default faces.
- Stake chips, and the shop sign.
- Animated art and floating soul layers for single cards, and default shaders (visual only).
- Custom sheets with art for objects added by other mods.
- Replacement sounds and music (`.ogg`).
- Text changes (`localization/<language>.json`).

The full format is in `FORMAT.md` (included here, and in the GitHub repository).

## Requirements

- [Steamodded](https://thunderstore.io/c/balatro/p/Steamodded/Steamodded/) and [Malverk](https://thunderstore.io/c/balatro/p/Eremel_Mods/Malverk/), installed automatically as dependencies.
- For packs and Ranked: the Balatro Essentials Toolkit launcher.

## Links

- Source and format: https://github.com/12problems/ReskinStudioRanked
