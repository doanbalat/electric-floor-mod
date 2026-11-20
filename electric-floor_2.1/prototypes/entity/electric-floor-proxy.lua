-- Electric concrete gets its power coverage from hidden electric poles.
-- The poles stay off the map and out of blueprints and deconstruction orders, and the player cannot select them.
-- They have no collision layers, so a machine can stand on the same tile.
-- Their normal wire reach is zero, so the mod makes the copper connections itself when squares of coverage meet.
-- There is one pole type per square size, so a full 32 × 32 chunk of concrete needs just one hidden pole.

local sizes = {1, 2, 4, 8, 16, 32}

-- The pole needs wire attachment points, even though the game never draws its wires.
local connection_point = {
	wire = {
		copper = {0, 0},
		green = {0, 0},
		red = {0, 0},
	},
	shadow = {
		copper = {0, 0},
		green = {0, 0},
		red = {0, 0},
	},
}

local prototype = {
	type = "electric-pole",
	hidden = true,
	selectable_in_game = false,
	flags = {
		"placeable-off-grid",
		"not-on-map",
		"not-blueprintable",
		"not-deconstructable",
	},
	collision_mask = {layers = {}},
	collision_box = {{-0.4, -0.4}, {0.4, 0.4}},
	maximum_wire_distance = 0,
	draw_copper_wires = false,
	draw_circuit_wires = false,
	create_ghost_on_death = false,
	rewire_neighbours_when_destroying = false,
	protected_from_tile_building = false,
	remove_decoratives = "false",
	connection_points = {connection_point, connection_point, connection_point, connection_point},
}

local proxies = {}

for i = 1, #sizes do
	local size = sizes[i]
	local p = table.deepcopy(prototype)

	p.name = "electric-floor-proxy-" .. size
	p.supply_area_distance = size / 2

	proxies[#proxies + 1] = p
end

data:extend(proxies)
