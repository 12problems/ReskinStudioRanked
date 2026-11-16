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
