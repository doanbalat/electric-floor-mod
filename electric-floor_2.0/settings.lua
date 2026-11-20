<<<<<<< HEAD
-- Runtime settings.
--
-- Both settings are runtime-global on purpose: they only affect how much work
-- the mod does per pass, so players can retune them to their factory size
-- without regenerating anything.

data:extend({
	{
		type = "int-setting",
		name = "pass-interval",
		setting_type = "runtime-global",
		default_value = 1,
		minimum_value = 1,
		maximum_value = 600,
		order = "a",
	},
	{
		type = "int-setting",
		name = "chunks-per-pass",
		setting_type = "runtime-global",
		default_value = 1,
		minimum_value = 1,
		maximum_value = 128,
		order = "b",
	},
})
=======
-- You can change all three settings in an existing save under Mod settings > Map.
-- The update interval is how often the mod checks for waiting floor edits when no work is already running.
-- Once work is running, the work budget limits how many steps run each tick, and the job limit caps how many chunk or pole jobs can finish that tick.
-- Lower limits spread a big paving or removal job across more ticks, so the floor can take longer to finish connecting.

data:extend({
	{
		type = "int-setting",
		name = "pass-interval",
		setting_type = "runtime-global",
		default_value = 1,
		minimum_value = 1,
		maximum_value = 600,
		order = "a",
	},
	{
		type = "int-setting",
		name = "jobs-per-tick",
		setting_type = "runtime-global",
		default_value = 1,
		minimum_value = 1,
		maximum_value = 128,
		order = "b",
	},
	{
		type = "int-setting",
		name = "work-per-tick",
		setting_type = "runtime-global",
		default_value = 64,
		minimum_value = 8,
		maximum_value = 256,
		order = "c",
	},
})
>>>>>>> 2d8be52 (Fixes focus on de-sync for multiplayer, also remove dead codes, and some small fixes)
