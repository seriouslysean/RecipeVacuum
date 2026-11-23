local addonName, ns = ...

-- Option defaults live in Settings.lua; Blizzard's Settings API fills them in.
local defaults = {
	showUnlearned = true, -- Blizzard's standard default; Forever turns it off.
	sourceFilter = {},     -- [sourceType or "unknown"] = false when unchecked in the Sources filter
	sources = {},          -- see Sources.lua for the keys
	itemRecipe = {},       -- [recipe itemID] = recipeID, linked when the profession is opened
	recipeItems = {},      -- [recipeID] = { recipe itemIDs }
	pendingItems = {},     -- [recipe itemID] = { name, spellID } until linked to a recipe
	schema = 2,
}

-- Older saves used a lowercased recipe name as the bucket for both vendors and trainers.
local function MigrateNameKeys(db)
	local sources, pending = {}, {}
	for name, entries in pairs(db.sources or {}) do
		for _, entry in ipairs(entries) do
			local key
			if entry.type == "vendor" and entry.itemID then
				key = ns.ItemKey(entry.itemID)
				entry.recipeName = entry.recipeName or name
				pending[entry.itemID] = { name = name:lower(), spellID = entry.spellID }
			else
				key = ns.NameKey(name)
			end
			sources[key] = sources[key] or {}
			table.insert(sources[key], entry)
		end
	end
	db.sources, db.pendingItems, db.schema = sources, pending, 2
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	RecipeVacuumDB = RecipeVacuumDB or {}
	if RecipeVacuumDB.schema == 1 or (RecipeVacuumDB.schema == nil and RecipeVacuumDB.sources) then
		MigrateNameKeys(RecipeVacuumDB)
	end
	for key, value in pairs(defaults) do
		if RecipeVacuumDB[key] == nil then
			RecipeVacuumDB[key] = value
		end
	end
	ns.db = RecipeVacuumDB
	ns.InitFinds()
	ns.InitSettings()
end)
