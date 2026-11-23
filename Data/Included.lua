local _, ns = ...

-- Included data: owner-reviewed finds shipped with the addon, layer 2 of the data model
-- (HANDOFF.md). Same layout as a saved layer (see Core.lua), plus the NPCs it refers to.
-- another addon ships its sources the same way, as Lua tables keyed by IDs
-- (Database/Trainer.lua, Database/Vendor.lua). Empty until reviewed finds exist; bump
-- `format` whenever the layout changes.
ns.included = {
	format = 1,
	recipes = {},
	items = {},
	trainerNames = {},
	npcs = {},
}
