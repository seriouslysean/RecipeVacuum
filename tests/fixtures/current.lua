-- A made-up saved file at the current schema (tests/simulate_spec.lua). Every name and ID is invented; it holds one
-- source of each recorded kind, a shared find, a rank and the dev fields a working build leaves behind.
RecipeVacuumDB = {
	schema = 11,
	selfFound = true, shareFinds = true, announceNewFinds = true, sourceLevel = 2,
	watch = true,
	met = { recipes = { [3276] = 2 }, items = { [5002] = 3 } },
	found = {
		recipes = {
			[3273] = { { kind = "trainer", npc = 200, skill = 1, cost = 100, faction = "Alliance", seen = 1795400000, build = 71139, rev = 1 } },
		},
		items = {
			[5000] = { { kind = "vendor", npc = 201, price = 500, limited = false, faction = "Alliance", seen = 1795400100, build = 71139, rev = 2 } },
			[5003] = { { kind = "quest", quest = 1199, npc = 202, finisher = 202, choice = true, seen = 1795400200, build = 71139, rev = 3 } },
			[5004] = { { kind = "drop", npc = 203, map = 1429, area = 41, x = 0.5, y = 0.5, count = 2, seen = 1795400300, build = 71139, rev = 4 } },
		},
	},
	shared = {
		recipes = {},
		items = { [5005] = { { kind = "vendor", npc = 204, price = 900, seen = 1795400400, build = 71139 } } },
	},
	npcs = {
		[200] = { name = "Test Trainer", faction = "Alliance", positions = { [1429] = { x = 0.4, y = 0.6, seen = 1795400000 } } },
		[201] = { name = "Test Vendor", faction = "Alliance", positions = { [1429] = { x = 0.5, y = 0.5, seen = 1795400100 } } },
		[202] = { name = "Test Giver", faction = "Alliance", positions = { [1429] = { x = 0.3, y = 0.3, seen = 1795400200 } } },
		[203] = { name = "Test Creature", positions = { [1429] = { x = 0.5, y = 0.5, seen = 1795400300 } } },
		[204] = { name = "Friend's Vendor", positions = { [1453] = { x = 0.6, y = 0.4, seen = 1795400400 } } },
		[205] = { name = "Rank Trainer", positions = { [1429] = { x = 0.45, y = 0.55, seen = 1795400500 } } },
	},
	objects = {},
	ranks = { [185] = { [0] = { npcs = { [205] = 1795400500 }, items = {}, quests = {}, spell = 2550 } } },
	itemRecipe = {}, recipeItems = {}, pendingItems = {},
	exchange = { id = "1795400000-12345", revision = 4, received = {} },
	devLog = { "2026-11-25 12:00:00 session: test" }, devLogRun = 1,
}
