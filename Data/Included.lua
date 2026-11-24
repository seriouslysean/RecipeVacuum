local _, ns = ...

-- Reviewed finds shipped with the addon (data layer 2): the saved layer layout (Core.lua) plus its NPCs.
-- another addon ships its sources the same way (Database/Trainer.lua, Vendor.lua).
-- Bump `format` whenever the layout changes.
ns.included = {
	format = 2,
	recipes = {},
	items = {},
	npcs = {},
	objects = {},
}
