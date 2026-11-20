-- Each chunk update works out which hidden poles the electric concrete needs.
-- It keeps poles that still fit, places and connects the new ones, then removes the old ones.
-- Wiring the replacements first helps keep the floor powered while the layout changes.
local C=require('scripts.constants')
local coverage=require('scripts.coverage')
local P=require('scripts.proxies')
local jobs={}
local function key(x,y,j) return (y-j.y0+1)*34+x-j.x0+2 end
local function bounds(entity)
 local r=P.radius_from_name(entity.name);local p=entity.position
 return math.floor(p.x-r+0.001),math.floor(p.y-r+0.001),math.ceil(p.x+r-0.001)-1,math.ceil(p.y+r-0.001)-1
end
local function add_grid(j,e)
 local l,t,r,b=bounds(e)
 for y=math.max(t,j.y0-1),math.min(b,j.y0+32)do
  for x=math.max(l,j.x0-1),math.min(r,j.x0+32)do j.grid[key(x,y,j)]=e end
 end
end
-- Look around the edge of this pole’s square, including the four corners, to find the hidden poles it should join.
local function links(j,e)
 local l,t,r,b=bounds(e);local result,seen={},{}
 local function at(x,y)
  if x<j.x0-1 or x>j.x0+32 or y<j.y0-1 or y>j.y0+32 then return end
  local other=j.grid[key(x,y,j)]
  if other and other.valid and other~=e and not seen[other.unit_number] then
   seen[other.unit_number]=true;result[#result+1]=other
  end
 end
 for x=l-1,r+1 do at(x,t-1);at(x,b+1)end
 for y=t,b do at(l-1,y);at(r+1,y)end
 return result
end
function jobs.new(job)
 return {surface=job.surface,cx=job.cx,cy=job.cy,repair=job.repair,x0=job.cx*32,y0=job.cy*32,phase='read'}
end
function jobs.pole(entity) return {surface=entity.surface.name,pole=entity,phase='pole-read'}end
-- Run the next piece of work, such as placing one hidden pole, checking a wire connection, or looking up nearby poles.
-- The job keeps its place across ticks and can pick up again after saving and loading.
function jobs.step(j)
 local surface=game.surfaces[j.surface]
 if not(surface and surface.valid)then return true end
 local phase=j.phase
 if phase=='pole-read'then
  if not(j.pole and j.pole.valid)then return true end
  local p=j.pole.position;local reach=P.supply_radius(j.pole)+C.MAX_RADIUS+1
  j.candidates=surface.find_entities_filtered{name=C.PROXY_NAMES,area={{p.x-reach,p.y-reach},{p.x+reach,p.y+reach}}}
  j.i=1;j.phase='pole-links'
 elseif phase=='pole-links'then
  if not j.pole.valid then return true end
  local other=j.candidates[j.i];if not other then return true end
  j.i=j.i+1
  if other.valid and P.touch(j.pole.position,P.supply_radius(j.pole),other.position,P.radius_from_name(other.name))then P.connect(j.pole,other)end
 elseif phase=='read'then
  j.desired=coverage.cover_chunk(surface,j.x0,j.y0)
  j.existing=surface.find_entities_filtered{name=C.PROXY_NAMES,area={{j.x0,j.y0},{j.x0+32,j.y0+32}}}
  j.obsolete={};j.live={};j.missing={};j.created={};j.i=1;j.phase='existing'
 elseif phase=='existing'then
  local e=j.existing[j.i]
  if not e then j.i=1;j.phase='diff'
  else j.obsolete[P.entity_key(e)]=e;j.i=j.i+1 end
 elseif phase=='diff'then
  local wanted=j.desired[j.i]
  if not wanted then
   j.remove={};for _,e in pairs(j.obsolete)do j.remove[#j.remove+1]=e end
   if #j.remove==0 and #j.missing==0 and not j.repair then return true end
   j.i=1;j.phase='create'
  else
   local k=P.position_key(wanted.name,wanted.x,wanted.y);local existing=j.obsolete[k]
   if existing and existing.valid then j.obsolete[k]=nil;j.live[#j.live+1]=existing
   else j.missing[#j.missing+1]=wanted end
   j.i=j.i+1
  end
 elseif phase=='create'then
  local wanted=j.missing[j.i]
  if not wanted then j.phase='grid-read'
  else
   local e=surface.create_entity{name=wanted.name,position={wanted.x,wanted.y},force='neutral',preserve_ghosts_and_corpses=true}
   if e then e.destructible=false;j.live[#j.live+1]=e;j.created[e.unit_number]=true end
   j.i=j.i+1
  end
 -- Look up nearby hidden poles once, then use the tile table to find neighbors when wiring each square.
 elseif phase=='grid-read'then
  j.candidates=surface.find_entities_filtered{name=C.PROXY_NAMES,area={{j.x0-17,j.y0-17},{j.x0+49,j.y0+49}}}
  j.grid={};j.i=1;j.phase='grid'
 elseif phase=='grid'then
  local e=j.candidates[j.i]
  if not e then j.candidates=nil;j.i=1;j.phase='wire'
  else
   if e.valid and not j.obsolete[P.entity_key(e)]then add_grid(j,e)end
   j.i=j.i+1
  end
 -- During normal paving, wire newly placed hidden poles and leave the existing connections in place.
 elseif phase=='wire'then
  local e=j.live[j.i]
  if not e then j.phase='poles-read'
  elseif not e.valid or(not j.repair and not j.created[e.unit_number])then j.i=j.i+1
  else j.links=links(j,e);j.link_index=1;j.phase='wire-links'end
 elseif phase=='wire-links'then
  local other=j.links[j.link_index]
  if not other then j.links=nil;j.i=j.i+1;j.phase='wire'
  else
   local e=j.live[j.i]
   if e.valid and other.valid then P.connect(e,other)end
   j.link_index=j.link_index+1
  end
 elseif phase=='poles-read'then
  local margin=C.max_pole_supply_radius()+1
  j.poles=surface.find_entities_filtered{type='electric-pole',area={{j.x0-margin,j.y0-margin},{j.x0+32+margin,j.y0+32+margin}}}
  j.real_poles={};j.i=1;j.phase='pole-filter'
 elseif phase=='pole-filter'then
  local pole=j.poles[j.i]
  if not pole then j.poles=j.real_poles;j.real_poles=nil;j.i=1;j.pole_index=1;j.phase='real-links'
  else if pole.valid and not P.is_proxy(pole.name)then j.real_poles[#j.real_poles+1]=pole end;j.i=j.i+1 end
 elseif phase=='real-links'then
  local e=j.live[j.i]
  if not e then j.i=1;j.phase='remove'
  elseif not e.valid or(not j.repair and not j.created[e.unit_number])then j.i=j.i+1;j.pole_index=1
  else
   local pole=j.poles[j.pole_index]
   if not pole then j.i=j.i+1;j.pole_index=1
   else
    if pole.valid and not P.is_proxy(pole.name) and P.touch(e.position,P.radius_from_name(e.name),pole.position,P.supply_radius(pole))then P.connect(e,pole)end
    j.pole_index=j.pole_index+1
   end
  end
 -- Remove the old hidden poles after connecting the replacements.
 elseif phase=='remove'then
  local e=j.remove[j.i];if not e then return true end
  if e.valid then e.destroy()end
  j.i=j.i+1
 end
 return false
end
return jobs
