-- Helpers for identifying hidden poles and connecting them to the floor network.

local constants = require("scripts.constants")

local proxies = {}

local PREFIX_LENGTH = #constants.PROXY_PREFIX

--- Check whether this name belongs to one of the floor’s hidden poles.
--- @param name string?
--- @return boolean
function proxies.is_proxy(name)
	return name ~= nil and name:sub(1, PREFIX_LENGTH) == constants.PROXY_PREFIX
end

--- Read the hidden pole’s square size from its name and divide by two to get its supply radius.
--- @param name string
--- @return number
function proxies.radius_from_name(name)
	return tonumber(name:sub(PREFIX_LENGTH + 1)) / 2
end

--- Identify a hidden pole by its prototype name and position so a rebuild can keep it if it still fits.
--- The pole can sit on a whole or half tile coordinate, so doubling the coordinates gives whole numbers.
--- @return string
function proxies.position_key(name, x, y)
	return name .. "|" .. math.floor(x * 2 + 0.5) .. "|" .. math.floor(y * 2 + 0.5)
end

--- @param entity LuaEntity
--- @return string
function proxies.entity_key(entity)
	return proxies.position_key(entity.name, entity.position.x, entity.position.y)
end

--- Check whether two squares of power coverage overlap or meet along an edge or at a corner.
--- The same check works for the supply area of a regular electric pole and the square covered by a hidden pole.
--- @return boolean
function proxies.touch(a_position, a_radius, b_position, b_radius)
	local reach = a_radius + b_radius + 0.001
	return math.abs(a_position.x - b_position.x) <= reach and math.abs(a_position.y - b_position.y) <= reach
end

--- Find or create a copper wire connector on each pole and keep an existing connection if they already share one.
--- For a new connection, skip the normal wire reach check because the caller already checked that the power coverage meets.
--- @param a LuaEntity
--- @param b LuaEntity
--- @return boolean
function proxies.connect(a, b)
	local connector_a = a.get_wire_connector(constants.POLE_COPPER, true)
	local connector_b = b.get_wire_connector(constants.POLE_COPPER, true)

	if not connector_a or not connector_b then return false end
	if connector_a.is_connected_to(connector_b) then return true end

	return connector_a.connect_to(connector_b, false)
end

--- Check for any electric concrete in the pole’s supply area.
--- If the supply radius is unknown or zero, check out to the largest hidden pole radius instead.
--- @param pole LuaEntity
--- @return boolean
function proxies.can_reach_floor(pole)
	local reach = proxies.supply_radius(pole)
	if reach <= 0 then reach = constants.MAX_RADIUS end

	local position = pole.position

	return pole.surface.count_tiles_filtered {
		name = constants.TILE_NAME,
		area = {
			{position.x - reach, position.y - reach},
			{position.x + reach, position.y + reach},
		},
	} > 0
end

--- Look up the supply radius for this regular electric pole.
--- @param pole LuaEntity
--- @return number
function proxies.supply_radius(pole)
	return constants.pole_supply_radius(pole.name)
end

--- Connect a regular electric pole to all nearby hidden poles whose supply areas meet its own.
--- A pole can stand beside the concrete and still join the network when its supply area reaches the floor.
--- @param surface LuaSurface
--- @param pole LuaEntity
--- @return number amount of proxies connected
function proxies.connect_pole(surface, pole)
	local supply = proxies.supply_radius(pole)
	local position = pole.position
	local search = supply + constants.MAX_RADIUS + 1

	local found = surface.find_entities_filtered {
		name = constants.PROXY_NAMES,
		area = {
			{position.x - search, position.y - search},
			{position.x + search, position.y + search},
		},
	}

	local connected = 0

	for i = 1, #found do
		local proxy = found[i]

		if
			proxy.valid
			and proxies.touch(position, supply, proxy.position, proxies.radius_from_name(proxy.name))
			and proxies.connect(pole, proxy)
		then
			connected = connected + 1
		end
	end

	return connected
end

return proxies
