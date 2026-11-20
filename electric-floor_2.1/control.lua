-- Electric concrete uses hidden electric poles to carry power across the floor.
-- One hidden pole covers each square of electric concrete, so a fully paved 32 × 32 chunk only needs one pole.
-- Neighboring squares join the same network when they touch, even at a corner.
-- A regular electric pole can join the floor network from the side if its supply area reaches the concrete.

local floors = require("scripts.floors")

floors.register()

remote.add_interface("electric-floor", {
	--- Check generated chunks and queue floor repairs over several ticks.
	--- Use this after adding the mod to an existing save or when you need to repair the floor network.
	rescan = function()
		floors.rescan()
	end,

	--- Check and repair the floor network before returning.
	--- This can pause a large factory while the work finishes.
	rescan_now = function()
		floors.rescan()
		floors.drain_now()
	end,
})
