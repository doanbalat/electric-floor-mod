-- Record how far every electric pole reaches so the floor can find nearby poles once a save is running.
-- This runs late in the data stage to include electric poles added by other mods.

local by_name = {}
local largest = 0

for name, prototype in pairs(data.raw["electric-pole"] or {}) do
	local distance = prototype.supply_area_distance or 0

	by_name[name] = distance

	if distance > largest then largest = distance end
end

data:extend({
	{
		type = "mod-data",
		name = "electric-floor-pole-supply",
		data = {
			by_name = by_name,
			largest = largest,
		},
	},
})
