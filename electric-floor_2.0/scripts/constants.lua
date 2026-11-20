-- Shared constants for the runtime side of the mod.

local constants = {}

constants.TILE_NAME = "electric-floor"
constants.PROXY_PREFIX = "electric-floor-proxy-"

-- Square edge lengths (in tiles) a proxy is sized for. The proxy's supply
-- radius is half of its square, and the quadtree covering only produces these
-- sizes, so one prototype per entry is enough.
constants.SIZES = {1, 2, 4, 8, 16, 32}

constants.CHUNK_SIZE = 32
constants.MAX_RADIUS = 16 -- SIZES[#SIZES] / 2

constants.PROXY_NAMES = {}
for i = 1, #constants.SIZES do
	constants.PROXY_NAMES[i] = constants.PROXY_PREFIX .. constants.SIZES[i]
end

constants.POLE_COPPER = defines.wire_connector_id.pole_copper

constants.SETTING_INTERVAL = "electric-floor-pass-interval"
constants.SETTING_WORK = "electric-floor-work-per-tick"
constants.SETTING_JOB_LIMIT = "electric-floor-jobs-per-tick"

------------------------------------------------------------------------------
-- pole supply areas
--
-- `supply_area_distance` cannot be read from a prototype at runtime, so
-- data-final-fixes.lua collects it into a mod-data prototype.
------------------------------------------------------------------------------

local pole_supply_by_name

local function pole_supply()
	if not pole_supply_by_name then
		local carrier = prototypes.mod_data["electric-floor-pole-supply"]
		pole_supply_by_name = (carrier and carrier.data and carrier.data.by_name) or {}
	end

	return pole_supply_by_name
end

--- Half the side of a pole's supply square: the distance within which it powers
--- whatever stands next to it.
--- @param name string
--- @return number
function constants.pole_supply_radius(name)
	return pole_supply()[name] or 0
end

--- Every electric pole prototype except our proxies, so a search for real
--- poles does not also return the many proxies around them.
--- @return string[]
local real_pole_names

function constants.real_pole_names()
	if not real_pole_names then
		real_pole_names = {}
		for name in pairs(prototypes.get_entity_filtered {{filter = "type", type = "electric-pole"}}) do
			if name:sub(1, #constants.PROXY_PREFIX) ~= constants.PROXY_PREFIX then
				real_pole_names[#real_pole_names + 1] = name
			end
		end
	end

	return real_pole_names
end

--- Largest supply radius of any pole prototype. Used as the search margin when
--- looking for poles that can reach a floor square.
--- @return number
function constants.max_pole_supply_radius()
	local from_game = prototypes.max_electric_pole_supply_area_distance
	if type(from_game) == "number" and from_game > 0 then return from_game end

	local carrier = prototypes.mod_data["electric-floor-pole-supply"]
	return (carrier and carrier.data and carrier.data.largest) or 0
end

return constants
