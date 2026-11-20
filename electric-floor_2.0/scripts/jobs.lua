-- Each chunk update works out which hidden poles the electric concrete needs.
-- It keeps poles that still fit, places and connects the new ones, then removes the old ones.
-- Wiring the replacements first helps keep the floor powered while the layout changes.
--
-- A job is a small state machine: jobs.step() does one piece of work and returns
-- true when the job is finished, so a big rebuild is spread over many ticks
-- instead of running inside a single one.

local constants = require("scripts.constants")
local coverage = require("scripts.coverage")
local proxies = require("scripts.proxies")

local jobs = {}

local CHUNK = constants.CHUNK_SIZE

-- How far outside the chunk a proxy can still touch one inside it.
local MARGIN = constants.MAX_RADIUS + 1

-- The tile table holds the chunk plus a one tile border on every side.
local GRID = CHUNK + 2

--- Tile lookup key inside a job's grid, which spans x0 - 1 .. x0 + CHUNK.
--- @return integer
local function grid_key(x, y, job)
	return (y - job.y0 + 1) * GRID + (x - job.x0 + 1)
end

--- Supply square of a proxy, in whole tiles.
--- @return integer left, integer top, integer right, integer bottom
local function bounds(entity)
	local radius = proxies.radius_from_name(entity.name)
	local position = entity.position

	return math.floor(position.x - radius + 0.001),
		math.floor(position.y - radius + 0.001),
		math.ceil(position.x + radius - 0.001) - 1,
		math.ceil(position.y + radius - 0.001) - 1
end

local function add_grid(job, entity)
	local left, top, right, bottom = bounds(entity)

	for y = math.max(top, job.y0 - 1), math.min(bottom, job.y0 + CHUNK) do
		for x = math.max(left, job.x0 - 1), math.min(right, job.x0 + CHUNK) do
			job.grid[grid_key(x, y, job)] = entity
		end
	end
end

--- Look around the edge of this proxy's supply square, including the four
--- corners, to find the hidden poles it should join.
local function links(job, entity)
	local left, top, right, bottom = bounds(entity)
	local result, seen = {}, {}

	local function at(x, y)
		if x < job.x0 - 1 or x > job.x0 + CHUNK or y < job.y0 - 1 or y > job.y0 + CHUNK then return end

		local other = job.grid[grid_key(x, y, job)]
		if other and other.valid and other ~= entity and not seen[other.unit_number] then
			seen[other.unit_number] = true
			result[#result + 1] = other
		end
	end

	for x = left - 1, right + 1 do
		at(x, top - 1)
		at(x, bottom + 1)
	end

	for y = top, bottom do
		at(left - 1, y)
		at(right + 1, y)
	end

	return result
end

--- @param queued table entry of the dirty chunk queue
--- @return table job
function jobs.new(queued)
	return {
		surface = queued.surface,
		cx = queued.cx,
		cy = queued.cy,
		repair = queued.repair,
		x0 = queued.cx * CHUNK,
		y0 = queued.cy * CHUNK,
		phase = "read",
	}
end

--- @param entity LuaEntity
--- @return table job
function jobs.pole(entity)
	return {surface = entity.surface.name, pole = entity, phase = "pole-read"}
end

--- Runs the next piece of work, such as placing one hidden pole, checking a
--- wire connection, or looking up nearby poles.
--- The job keeps its place across ticks and can pick up again after saving and loading.
--- @return boolean finished
function jobs.step(job)
	local surface = game.surfaces[job.surface]
	if not (surface and surface.valid) then return true end

	local phase = job.phase

	if phase == "pole-read" then
		if not (job.pole and job.pole.valid) then return true end

		local position = job.pole.position
		local reach = proxies.supply_radius(job.pole) + constants.MAX_RADIUS + 1

		job.candidates = surface.find_entities_filtered {
			name = constants.PROXY_NAMES,
			area = {
				{position.x - reach, position.y - reach},
				{position.x + reach, position.y + reach},
			},
		}
		job.i = 1
		job.phase = "pole-links"
	elseif phase == "pole-links" then
		if not job.pole.valid then return true end

		local other = job.candidates[job.i]
		if not other then return true end
		job.i = job.i + 1

		if
			other.valid
			and proxies.touch(job.pole.position, proxies.supply_radius(job.pole), other.position, proxies.radius_from_name(other.name))
		then
			proxies.connect(job.pole, other)
		end
	elseif phase == "read" then
		job.desired = coverage.cover_chunk(surface, job.x0, job.y0)
		job.existing = surface.find_entities_filtered {
			name = constants.PROXY_NAMES,
			area = {{job.x0, job.y0}, {job.x0 + CHUNK, job.y0 + CHUNK}},
		}
		job.obsolete = {}
		job.live = {}
		job.missing = {}
		job.created = {}
		job.i = 1
		job.phase = "existing"
	elseif phase == "existing" then
		local entity = job.existing[job.i]
		if not entity then
			job.i = 1
			job.phase = "diff"
		else
			-- Anything can destroy a proxy while the job waits for its next step.
			if entity.valid then job.obsolete[proxies.entity_key(entity)] = entity end
			job.i = job.i + 1
		end
	elseif phase == "diff" then
		local wanted = job.desired[job.i]
		if not wanted then
			job.remove = {}
			for _, entity in pairs(job.obsolete) do job.remove[#job.remove + 1] = entity end

			if #job.remove == 0 and #job.missing == 0 and not job.repair then return true end

			job.i = 1
			job.phase = "create"
		else
			local wanted_key = proxies.position_key(wanted.name, wanted.x, wanted.y)
			local existing = job.obsolete[wanted_key]

			if existing and existing.valid then
				job.obsolete[wanted_key] = nil -- unchanged proxy, keep it and its wires
				job.live[#job.live + 1] = existing
			else
				job.missing[#job.missing + 1] = wanted
			end

			job.i = job.i + 1
		end
	elseif phase == "create" then
		local wanted = job.missing[job.i]
		if not wanted then
			job.phase = "grid-read"
		else
			local entity = surface.create_entity {
				name = wanted.name,
				position = {wanted.x, wanted.y},
				force = "neutral",
				preserve_ghosts_and_corpses = true,
			}

			if entity then
				entity.destructible = false
				job.live[#job.live + 1] = entity
				job.created[entity.unit_number] = true
			end

			job.i = job.i + 1
		end
	elseif phase == "grid-read" then
		-- Look up nearby hidden poles once, then use the tile table to find neighbours when wiring each square.
		job.candidates = surface.find_entities_filtered {
			name = constants.PROXY_NAMES,
			area = {
				{job.x0 - MARGIN, job.y0 - MARGIN},
				{job.x0 + CHUNK + MARGIN, job.y0 + CHUNK + MARGIN},
			},
		}
		job.grid = {}
		job.i = 1
		job.phase = "grid"
	elseif phase == "grid" then
		local entity = job.candidates[job.i]
		if not entity then
			job.candidates = nil
			job.i = 1
			job.phase = "wire"
		else
			if entity.valid and not job.obsolete[proxies.entity_key(entity)] then add_grid(job, entity) end
			job.i = job.i + 1
		end
	elseif phase == "wire" then
		-- During normal paving, wire newly placed hidden poles and leave the existing connections in place.
		local entity = job.live[job.i]
		if not entity then
			job.phase = "poles-read"
		elseif not entity.valid or (not job.repair and not job.created[entity.unit_number]) then
			job.i = job.i + 1
		else
			job.links = links(job, entity)
			job.link_index = 1
			job.phase = "wire-links"
		end
	elseif phase == "wire-links" then
		local other = job.links[job.link_index]
		if not other then
			job.links = nil
			job.i = job.i + 1
			job.phase = "wire"
		else
			local entity = job.live[job.i]
			if entity.valid and other.valid then proxies.connect(entity, other) end
			job.link_index = job.link_index + 1
		end
	elseif phase == "poles-read" then
		local margin = constants.max_pole_supply_radius() + 1

		job.poles = surface.find_entities_filtered {
			type = "electric-pole",
			area = {
				{job.x0 - margin, job.y0 - margin},
				{job.x0 + CHUNK + margin, job.y0 + CHUNK + margin},
			},
		}
		job.real_poles = {}
		job.i = 1
		job.phase = "pole-filter"
	elseif phase == "pole-filter" then
		local pole = job.poles[job.i]
		if not pole then
			job.poles = job.real_poles
			job.real_poles = nil
			job.i = 1
			job.pole_index = 1
			job.phase = "real-links"
		else
			if pole.valid and not proxies.is_proxy(pole.name) then job.real_poles[#job.real_poles + 1] = pole end
			job.i = job.i + 1
		end
	elseif phase == "real-links" then
		local entity = job.live[job.i]
		if not entity then
			job.i = 1
			job.phase = "remove"
		elseif not entity.valid or (not job.repair and not job.created[entity.unit_number]) then
			job.i = job.i + 1
			job.pole_index = 1
		else
			local pole = job.poles[job.pole_index]
			if not pole then
				job.i = job.i + 1
				job.pole_index = 1
			else
				if
					pole.valid
					and not proxies.is_proxy(pole.name)
					and proxies.touch(entity.position, proxies.radius_from_name(entity.name), pole.position, proxies.supply_radius(pole))
				then
					proxies.connect(entity, pole)
				end

				job.pole_index = job.pole_index + 1
			end
		end
	elseif phase == "remove" then
		-- Remove the old hidden poles after connecting the replacements.
		local entity = job.remove[job.i]
		if not entity then return true end
		if entity.valid then entity.destroy() end
		job.i = job.i + 1
	end

	return false
end

return jobs