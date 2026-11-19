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
