-- Shared names, sizes, and settings for the floor network.

local constants = {}

constants.TILE_NAME = "electric-floor"
constants.PROXY_PREFIX = "electric-floor-proxy-"

-- Hidden poles cover squares of 1, 2, 4, 8, 16, or 32 tiles per side.
-- Each pole sits at the center of its square, so its supply radius is half the side length.
constants.SIZES = {1, 2, 4, 8, 16, 32}

constants.CHUNK_SIZE = 32
constants.MAX_RADIUS = 16 -- SIZES[#SIZES] / 2

constants.PROXY_NAMES = {}
for i = 1, #constants.SIZES do
	constants.PROXY_NAMES[i] = constants.PROXY_PREFIX .. constants.SIZES[i]
end

constants.POLE_COPPER = defines.wire_connector_id.pole_copper

constants.SETTING_INTERVAL = "electric-floor-pass-interval"
constants.SETTING_BUDGET = "electric-floor-chunks-per-pass"

-- Read each pole’s supply radius from the table collected in data-final-fixes.lua.

local pole_supply_by_name

local function pole_supply()
	if not pole_supply_by_name then
		local carrier = prototypes.mod_data["electric-floor-pole-supply"]
		pole_supply_by_name = (carrier and carrier.data and carrier.data.by_name) or {}
	end

	return pole_supply_by_name
end

--- Return how far this type of pole supplies power in each direction.
--- Return zero if the pole is missing from the supply table.
--- @param name string
--- @return number
function constants.pole_supply_radius(name)
	return pole_supply()[name] or 0
end

--- Use the largest supply radius to decide how far outside a chunk to look for electric poles.
--- Use Factorio’s value when available, with the recorded prototype data as a fallback.
--- @return number
function constants.max_pole_supply_radius()
	local from_game = prototypes.max_electric_pole_supply_area_distance
	if type(from_game) == "number" and from_game > 0 then return from_game end

	local carrier = prototypes.mod_data["electric-floor-pole-supply"]
	return (carrier and carrier.data and carrier.data.largest) or 0
end

return constants
