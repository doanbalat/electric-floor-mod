-- Electric Floor - runtime entry point.
--
-- A tile can never be part of the electric network, so the floor is made
-- conductive by laying a sparse network of hidden electric poles over it:
--   * one pole per maximally-sized square of floor (a full 32x32 chunk of floor
--     needs a single pole),
--   * poles wired to the touching poles around them, which makes the network
--     follow the shape of the floor,
--   * any real pole placed on the floor is wired into it.
--
-- The poles are wired with the reach check disabled, because the floor itself
-- is the conductor.

local floors = require("scripts.floors")

floors.register()

remote.add_interface("electric-floor", {
	--- Checks the surface for floor chunks and queues the repairs, which are
	--- then done a little at a time. Useful after adding the mod to an existing
	--- save, or to force a repair if something else removed proxies.
	rescan = function()
		floors.rescan()
	end,

	--- Same, but waits for the work to finish instead of spreading it over
	--- ticks. Can take a while on a large factory.
	rescan_now = function()
		floors.rescan()
		floors.drain_now()
	end,
})
