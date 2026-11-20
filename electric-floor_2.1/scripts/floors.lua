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
