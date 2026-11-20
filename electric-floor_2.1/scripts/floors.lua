<<<<<<< HEAD
-- When you lay or remove electric concrete, the mod marks the affected chunks for an update.
-- A solid square of concrete is easy to wire up, but a patchy floor can need a lot of hidden poles.
-- We spread the work over several ticks so a big paving job does not try to rebuild the whole grid at once.
local C=require('scripts.constants')
local P=require('scripts.proxies')
local jobs=require('scripts.jobs')
local floors={}
local function new_state()return {queue={},pending={},head=1,count=0,poles={},pole_head=1,pole_count=0,pole_pending={}}end
local function state()
 local s=storage.electric_floor
 if not s then s=new_state();storage.electric_floor=s end
 -- Keep any queued floor updates when loading a save from an older version.
 -- Set up a separate queue for regular electric poles if the save does not already have one.
 s.poles=s.poles or {};s.pole_head=s.pole_head or 1;s.pole_count=s.pole_count or 0;s.pole_pending=s.pole_pending or {}
 return s
end
-- The setting is registered as pass-interval, for example, so check that name before the older prefixed one.
function floors.setting(name,fallback)
 local plain=name:gsub('^electric%-floor%-','')
 local value=settings.global[plain] or settings.global[name] or settings.global['electric-floor-'..name]
 return value and value.value or fallback
end
local function has_work(s)return s.active or s.scan or s.head<=s.count or s.pole_head<=s.pole_count end
local function activate()script.on_event(defines.events.on_tick,floors.work_tick)end
function floors.mark(surface,position,repair)
 local s=state();local cx,cy=math.floor(position.x/32),math.floor(position.y/32)
 local key=surface.name..'|'..cx..'|'..cy
 if s.queue[key]then s.queue[key].repair=s.queue[key].repair or repair;return end
 s.queue[key]={surface=surface.name,cx=cx,cy=cy,repair=repair}
 s.count=s.count+1;s.pending[s.count]=key
end
local function mark_pole(entity)
 local s=state();local id=entity.unit_number
 if not id or s.pole_pending[id]then return end
 s.pole_count=s.pole_count+1;s.poles[s.pole_count]=entity;s.pole_pending[id]=true
 -- When you build a regular electric pole, add it to the queue first.
 -- The mod checks which patches of electric concrete it can reach in a later step.
 activate()
end
local function scan_one(s)
 local scan=s.scan;if not scan then return end
 local index=scan.surfaces[scan.i]
 if not index then s.scan=nil;return end
 local surface=game.surfaces[index]
 if not(surface and surface.valid)then scan.i=scan.i+1;scan.iterator=nil;return end
 if not scan.iterator then scan.iterator=surface.get_chunks()end
 if not scan.iterator.valid then scan.i=scan.i+1;scan.iterator=nil;return end
 local chunk=scan.iterator()
 if not chunk then scan.i=scan.i+1;scan.iterator=nil;return end
 if surface.is_chunk_generated(chunk)then
  local area={{chunk.x*32,chunk.y*32},{chunk.x*32+32,chunk.y*32+32}}
  if surface.count_tiles_filtered{name=C.TILE_NAME,area=area,limit=1}>0 or surface.count_entities_filtered{name=C.PROXY_NAMES,area=area,limit=1}>0 then
   floors.mark(surface,{x=chunk.x*32,y=chunk.y*32},true)
  end
 end
end
-- Pick a waiting regular pole before starting another chunk, then let the chosen job finish before switching again.
local function next_job(s)
 while s.pole_head<=s.pole_count do
  local pole=s.poles[s.pole_head];s.poles[s.pole_head]=nil;s.pole_head=s.pole_head+1
  if pole and pole.valid then s.pole_pending[pole.unit_number]=nil;return jobs.pole(pole)end
 end
 s.poles={};s.pole_head=1;s.pole_count=0;s.pole_pending={}
 while s.head<=s.count do
  local key=s.pending[s.head];s.pending[s.head]=nil;s.head=s.head+1
  local job=s.queue[key];s.queue[key]=nil
  if job then return jobs.new(job)end
 end
 s.pending={};s.head=1;s.count=0
end
-- A tick can be reached through either update hook, so count the work budget only once per tick.
function floors.work_tick()
 local s=storage.electric_floor
 if not s or not has_work(s)then script.on_event(defines.events.on_tick,nil);return end
 if s.last_work_tick==game.tick then return end
 s.last_work_tick=game.tick
 local budget=floors.setting('work-per-tick',64)
 local completed=0;local chunk_limit=floors.setting(C.SETTING_BUDGET,8)
 -- While a rescan is running, check up to one generated chunk per work tick.
 -- Queue a repair only for chunks with electric concrete or hidden poles left over from an earlier layout.
 if s.scan then scan_one(s);budget=budget-1 end
 for _=1,budget do
  if not s.active then s.active=next_job(s)end
  if not s.active then break end
  if jobs.step(s.active)then
   s.active=nil;completed=completed+1
   if completed>=chunk_limit then break end
  end
 end
 if not has_work(s)then
  s.pending={};s.head=1;s.count=0;s.poles={};s.pole_head=1;s.pole_count=0;s.pole_pending={}
  script.on_event(defines.events.on_tick,nil)
 end
end
function floors.pass()
 local s=storage.electric_floor
 if s and has_work(s)then activate();floors.work_tick()end
end
function floors.drain_now()
 local s=state()
 -- rescan_now finishes the entire floor check before the game continues.
 -- Normal building and paving let the floor catch up over several ticks.
 while has_work(s)do
  if s.scan then scan_one(s)end
  if not s.active then s.active=next_job(s)end
  if s.active and jobs.step(s.active)then s.active=nil end
 end
 script.on_event(defines.events.on_tick,nil)
end
function floors.rescan()
 local s=state();s.scan={surfaces={},i=1}
 for index in pairs(game.surfaces)do s.scan.surfaces[#s.scan.surfaces+1]=index end
 table.sort(s.scan.surfaces);activate()
end
local function on_tiles_built(event)
 local surface=game.surfaces[event.surface_index];if not surface then return end
 local new_is_floor=event.tile and event.tile.name==C.TILE_NAME
 for _,entry in ipairs(event.tiles)do
  local old=entry.old_tile and entry.old_tile.name==C.TILE_NAME
  if new_is_floor~=old then floors.mark(surface,entry.position)end
 end
end
local function on_tiles_mined(event)
 local surface=game.surfaces[event.surface_index];if not surface then return end
 for _,entry in ipairs(event.tiles)do if entry.old_tile and entry.old_tile.name==C.TILE_NAME then floors.mark(surface,entry.position)end end
end
local function on_tiles_set(event)
 local surface=game.surfaces[event.surface_index];if not surface then return end
 for _,entry in ipairs(event.tiles)do floors.mark(surface,entry.position)end
end
local function on_pole_built(event)
 local entity=event.entity
 if entity and entity.valid and not P.is_proxy(entity.name)then mark_pole(entity)end
end
local function schedule()script.on_nth_tick(floors.setting(C.SETTING_INTERVAL,15),floors.pass)end
function floors.register()
 script.on_event({defines.events.on_player_built_tile,defines.events.on_robot_built_tile},on_tiles_built)
 script.on_event({defines.events.on_player_mined_tile,defines.events.on_robot_mined_tile},on_tiles_mined)
 script.on_event(defines.events.script_raised_set_tiles,on_tiles_set)
 script.on_event(defines.events.script_raised_destroy,function(event)
  local e=event.entity;if e and e.valid then floors.mark(e.surface,e.position)end
 end,{{filter='type',type='deconstructible-tile-proxy'}})
 for _,event in ipairs({defines.events.on_built_entity,defines.events.on_robot_built_entity,defines.events.script_raised_built,defines.events.script_raised_revive})do
  script.on_event(event,on_pole_built,{{filter='type',type='electric-pole'}})
 end
 script.on_init(function()storage.electric_floor=new_state()end)
 script.on_load(function()
  local s=storage.electric_floor
  if s and (s.active or s.scan or s.head<=s.count or (s.pole_head or 1)<=(s.pole_count or 0))then activate()end
 end)
 script.on_configuration_changed(function(event)
  state()
  if event.mod_changes and event.mod_changes['electric-floor']then floors.rescan()end
 end)
 script.on_event(defines.events.on_runtime_mod_setting_changed,function(event)
  if event.setting=='pass-interval' or event.setting==C.SETTING_INTERVAL then script.on_nth_tick(nil);schedule()end
 end)
 schedule()
end
return floors
=======
-- When you lay or remove electric concrete, the mod marks the affected chunks for an update.
-- A solid square of concrete is easy to wire up, but a patchy floor can need a lot of hidden poles.
-- We spread the work over several ticks so a big paving job does not try to rebuild the whole grid at once.

local constants = require("scripts.constants")
local proxies = require("scripts.proxies")
local jobs = require("scripts.jobs")

local CHUNK = constants.CHUNK_SIZE

local floors = {}

local function new_state()
	return {
		queue = {}, -- [key] = {surface = <name>, cx = <int>, cy = <int>, repair = <boolean>}
		pending = {}, -- keys of `queue`, in insertion order
		head = 1, -- first unprocessed entry of `pending`
		count = 0, -- last used index of `pending`
		poles = {}, -- regular electric poles waiting to join the floor network
		pole_head = 1, -- first unprocessed entry of `poles`
		pole_count = 0, -- last used index of `poles`
		pole_pending = {}, -- [unit_number] = true while that pole is queued
		ticking = false, -- whether the per-tick work handler is registered
	}
end

local function state()
	local s = storage.electric_floor
	if not s then
		s = new_state()
		storage.electric_floor = s
	end

	-- Keep any queued floor updates when loading a save from an older version,
	-- and set up the pole queue and the tick flag if the save does not have them.
	s.poles = s.poles or {}
	s.pole_head = s.pole_head or 1
	s.pole_count = s.pole_count or 0
	s.pole_pending = s.pole_pending or {}
	s.ticking = s.ticking or false

	return s
end

--- Reads one of our runtime-global settings. The setting is registered without
--- the mod-name prefix, but both spellings are accepted so a lookup cannot
--- silently fall back to a default.
--- @param name string
--- @param fallback any
function floors.setting(name, fallback)
	local plain = name:gsub("^electric%-floor%-", "")
	local value = settings.global[plain] or settings.global[name] or settings.global["electric-floor-" .. name]

	return value and value.value or fallback
end

local function has_work(s)
	return s.active or s.scan or s.head <= s.count or (s.pole_head or 1) <= (s.pole_count or 0)
end

--- Registers or removes the per-tick work handler. The flag is stored so that a
--- client joining the game restores exactly the handler state the host has,
--- instead of deriving it from the queue and disagreeing for a while.
local function set_ticking(on)
	local s = storage.electric_floor

	if on then
		script.on_event(defines.events.on_tick, floors.work_tick)
	else
		script.on_event(defines.events.on_tick, nil)
	end

	if s then s.ticking = on end
end

local function activate() set_ticking(true) end
local function deactivate() set_ticking(false) end

--- Queue the chunk that contains this position.
--- @param surface LuaSurface
--- @param position MapPosition
--- @param repair boolean? re-wire every proxy of the chunk, not just new ones
function floors.mark(surface, position, repair)
	local s = state()

	local cx = math.floor(position.x / CHUNK)
	local cy = math.floor(position.y / CHUNK)
	local key = surface.name .. "|" .. cx .. "|" .. cy

	local queued = s.queue[key]
	if queued then
		queued.repair = queued.repair or repair
		return
	end

	s.queue[key] = {surface = surface.name, cx = cx, cy = cy, repair = repair}
	s.count = s.count + 1
	s.pending[s.count] = key
end

--- Queue a regular electric pole so the floor network can be joined to it.
local function mark_pole(entity)
	local s = state()
	local id = entity.unit_number
	if not id or s.pole_pending[id] then return end

	s.pole_count = s.pole_count + 1
	s.poles[s.pole_count] = entity
	s.pole_pending[id] = true
	activate()
end

--- Reads one chunk of one surface while a rescan is running.
local function scan_one(s)
	local scan = s.scan
	if not scan then return end

	local index = scan.surfaces[scan.i]
	if not index then
		s.scan = nil
		return
	end

	local surface = game.surfaces[index]
	if not (surface and surface.valid) then
		scan.i = scan.i + 1
		scan.iterator = nil
		return
	end

	if not scan.iterator then scan.iterator = surface.get_chunks() end

	if not scan.iterator.valid then
		scan.i = scan.i + 1
		scan.iterator = nil
		return
	end

	local chunk = scan.iterator()
	if not chunk then
		scan.i = scan.i + 1
		scan.iterator = nil
		return
	end

	if surface.is_chunk_generated(chunk) then
		local x0, y0 = chunk.x * CHUNK, chunk.y * CHUNK
		local area = {{x0, y0}, {x0 + CHUNK, y0 + CHUNK}}
		local has_tiles = surface.count_tiles_filtered {name = constants.TILE_NAME, area = area, limit = 1} > 0
		local has_poles = surface.count_entities_filtered {name = constants.PROXY_NAMES, area = area, limit = 1} > 0

		if has_tiles or has_poles then floors.mark(surface, {x = x0, y = y0}, true) end
	end
end

--- Pick a waiting regular pole before starting another chunk, then let the
--- chosen job finish before switching again.
local function next_job(s)
	while (s.pole_head or 1) <= (s.pole_count or 0) do
		local pole = s.poles[s.pole_head]
		s.poles[s.pole_head] = nil
		s.pole_head = s.pole_head + 1

		if pole and pole.valid then
			s.pole_pending[pole.unit_number] = nil
			return jobs.pole(pole)
		end
	end

	s.poles = {}
	s.pole_head = 1
	s.pole_count = 0
	s.pole_pending = {}

	while s.head <= s.count do
		local key = s.pending[s.head]
		s.pending[s.head] = nil
		s.head = s.head + 1

		local job = s.queue[key]
		s.queue[key] = nil
		if job then return jobs.new(job) end
	end

	s.pending = {}
	s.head = 1
	s.count = 0
end

--- Runs the next piece of queued work. Registered on both update hooks while
--- work is waiting, so the budget is spent every tick.
function floors.work_tick()
	local s = storage.electric_floor
	if not s or not has_work(s) then
		deactivate()
		return
	end

	-- A tick can be reached through either update hook, so count the work budget only once per tick.
	if s.last_work_tick == game.tick then return end
	s.last_work_tick = game.tick

	local budget = floors.setting(constants.SETTING_WORK, 64)
	local job_limit = floors.setting(constants.SETTING_JOB_LIMIT, 1)
	local completed = 0

	-- While a rescan is running, check up to one generated chunk per work tick.
	-- Queue a repair only for chunks with electric concrete or hidden poles left over from an earlier layout.
	if s.scan then
		scan_one(s)
		budget = budget - 1
	end

	for _ = 1, budget do
		if not s.active then s.active = next_job(s) end
		if not s.active then break end

		if jobs.step(s.active) then
			s.active = nil
			completed = completed + 1
			if completed >= job_limit then break end
		end
	end

	if not has_work(s) then
		s.pending = {}
		s.head = 1
		s.count = 0
		s.poles = {}
		s.pole_head = 1
		s.pole_count = 0
		s.pole_pending = {}
		deactivate()
	end
end

--- Starts queued work. Registered as the nth-tick handler, so this is the only
--- code that runs while the factory is idle.
function floors.pass()
	local s = storage.electric_floor
	if s and has_work(s) then
		activate()
		floors.work_tick()
	end
end

--- Drains the whole queue at once. Much more expensive than a regular pass, so
--- it is only reachable on demand.
function floors.drain_now()
	local s = state()

	-- rescan_now finishes the entire floor check before the game continues.
	-- Normal building and paving let the floor catch up over several ticks.
	while has_work(s) do
		if s.scan then scan_one(s) end
		if not s.active then s.active = next_job(s) end
		if s.active and jobs.step(s.active) then s.active = nil end
	end

	deactivate()
end

--- Checks every generated chunk for floor tiles and queues the ones that need a
--- repair. The scan itself is spread over ticks as well.
function floors.rescan()
	local s = state()
	s.scan = {surfaces = {}, i = 1}

	for index in pairs(game.surfaces) do
		s.scan.surfaces[#s.scan.surfaces + 1] = index
	end

	table.sort(s.scan.surfaces)
	activate()
end

--- Player or robot placed tiles: the new tile is on the event itself, the tile
--- that was replaced is on every entry.
local function on_tiles_built(event)
	local surface = game.surfaces[event.surface_index]
	if not surface then return end

	local new_is_floor = event.tile and event.tile.name == constants.TILE_NAME

	for _, entry in ipairs(event.tiles) do
		local old_is_floor = entry.old_tile and entry.old_tile.name == constants.TILE_NAME

		-- Only a tile that appears or disappears changes the network.
		if new_is_floor ~= old_is_floor then floors.mark(surface, entry.position) end
	end
end

--- Player or robot removed tiles. The event does not say what is underneath, so
--- the payload can only tell us whether a floor tile went away.
local function on_tiles_mined(event)
	local surface = game.surfaces[event.surface_index]
	if not surface then return end

	for _, entry in ipairs(event.tiles) do
		if entry.old_tile and entry.old_tile.name == constants.TILE_NAME then floors.mark(surface, entry.position) end
	end
end

--- Undo/redo, the map editor and other mods. These entries only carry the name
--- of the tile that was set, not what was there before, so the chunk is queued
--- unconditionally - rebuilding it is a no-op when nothing relevant changed.
local function on_tiles_set(event)
	local surface = game.surfaces[event.surface_index]
	if not surface then return end

	for _, entry in ipairs(event.tiles) do
		floors.mark(surface, entry.position)
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

	-- Safety net: if that attempt found nothing, queue the pole so the next
	-- ticks can finish the job. A pole that the game has just built is not fully
	-- initialised while this event runs, so the attempt above can fail even
	-- though the pole does stand next to the floor - and it means pulling a pole
	-- out and putting it straight back cannot leave the floor without power.
	if connected == 0 and proxies.can_reach_floor(entity) then mark_pole(entity) end
end

local function on_tile_ghost_removed(event)
	local entity = event.entity
	if entity and entity.valid then floors.mark(entity.surface, entity.position) end
end

local function schedule()
	script.on_nth_tick(floors.setting(constants.SETTING_INTERVAL, 1), floors.pass)
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

	-- Filters may only be used when registering a single event, so the build
	-- events are registered one by one. Filtering in the engine keeps this mod
	-- out of the way while belts and rails are being built.
	local pole_filter = {{filter = "type", type = "electric-pole"}}
	for _, event in ipairs({
		defines.events.on_built_entity,
		defines.events.on_robot_built_entity,
		defines.events.script_raised_built,
		defines.events.script_raised_revive,
	}) do
		script.on_event(event, on_pole_built, pole_filter)
	end

	script.on_init(function()
		storage.electric_floor = new_state()
	end)

	-- Only the stored flag tells a joining client whether the host is currently
	-- running the per-tick handler; the queue alone cannot, because the next
	-- pass may be up to `pass-interval` ticks away.
	script.on_load(function()
		local s = storage.electric_floor
		if s and s.ticking then script.on_event(defines.events.on_tick, floors.work_tick) end
	end)

	script.on_configuration_changed(function(event)
		state()

		-- Only a change to this mod can invalidate the proxies; rescanning on
		-- every unrelated mod update would be wasted work.
		if event.mod_changes and event.mod_changes["electric-floor"] then floors.rescan() end
	end)

	script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
		if event.setting == "pass-interval" or event.setting == constants.SETTING_INTERVAL then
			script.on_nth_tick(nil)
			schedule()
		end
	end)

	schedule()
end

return floors
>>>>>>> 2d8be52 (Fixes focus on de-sync for multiplayer, also remove dead codes, and some small fixes)
