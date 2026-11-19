-- Keeping the hidden proxy network in sync with the floor.
--
-- The whole feature is driven by a queue of dirty 32x32 chunks. Work only
-- happens when a floor tile appears or disappears, and the queue is drained a
-- few chunks at a time, so the mod costs nothing at all while idle and cannot
-- stall a tick when a large blueprint is built.
--
-- Every chunk stores its own covering, and a chunk's proxies are only ever
-- wired to proxies of the neighbouring chunks whose supply square touches
-- theirs. That means the electric network follows the actual shape of the
-- floor: two separate floors never share power.

local constants = require("scripts.constants")
local coverage = require("scripts.coverage")
local proxies = require("scripts.proxies")

local floors = {}

local CHUNK = constants.CHUNK_SIZE
local TILE_NAME = constants.TILE_NAME

------------------------------------------------------------------------------
-- state
------------------------------------------------------------------------------

local function new_state()
	return {
		queue = {}, -- [key] = {surface = <name>, cx = <int>, cy = <int>}
		pending = {}, -- keys of `queue`, in insertion order
		head = 1, -- first unprocessed entry of `pending`
		count = 0, -- last used index of `pending`
	}
end

-- Storage access is intentionally split in two: `state` may create the table
-- and is only ever called from events, while the pass reader below must not
-- touch storage at all (it also runs before the first event of a save).
local function state()
	local s = storage.electric_floor
	if not s then
		s = new_state()
		storage.electric_floor = s
	end
	return s
end

--- Reads one of our runtime-global settings. The mod-name prefix Factorio
--- applies to settings is not worth guessing, so both spellings are accepted.
local function setting(name, fallback)
	local direct = settings.global[name]
	if direct then return direct.value end

	local prefixed = settings.global["electric-floor-" .. name]
	if prefixed then return prefixed.value end

	return fallback
end

floors.setting = setting

------------------------------------------------------------------------------
-- queue
------------------------------------------------------------------------------

--- Queue the chunk that contains this position.
--- @param surface LuaSurface
--- @param position MapPosition
--- @param rewire boolean? re-wire every proxy of the chunk, not just new ones
function floors.mark(surface, position, rewire)
	local s = state()

	local cx = math.floor(position.x / CHUNK)
	local cy = math.floor(position.y / CHUNK)
	local key = surface.name .. "|" .. cx .. "|" .. cy

	local queued = s.queue[key]
	if queued then
		if rewire then queued.rewire = true end
		return
	end

	s.queue[key] = {surface = surface.name, cx = cx, cy = cy, rewire = rewire}
	s.count = s.count + 1
	s.pending[s.count] = key
end

--- Wires a proxy to every touching proxy and to every real pole standing on
--- the floor within its supply area.
local function join_network(surface, proxy)
	local radius = proxies.radius_from_name(proxy.name)
	local position = proxy.position

	-- One search per proxy size, reaching exactly as far as a proxy of that
	-- size can be and still touch. A single search wide enough for the largest
	-- size returned every small proxy around - hundreds on a half-built floor -
	-- only to discard all but the few that touch.
	for i = 1, #constants.SIZES do
		local other_radius = constants.SIZES[i] / 2
		local reach = radius + other_radius + 0.01

		local candidates = surface.find_entities_filtered {
			name = constants.PROXY_NAMES[i],
			area = {
				{position.x - reach, position.y - reach},
				{position.x + reach, position.y + reach},
			},
		}

		for j = 1, #candidates do
			local other = candidates[j]

			if other.valid and other ~= proxy and proxies.touch(position, radius, other.position, other_radius) then
				proxies.connect(proxy, other)
			end
		end
	end

	-- A pole that already stood here before the floor was laid has to join too,
	-- which is the same check the build event uses. A pole only has to be able
	-- to power part of the floor, so the search reaches out by the largest
	-- supply radius any pole prototype has (a substation reaches 9 tiles out).
	local margin = constants.max_pole_supply_radius() + 1
	-- Real poles only, by name: searching by type also returned every proxy.
	local poles = surface.find_entities_filtered {
		name = constants.real_pole_names(),
		area = {
			{position.x - radius - margin, position.y - radius - margin},
			{position.x + radius + margin, position.y + radius + margin},
		},
	}

	for i = 1, #poles do
		local pole = poles[i]

		if pole.valid and not proxies.is_proxy(pole.name) then
			local supply = proxies.supply_radius(pole)

			if proxies.touch(position, radius, pole.position, supply) then proxies.connect(proxy, pole) end
		end
	end
end

--- Brings one chunk's proxies in line with its floor tiles.
local function rebuild_chunk(job)
	local surface = game.surfaces[job.surface]
	if not surface or not surface.valid then return end

	local x0, y0 = job.cx * CHUNK, job.cy * CHUNK
	local area = {{x0, y0}, {x0 + CHUNK, y0 + CHUNK}}

	local desired = coverage.cover_chunk(surface, x0, y0)

	-- Compare against what is already there instead of rebuilding blindly:
	-- creating and destroying entities is far more expensive than a few string
	-- comparisons, and most edits (a tile placed inside one big square, a
	-- machine built on the floor, ...) do not change the covering at all.
	local obsolete = {}
	for _, entity in ipairs(surface.find_entities_filtered {name = constants.PROXY_NAMES, area = area}) do
		obsolete[proxies.entity_key(entity)] = entity
	end

	local live = {}
	local missing = {}

	for i = 1, #desired do
		local wanted = desired[i]
		local key = proxies.position_key(wanted.name, wanted.x, wanted.y)
		local existing = obsolete[key]

		if existing then
			obsolete[key] = nil -- unchanged proxy, keep it and its wires
			live[#live + 1] = existing
		else
			missing[#missing + 1] = wanted
		end
	end

	for _, entity in pairs(obsolete) do
		if entity.valid then entity.destroy() end
	end

	-- Only new proxies need wiring: a kept proxy kept its wires, and whatever it
	-- lost to a destroyed neighbour comes back when the replacement joins it.
	-- Re-wiring every kept proxy on every edit was most of the mod's cost.
	if not job.rewire then live = {} end

	for i = 1, #missing do
		local wanted = missing[i]
		local entity = surface.create_entity {
			name = wanted.name,
			position = {x = wanted.x, y = wanted.y},
			force = "neutral",
			preserve_ghosts_and_corpses = true,
		}

		if entity then
			entity.destructible = false
			live[#live + 1] = entity
		end
	end

	for i = 1, #live do
		local proxy = live[i]
		if proxy.valid then join_network(surface, proxy) end
	end
end

--- Processes up to `max` queued chunks (`max` = nil drains everything).
--- @param max number?
--- @return number amount of chunks rebuilt
local function drain(max)
	local s = state()
	local done = 0

	while s.head <= s.count and (max == nil or done < max) do
		local key = s.pending[s.head]
		s.pending[s.head] = nil
		s.head = s.head + 1

		local job = s.queue[key]
		if job then
			s.queue[key] = nil
			rebuild_chunk(job)
			done = done + 1
		end
	end

	if s.head > s.count then
		s.pending = {}
		s.head = 1
		s.count = 0
	end

	return done
end

--- Drains a few queued chunks. Registered as the nth-tick handler, so this is
--- the only code that runs while the factory is idle.
function floors.pass()
	local s = storage.electric_floor
	if not s or s.head > s.count then return end

	drain(setting(constants.SETTING_BUDGET, 1))
end

--- Drains the whole queue at once. Much more expensive than a regular pass, so
--- it is only reachable on demand.
function floors.drain_now()
	local s = storage.electric_floor
	if s and s.head <= s.count then drain(nil) end
end

------------------------------------------------------------------------------
-- events
------------------------------------------------------------------------------

--- Player or robot placed tiles: the new tile is on the event itself, the tile
--- that was replaced is on every entry.
local function on_tiles_built(event)
	local surface = game.surfaces[event.surface_index]
	if not surface then return end

	local new_is_floor = event.tile and event.tile.name == TILE_NAME
	local tiles = event.tiles

	for i = 1, #tiles do
		local entry = tiles[i]
		local old_is_floor = entry.old_tile and entry.old_tile.name == TILE_NAME

		-- Only a tile that appears or disappears changes the network.
		if new_is_floor ~= old_is_floor then floors.mark(surface, entry.position) end
	end
end

--- Player or robot removed tiles. The event does not say what is underneath, so
--- the payload can only tell us whether a floor tile went away.
local function on_tiles_mined(event)
	local surface = game.surfaces[event.surface_index]
	if not surface then return end

	local tiles = event.tiles

	for i = 1, #tiles do
		local entry = tiles[i]
		if entry.old_tile and entry.old_tile.name == TILE_NAME then floors.mark(surface, entry.position) end
	end
end

--- Undo/redo, the map editor and other mods. These entries only carry the name
--- of the tile that was set, not what was there before, so the chunk is queued
--- unconditionally - rebuilding it is a no-op when nothing relevant changed.
local function on_tiles_set(event)
	local surface = game.surfaces[event.surface_index]
	if not surface then return end

	local tiles = event.tiles

	for i = 1, #tiles do
		floors.mark(surface, tiles[i].position)
	end
end

local function on_pole_built(event)
	local entity = event.entity
	if not (entity and entity.valid) then return end
	if proxies.is_proxy(entity.name) then return end

	local surface = entity.surface

	-- Join the floor network right now. This is what makes a pole placed on an
	-- already conducting floor conduct in the very same tick.
	local connected = proxies.connect_pole(surface, entity)

	-- Safety net: if that attempt found nothing, queue the pole's chunk so the
	-- next update pass verifies it. A pole that the game has just built is not
	-- fully initialised while this event runs, so the attempt above can fail
	-- even though the pole does stand next to the floor. Rebuilding is diffed,
	-- so this costs nothing when nothing changed - and it means pulling a pole
	-- out and putting it straight back cannot leave the floor without power.
	if connected == 0 and proxies.can_reach_floor(entity) then
		floors.mark(surface, entity.position)
	end
end

local function on_tile_ghost_removed(event)
	local entity = event.entity
	if entity and entity.valid then floors.mark(entity.surface, entity.position) end
end

--- Rebuilds every chunk that contains a floor tile. Used when the mod is added
--- to an existing save and exposed through the remote interface.
function floors.rescan()
	for _, surface in pairs(game.surfaces) do
		for _, tile in ipairs(surface.find_tiles_filtered {name = TILE_NAME}) do
			floors.mark(surface, tile.position, true)
		end
	end
end

local function schedule()
	script.on_nth_tick(setting(constants.SETTING_INTERVAL, 1), floors.pass)
end

function floors.register()
	-- Tile events take no filters, so they can share one registration each.
	script.on_event({
		defines.events.on_player_built_tile,
		defines.events.on_robot_built_tile,
	}, on_tiles_built)

	script.on_event({
		defines.events.on_player_mined_tile,
		defines.events.on_robot_mined_tile,
	}, on_tiles_mined)

	script.on_event(defines.events.script_raised_set_tiles, on_tiles_set)

	-- Deconstruction planners remove tiles by destroying their tile ghost.
	script.on_event(
		defines.events.script_raised_destroy,
		on_tile_ghost_removed,
		{{filter = "type", type = "deconstructible-tile-proxy"}}
	)

	-- Filters may only be used when registering a single event, so the three
	-- build events are registered one by one. Filtering in the engine keeps this
	-- mod out of the way while belts and rails are being built.
	local pole_filter = {{filter = "type", type = "electric-pole"}}
	script.on_event(defines.events.on_built_entity, on_pole_built, pole_filter)
	script.on_event(defines.events.on_robot_built_entity, on_pole_built, pole_filter)
	script.on_event(defines.events.script_raised_built, on_pole_built, pole_filter)

	script.on_init(function()
		storage.electric_floor = new_state()
	end)

	script.on_configuration_changed(function(event)
		state()

		-- Only a change to this mod can invalidate the proxies; rescanning on
		-- every unrelated mod update would be wasted work.
		local change = event.mod_changes and event.mod_changes["electric-floor"]
		if change then floors.rescan() end
	end)

	script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
		if event.setting == constants.SETTING_INTERVAL or event.setting == "electric-floor-" .. constants.SETTING_INTERVAL then
			script.on_nth_tick(nil)
			schedule()
		end
	end)

	schedule()
end

return floors
