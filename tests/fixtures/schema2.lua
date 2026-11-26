-- A made-up saved file at schema 2, the oldest an upgrade starts from (tests/upgrade.lua). Every name and ID
-- is invented; only the shape matches what schema 2 saved.
RecipeVacuumDB = {
	schema = 2,
	sources = {
		["item:5000"] = {
			{ type = "vendor", itemID = 5000, npcID = 100, npcName = "Test Vendor", mapID = 1429, x = 0.5, y = 0.5,
				seen = 1795000000, faction = "Alliance", price = 500, limited = false, recipeName = "Pattern: Test" },
		},
		["item:5001"] = {
			{ type = "vendor", itemID = 5001, npcID = 101, npcName = "Other Vendor", mapID = 1453, x = 0.25, y = 0.75,
				seen = 1795000100, faction = "Alliance", price = 1200, recipeName = "Plans: Test" },
			{ type = "vendor", itemID = 5001, npcID = 102, npcName = "Shared Vendor", mapID = 1453, x = 0.3, y = 0.7,
				seen = 1795000200, faction = "Alliance", price = 1200, origin = "shared", recipeName = "Plans: Test" },
		},
		["name:apprentice test"] = {
			{ type = "trainer", npcID = 103, npcName = "Test Trainer", mapID = 1429, x = 0.4, y = 0.6, seen = 1795000300 },
		},
	},
	itemRecipe = { [5000] = 3275, [5001] = 2662 },
	pendingItems = {},
}
