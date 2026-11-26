local addonName, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("RecipeVacuum")

local LEVEL = ns.LEVEL

-- Player commands; Troubleshooting.lua adds diagnostics. One table drives the chat help and the Commands rows.
ns.commands = ns.commands or {}
table.insert(ns.commands, 1, { action = "", description = L["Open the options"], run = function()
	Settings.OpenToCategory(ns.module.category:GetID())
end })
table.insert(ns.commands, 2, { action = "export", description = L["Copy the recipe sources you found"],
	note = L["Opens a window of every recipe source you found, ready to copy."], run = function()
	ns.ExportFinds()
end })

-- Called once saved variables load. Sections follow Blizzard's pages; labels are capitalized as Blizzard's are.
function ns.InitSettings()
	local toolkit = LibStub("JigBoltgripToolkit-1.0")
	local module = toolkit:RegisterModule(addonName, ns.device.class)
	ns.module = module
	toolkit:BuildOptions(module, ns.db, {
		{ heading = L["Recipe Sources"], place = "sources", rows = {
			{ kind = "cards", key = "sourceLevel", label = L["Recipe Sources"], default = LEVEL.FRIENDS,
				-- The kit words the cards; Recipe Vacuum names what it tracks (the toolkit's docs/standards.md, "Options").
				values = toolkit:SourceCards({ what = L["recipes"], friends = true, public = L["recipes people link in chat"] }),
				onChange = function()
					ns.SharingSettingsChanged()
					ns.SourcesChanged()
				end },
			{ kind = "checkbox", key = "shareFinds", label = L["Share My Finds"], default = true,
				tooltip = L["Send what you find to party, guild and friends who use Recipe Vacuum."],
				note = L["Sends your trainers, vendors, quests and drops to friends who use Recipe Vacuum. Nothing else is sent."],
				onChange = ns.SharingSettingsChanged },
		} },
		{ heading = L["Personal Finds"], place = "features", rows = {
			{ kind = "checkbox", key = "selfFound", label = L["Track Personal Finds"], default = true,
				tooltip = L["Remembers the trainers, vendors, quests and loot you see, on every character."] },
			{ kind = "checkbox", key = "announceNewFinds", label = L["Announce New Finds"], default = true, under = "selfFound",
				tooltip = L["Print one message in your chat window after a visit with new recipe sources."] },
		} },
	})
	toolkit:RegisterCommands(module, "recipevacuum", ns.commands)
	toolkit:FinishModule(module)
end
