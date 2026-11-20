-- The grid texture comes from Dectorio’s concrete grid by PantherX under GPLv3.
-- The tile starts as a copy of base-game concrete, with its own name, mining result, and grid texture.

local base_concrete = data.raw["tile"]["concrete"]

local electric_floor_tile = table.deepcopy(base_concrete)

electric_floor_tile.name = "electric-floor"
electric_floor_tile.order = "a[artificial]-b[tier-2]-b[electric-floor]"
electric_floor_tile.minable = {mining_time = 0.1, result = "electric-floor"}

-- Merge with concrete so no border is drawn between them.
electric_floor_tile.transition_merges_with_tile = "concrete"

-- Draw the Dectorio grid texture with the same count and scale as base-game concrete.
electric_floor_tile.variants.material_background = {
	picture = "__electric-floor__/graphics/terrain/electric-floor.png",
	count = 8,
	scale = 0.5
}

data:extend({electric_floor_tile})
