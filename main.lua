--- ReskinStudioRanked loader.
--
-- Ships NO art, sounds or text, and never executes user-supplied code. It reads
-- plain data files (PNG / OGG / JSON) from a user folder that lives OUTSIDE this
-- mod's own folder, so Ranked's folder-hash verification of this mod is never
-- affected by what the user customizes. See FORMAT.md for the folder layout.
--
-- User folder resolution:
--   1. BET_RESKIN_DIR env var (set by the Balatro Essentials Toolkit launcher,
--      per profile). This is the only source honoured in a Ranked Run.
--   2. <this mod>/user/  -- convenience for Casual/manual installs. Putting files
--      here changes this mod's folder hash, so Ranked verification will reject it.

local mod = SMODS.current_mod
local TAG = 'ReskinStudioRanked'

local function warn(msg) sendWarnMessage(msg, TAG) end
local function info(msg) sendInfoMessage(msg, TAG) end

-- ---------------------------------------------------------------------------
-- Locate the user folder
-- ---------------------------------------------------------------------------
local function normalize_dir(p)
	if not p or p == '' then return nil end
	p = p:gsub('\\', '/')
	if p:sub(-1) ~= '/' then p = p .. '/' end
	return p
end

local USER_DIR = normalize_dir(os.getenv('BET_RESKIN_DIR'))
if not USER_DIR then
	local fallback = normalize_dir(mod.path .. 'user')
	local ok, st = pcall(NFS.getInfo, fallback)
	if ok and st and st.type == 'directory' then USER_DIR = fallback end
end

if not USER_DIR then
	info('No user folder (BET_RESKIN_DIR unset, no user/ folder): nothing to apply.')
	return
end
info('Using user folder: ' .. USER_DIR)

-- Steamodded builds asset paths as `<mod.path> .. 'assets/<n>x/' .. file`.
-- Pointing that at the user folder makes it load user files. The proxy keeps
-- every other field (id, prefix, ...) of the real mod.
local user_mod = setmetatable({ path = USER_DIR }, { __index = mod })

local function file_exists(path)
	local ok, st = pcall(NFS.getInfo, path)
	return ok and st and st.type == 'file'
end

-- ---------------------------------------------------------------------------
-- Optional reskin.json: per-sheet `keys` (restrict which objects a sheet applies
-- to, so a sheet only has to contain the cells the user actually edited).
-- ---------------------------------------------------------------------------
local config = {}
do
	local raw = file_exists(USER_DIR .. 'reskin.json') and NFS.read(USER_DIR .. 'reskin.json')
	if raw then
		local ok, parsed = pcall(JSON.decode, raw)
		if ok and type(parsed) == 'table' then
			config = parsed
		else
			warn('reskin.json is not valid JSON; ignoring it.')
		end
	end
end

-- ---------------------------------------------------------------------------
-- Textures (through Malverk)
-- ---------------------------------------------------------------------------
-- file name (without .png) -> Malverk set. Each file is a sheet in the SAME layout
-- as the vanilla sheet for that set (Malverk `original_sheet`).
local SHEETS = {
	{ file = 'jokers',    set = 'Joker',    label = 'Jokers' },
	{ file = 'tarots',    set = 'Tarot',    label = 'Tarot Cards' },
	{ file = 'planets',   set = 'Planet',   label = 'Planet Cards' },
	{ file = 'spectrals', set = 'Spectral', label = 'Spectral Cards' },
	{ file = 'vouchers',  set = 'Voucher',  label = 'Vouchers' },
	{ file = 'boosters',  set = 'Booster',  label = 'Booster Packs' },
	{ file = 'enhancers', set = 'Enhanced', label = 'Card Enhancements' },
	{ file = 'decks',     set = 'Back',     label = 'Decks' },
	{ file = 'seals',     set = 'Seal',     label = 'Seals' },
	{ file = 'tags',      set = 'Tag',      label = 'Tags' },
	{ file = 'blinds',    set = 'Blind',    label = 'Blinds', frames = 21 },
	{ file = 'stakes',    set = 'Stake',    label = 'Stakes' },
}

local function sheet_present(name)
	return file_exists(USER_DIR .. 'assets/1x/' .. name .. '.png')
		or file_exists(USER_DIR .. 'assets/2x/' .. name .. '.png')
end

local texture_keys = {}

for _, s in ipairs(SHEETS) do
	if sheet_present(s.file) then
		local def = {
			key = s.file,
			set = s.set,
			path = s.file .. '.png',
			original_sheet = true,
			frames = s.frames,
			loc_txt = { name = 'Custom ' .. s.label },
		}
		local sheet_cfg = type(config.sheets) == 'table' and config.sheets[s.file] or nil
		if type(sheet_cfg) == 'table' and type(sheet_cfg.keys) == 'table' then
			local keys = {}
			for _, k in ipairs(sheet_cfg.keys) do
				if type(k) == 'string' then keys[#keys + 1] = k end
			end
			if #keys > 0 then def.keys = keys end
		end
		local alt = AltTexture(def)
		-- AltTexture forbids a pre-set `mod`, but reads `self.mod.path` at inject
		-- time (via SMODS.Atlas); swap in the proxy now that it is registered.
		alt.mod = user_mod
		texture_keys[#texture_keys + 1] = alt.key
		info('Registered sheet ' .. s.file .. ' (' .. s.set .. ')')
	end
end

-- ---------------------------------------------------------------------------
-- Custom sheets: art for objects that are NOT on a vanilla sheet (objects added
-- by other mods, e.g. a multiplayer joker). reskin.json maps a name to
--   { "set": "Joker", "keys": ["j_mp_ticket"], "px": 71, "py": 95 }
-- and the image is assets/<n>x/custom_<name>.png, laid out PACKED: key i is cell
-- i, left to right then top to bottom (what Malverk does for `keys` without
-- `original_sheet`). Data only; see FORMAT.md.
-- ---------------------------------------------------------------------------
do
	local CUSTOM_SETS = {
		Joker = true, Tarot = true, Planet = true, Spectral = true,
		Voucher = true, Booster = true, Enhanced = true, Back = true,
	}
	local MAX_CUSTOM_SHEETS, MAX_CUSTOM_KEYS = 64, 400

	local function whole(n, lo, hi)
		return type(n) == 'number' and n % 1 == 0 and n >= lo and n <= hi
	end

	if type(config.custom) == 'table' then
		local names = {}
		for name in pairs(config.custom) do
			if type(name) == 'string' then names[#names + 1] = name end
		end
		table.sort(names) -- pairs() order is not stable; keep texture order deterministic
		for i, name in ipairs(names) do
			if i > MAX_CUSTOM_SHEETS then
				warn('Too many custom sheets; ignoring the rest.')
				break
			end
			local entry = config.custom[name]
			local file = 'custom_' .. name
			local keys = {}
			if type(entry) == 'table' and type(entry.keys) == 'table' then
				for _, k in ipairs(entry.keys) do
					if type(k) == 'string' and #k <= 64 and k:match('^[%w_]+$') and #keys < MAX_CUSTOM_KEYS then
						keys[#keys + 1] = k
					end
				end
			end
			local px = type(entry) == 'table' and entry.px ~= nil and entry.px or 71
			local py = type(entry) == 'table' and entry.py ~= nil and entry.py or 95
			if #name <= 32 and name:match('^[a-z0-9_]+$') and type(entry) == 'table'
				and CUSTOM_SETS[entry.set] and #keys > 0 and whole(px, 1, 256) and whole(py, 1, 256)
				and sheet_present(file) then
				local alt = AltTexture({
					key = file,
					set = entry.set,
					path = file .. '.png',
					keys = keys,
					px = px,
					py = py,
					loc_txt = { name = 'Custom ' .. name },
				})
				alt.mod = user_mod
				texture_keys[#texture_keys + 1] = alt.key
				info('Registered custom sheet ' .. name .. ' (' .. entry.set .. ', ' .. #keys .. ' key(s))')
			else
				warn('Ignoring custom sheet "' .. name .. '": invalid entry or missing ' .. file .. '.png.')
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Whole sheets: art that is not a Malverk-managed object. Both scales must be
-- present and exactly the vanilla size (the launcher checks this), and the file
-- has to be complete (a blank cell is blank in game). Pure image data; no code is
-- read from the folder. See FORMAT.md.
--
--   cards.png    the playing card faces (13x4 cells, vanilla 8BitDeck layout).
--                Malverk has no playing-card set, and the game's default deck skin
--                reads the atlas `cards_1` directly, so this replaces that atlas.
--                Other deck skins (including Malverk-era packs') ship their own
--                atlases and are unaffected. The same file also replaces the
--                high-contrast sheet (cards_2), so players on the high-contrast
--                palette see the pack too (the Studio edits one sheet only).
--   shopsign.png the shop sign animation. Nothing manages that sprite but its
--                atlas, so it replaces the game's shop_sign atlas in place.
-- ---------------------------------------------------------------------------
local WHOLE_SHEETS = {
	{ file = 'cards',    atlas = 'cards_1',   px = 71,  py = 95 },
	{ file = 'cards',    atlas = 'cards_2',   px = 71,  py = 95 },
	{ file = 'shopsign', atlas = 'shop_sign', px = 113, py = 57, frames = 4 },
}

for _, s in ipairs(WHOLE_SHEETS) do
	if file_exists(USER_DIR .. 'assets/1x/' .. s.file .. '.png')
		and file_exists(USER_DIR .. 'assets/2x/' .. s.file .. '.png') then
		SMODS.Atlas({
			key = s.atlas,
			path = s.file .. '.png',
			path_mod = user_mod,
			px = s.px,
			py = s.py,
			frames = s.frames,
			atlas_table = s.frames and 'ANIMATION_ATLAS' or 'ASSET_ATLAS',
			prefix_config = { key = false }, -- keep the vanilla key so it replaces the game's sheet
		})
		info('Registered whole sheet ' .. s.file .. ' (replaces ' .. s.atlas .. ')')
	elseif sheet_present(s.file) and s.atlas ~= 'cards_2' then
		warn('Ignoring ' .. s.file .. '.png: both assets/1x and assets/2x are required.')
	end
end

-- ---------------------------------------------------------------------------
-- Deck skins: selectable playing card skins (Customize Deck), each a pair of
-- complete 13x4 face sheets (low / high contrast). reskin.json declares them:
--   "deckSkins": { "<id>": { "name": "My skin" } }
-- and the images are assets/<n>x/deckskin_<id>_lc.png / deckskin_<id>_hc.png
-- (either variant may be missing; the other one is used for both). Both scales
-- are required per image. Nothing is selected automatically.
-- ---------------------------------------------------------------------------
local function prefixed(key)
	return ((mod.prefix and mod.prefix ~= '') and (mod.prefix .. '_') or '') .. key
end

local function both_scales(name)
	return file_exists(USER_DIR .. 'assets/1x/' .. name .. '.png')
		and file_exists(USER_DIR .. 'assets/2x/' .. name .. '.png')
end

local function whole_number(n, lo, hi)
	return type(n) == 'number' and n % 1 == 0 and n >= lo and n <= hi
end

local function sorted_string_keys(t)
	local out = {}
	for k in pairs(t) do
		if type(k) == 'string' then out[#out + 1] = k end
	end
	table.sort(out) -- pairs() order is not stable; keep registration order deterministic
	return out
end

do
	local MAX_DECK_SKINS = 16
	local RANKS = { '2', '3', '4', '5', '6', '7', '8', '9', '10', 'Jack', 'Queen', 'King', 'Ace' }
	local SUITS = { 'Hearts', 'Clubs', 'Diamonds', 'Spades' }

	if type(config.deckSkins) == 'table' then
		for i, id in ipairs(sorted_string_keys(config.deckSkins)) do
			if i > MAX_DECK_SKINS then
				warn('Too many deck skins; ignoring the rest.')
				break
			end
			local entry = config.deckSkins[id]
			local lc_file, hc_file = 'deckskin_' .. id .. '_lc', 'deckskin_' .. id .. '_hc'
			local has_lc = both_scales(lc_file)
			local has_hc = both_scales(hc_file)
			if #id <= 40 and id:match('^[a-z0-9_]+$') and type(entry) == 'table' and (has_lc or has_hc) then
				local name = type(entry.name) == 'string' and entry.name:gsub('%c', ''):sub(1, 64) or ''
				if name == '' then name = id end
				local function register(file, present)
					if not present then return nil end
					SMODS.Atlas({ key = file, path = file .. '.png', path_mod = user_mod, px = 71, py = 95 })
					return prefixed(file)
				end
				local low = register(lc_file, has_lc)
				local high = register(hc_file, has_hc)
				low, high = low or high, high or low
				for _, suit in ipairs(SUITS) do
					local function palette(key, atlas, hc)
						return {
							key = key,
							ranks = RANKS,
							display_ranks = { 'King', 'Queen', 'Jack' },
							atlas = atlas,
							pos_style = 'deck',
							hc_default = hc,
						}
					end
					SMODS.DeckSkin({
						key = 'deckskin_' .. id .. '_' .. string.lower(suit),
						suit = suit,
						loc_txt = name,
						palettes = { palette('lc', low, false), palette('hc', high, true) },
					})
				end
				info('Registered deck skin ' .. id)
			else
				warn('Ignoring deck skin "' .. id:sub(1, 40) .. '": invalid entry or missing image.')
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Rebinds: art for single objects that cannot live on a shared vanilla sheet:
-- animations (GIF-style frame strips) and floating "soul" overlay layers.
--   "atlases": { "<name>": { "px": 71, "py": 95, "frames": 4, "fps": 10 } }
--       image assets/<n>x/atlas_<name>.png, both scales; `frames` makes it an
--       animation strip (frames cells wide), otherwise a plain grid of cells.
--   "objects": [ { "registry": "P_CENTERS", "key": "j_joker", "atlas": "<name>",
--                  "x": 0, "y": 0, "soul_atlas": "<name>", "soul_x": 0,
--                  "soul_y": 0, "soul_shared": false } ]
--       points that vanilla object (or just its soul layer) at a cell of an atlas.
-- Data only; the registries and keys are checked, no code is read. See FORMAT.md.
-- ---------------------------------------------------------------------------
do
	local MAX_ATLASES, MAX_OBJECTS = 64, 1000
	local REGISTRY = {
		P_CENTERS = function() return G.P_CENTERS end,
		P_BLINDS = function() return G.P_BLINDS end,
		P_TAGS = function() return G.P_TAGS end,
		P_SEALS = function() return G.P_SEALS end,
		P_STAKES = function() return G.P_STAKES end,
	}

	local atlas_defs = {}
	if type(config.atlases) == 'table' then
		for i, name in ipairs(sorted_string_keys(config.atlases)) do
			if i > MAX_ATLASES then
				warn('Too many atlases; ignoring the rest.')
				break
			end
			local a = config.atlases[name]
			local file = 'atlas_' .. name
			local frames_ok = a ~= nil and type(a) == 'table' and (a.frames == nil or whole_number(a.frames, 1, 64))
			local fps_ok = type(a) == 'table' and (a.fps == nil or (type(a.fps) == 'number' and a.fps >= 1 and a.fps <= 60))
			if #name <= 40 and name:match('^[a-z0-9_]+$') and type(a) == 'table'
				and whole_number(a.px, 1, 256) and whole_number(a.py, 1, 256) and frames_ok and fps_ok
				and both_scales(file) then
				SMODS.Atlas({
					key = file,
					path = file .. '.png',
					path_mod = user_mod,
					px = a.px,
					py = a.py,
					frames = a.frames,
					fps = a.fps,
					atlas_table = a.frames and 'ANIMATION_ATLAS' or 'ASSET_ATLAS',
				})
				atlas_defs[name] = prefixed(file)
				info('Registered atlas ' .. name)
			else
				warn('Ignoring atlas "' .. name:sub(1, 40) .. '": invalid entry or missing images.')
			end
		end
	end

	local objects = {}
	if type(config.objects) == 'table' then
		for i, o in ipairs(config.objects) do
			if i > MAX_OBJECTS then
				warn('Too many objects; ignoring the rest.')
				break
			end
			local good = type(o) == 'table' and REGISTRY[o.registry] ~= nil
				and type(o.key) == 'string' and #o.key <= 64 and o.key:match('^[%w_]+$') ~= nil
				and (o.atlas == nil or atlas_defs[o.atlas] ~= nil)
				and (o.soul_atlas == nil or atlas_defs[o.soul_atlas] ~= nil)
				and (o.atlas ~= nil or o.soul_atlas ~= nil)
			for _, f in ipairs({ 'x', 'y', 'soul_x', 'soul_y' }) do
				if good and o[f] ~= nil and not whole_number(o[f], 0, 255) then good = false end
			end
			if good then
				objects[#objects + 1] = {
					registry = o.registry,
					key = o.key,
					atlas = o.atlas and atlas_defs[o.atlas] or nil,
					x = o.x, y = o.y,
					soul_atlas = o.soul_atlas and atlas_defs[o.soul_atlas] or nil,
					soul_x = o.soul_x, soul_y = o.soul_y,
					soul_shared = o.soul_shared == true,
				}
			else
				warn('Ignoring an invalid entry in "objects".')
			end
		end
	end

	local function apply_object(o)
		local get = REGISTRY[o.registry]
		local tbl = get and get()
		local entry = tbl and tbl[o.key]
		if not entry then return false end
		if o.atlas then
			-- A floating layer falls back to the base atlas in Steamodded. Pin the
			-- original before changing the background, or vanilla soul_pos reads the
			-- replacement atlas at its old coordinates.
			if entry.soul_pos and not o.soul_atlas then
				entry.hc_soul_atlas = entry.hc_soul_atlas or entry.soul_atlas or entry.hc_atlas or entry.atlas or entry.set
				entry.lc_soul_atlas = entry.lc_soul_atlas or entry.soul_atlas or entry.lc_atlas or entry.atlas or entry.set
				entry.soul_atlas = entry.soul_atlas or entry.atlas or entry.set
			end
			entry.hc_atlas = nil
			entry.lc_atlas = nil
			entry.atlas = o.atlas
			entry.pos = { x = o.x or 0, y = o.y or 0 }
		end
		if o.soul_atlas and not o.soul_shared then
			entry.hc_soul_atlas = nil
			entry.lc_soul_atlas = nil
			entry.soul_atlas = o.soul_atlas
			entry.soul_pos = { x = o.soul_x or 0, y = o.soul_y or 0 }
		end
		if o.soul_atlas and o.soul_shared then
			-- The Soul's gem is G.shared_soul, not a floating center sprite: keep its
			-- vanilla animation but swap the shared sprite's texture and cell.
			local atlas = G.ASSET_ATLAS and G.ASSET_ATLAS[o.soul_atlas]
			if not G.shared_soul or not atlas then return false end
			local pos = G.shared_soul.sprite_pos or {}
			if G.shared_soul.atlas ~= atlas or pos.x ~= (o.soul_x or 0) or pos.y ~= (o.soul_y or 0) then
				G.shared_soul.atlas = atlas
				G.shared_soul:set_sprite_pos({ x = o.soul_x or 0, y = o.soul_y or 0 })
			end
		end
		return true
	end

	local function apply_all()
		local complete = true
		for _, o in ipairs(objects) do
			local ok, applied = pcall(apply_object, o)
			if not ok or not applied then complete = false end
		end
		return complete
	end

	if #objects > 0 then
		mod._rebinds_applied = G and G.P_CENTERS and apply_all() or false
		if not mod._rebinds_applied then
			-- G.shared_soul may be created after the prototype tables.
			local orig_update = Game.update
			function Game:update(dt)
				orig_update(self, dt)
				if not mod._rebinds_applied and G and G.P_CENTERS then
					mod._rebinds_applied = apply_all()
				end
			end
		end
		-- Texture-scaling changes can recreate G.shared_soul; rebind just before
		-- Steamodded's order-50 Soul draw. Its animation stays intact.
		if SMODS and SMODS.DrawStep then
			for _, o in ipairs(objects) do
				if o.soul_shared and o.soul_atlas then
					SMODS.DrawStep({
						key = 'rebind_shared_' .. o.key,
						order = 49,
						func = function(self)
							if self.config.center == G.P_CENTERS[o.key] then apply_object(o) end
						end,
					})
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Default shaders: a purely visual shader on specific cards, by vanilla center
-- key. "shaders": [ { "key": "j_joker", "shader": "foil" } ]. The shader name
-- must be one of the whitelisted visual shaders; no scoring effect.
-- ---------------------------------------------------------------------------
do
	local ALLOWED = {
		foil = true, holo = true, polychrome = true, negative = true, voucher = true,
		booster = true, hologram = true, debuff = true, gold_seal = true,
	}
	local ALIAS = { gold_seal = 'voucher' }
	local by_key, count = {}, 0
	if type(config.shaders) == 'table' then
		for i, s in ipairs(config.shaders) do
			if i > 1000 then
				warn('Too many shaders; ignoring the rest.')
				break
			end
			if type(s) == 'table' and type(s.key) == 'string' and #s.key <= 64 and s.key:match('^[%w_]+$')
				and type(s.shader) == 'string' and ALLOWED[s.shader] then
				by_key[s.key] = s.shader
				count = count + 1
			else
				warn('Ignoring an invalid entry in "shaders".')
			end
		end
	end
	if count > 0 and SMODS and SMODS.DrawStep then
		local function center_key(card)
			local c = card.config
			return c and (c.center_key or (c.center and c.center.key))
		end
		SMODS.DrawStep({
			key = 'default_shader',
			order = 21, -- just after the edition step (order 20)
			func = function(self)
				local raw = by_key[center_key(self)]
				if not raw then return end
				local name = ALIAS[raw] or raw
				local send = self.ARGS and self.ARGS.send_to_shader
				self.children.center:draw_shader(name, nil, send)
				if raw == 'negative' then self.children.center:draw_shader('negative_shine', nil, send) end
				local hide_front = self.should_hide_front and self:should_hide_front()
				if self.children.front and not hide_front then
					self.children.front:draw_shader(name, nil, send)
					if raw == 'negative' then self.children.front:draw_shader('negative_shine', nil, send) end
				end
			end,
		})
		info('Registered ' .. count .. ' default shader(s)')
	end
end

if #texture_keys > 0 then
	TexturePack({
		key = 'user_pack',
		textures = texture_keys,
		loc_txt = {
			name = 'Reskin Studio',
			text = { 'Your custom textures,', 'loaded from your profile.' },
		},
	})
end

-- ---------------------------------------------------------------------------
-- Sounds and music: assets/sounds/<vanilla_key>.ogg replaces that sound.
-- ---------------------------------------------------------------------------
do
	local ok, items = pcall(NFS.getDirectoryItems, USER_DIR .. 'assets/sounds')
	if ok and type(items) == 'table' then
		for _, f in ipairs(items) do
			local key = f:match('^([%w_%-]+)%.ogg$')
			if key then
				SMODS.Sound({ key = key, path = f, replace = key, path_mod = user_mod })
				info('Registered sound ' .. key)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Localization: localization/<lang>.json, data only (strings / arrays of
-- strings / objects). Merged over the game's own localization after it loads.
-- ---------------------------------------------------------------------------
local MAX_DEPTH, MAX_STRING = 8, 4000

local function is_clean(v, depth)
	local t = type(v)
	if t == 'string' then return #v <= MAX_STRING end
	if t ~= 'table' or depth > MAX_DEPTH then return false end
	for k, child in pairs(v) do
		if type(k) ~= 'string' and type(k) ~= 'number' then return false end
		if not is_clean(child, depth + 1) then return false end
	end
	return true
end

local function deep_merge(dst, src)
	for k, v in pairs(src) do
		if type(v) == 'table' and type(dst[k]) == 'table' then
			deep_merge(dst[k], v)
		else
			dst[k] = v
		end
	end
end

local function load_loc_file(lang)
	local path = USER_DIR .. 'localization/' .. lang .. '.json'
	if not file_exists(path) then return nil end
	local ok, parsed = pcall(JSON.decode, NFS.read(path))
	if not ok or type(parsed) ~= 'table' then
		warn(lang .. '.json is not valid JSON; ignoring it.')
		return nil
	end
	if not is_clean(parsed, 1) then
		warn(lang .. '.json contains disallowed values; ignoring it.')
		return nil
	end
	return parsed
end

local init_loc_ref = init_localization
function init_localization()
	init_loc_ref()
	local lang = G.SETTINGS and (G.SETTINGS.real_language or G.SETTINGS.language) or 'en-us'
	local data = load_loc_file(lang)
	if data and G.localization then
		deep_merge(G.localization, data)
		info('Applied localization ' .. lang .. '.json')
	end
end
