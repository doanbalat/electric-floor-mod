-- You can change all three settings in an existing save under Mod settings > Map.
-- The update interval is how often the mod checks for waiting floor edits when no work is already running.
-- Once work is running, the work budget limits how many steps run each tick, and the job limit caps how many chunk or pole jobs can finish that tick.
-- Lower limits spread a big paving job across more ticks, so the floor can take longer to finish connecting.

data:extend({
 {type="int-setting",name="work-per-tick",setting_type="runtime-global",default_value=64,minimum_value=8,maximum_value=256,order="c"},
	{
		type = "int-setting",
		name = "pass-interval",
		setting_type = "runtime-global",
		default_value = 15,
		minimum_value = 5,
		maximum_value = 600,
		order = "a",
	},
	{
		type = "int-setting",
		name = "chunks-per-pass",
		setting_type = "runtime-global",
		default_value = 8,
		minimum_value = 1,
		maximum_value = 128,
		order = "b",
	},
})
