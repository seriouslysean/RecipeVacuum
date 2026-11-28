local addonName, ns = ...
local L = ns.L

local LEVEL = ns.LEVEL

-- Player commands; Troubleshooting.lua adds diagnostics. One table drives the chat help and the Commands rows.
ns.commands = ns.commands or {}
table.insert(ns.commands, 1, { action = "export", label = L["Export Recipe Sources"], button = L["Export"],
	description = L["Copy the recipe sources you found"],
	note = L["Opens a window of every recipe source you found, ready to copy."], run = function()
	ns.ExportFinds()
end })

-- Called once saved variables load. Sections follow Blizzard's pages; labels are capitalized as Blizzard's are.
function ns.InitSettings()
	local toolkit = ns.toolkit
	local module = toolkit:RegisterModule(addonName)
	toolkit:BuildOptions(module, ns.db, {
		{ heading = L["Recipe Sources"], place = "sources", rows = {
			{ kind = "choice", key = "sourceLevel", label = L["Learn Recipes From"], default = LEVEL.FRIENDS,
				-- The kit words the options; Recipe Vacuum names what it tracks (the toolkit's docs/standards.md, "Options").
				values = toolkit:SourceChoices({ self = L["Tracks only recipes you see for yourself."], friends = true,
					public = L["Also tracks recipes people link in chat."] }),
				onChange = function()
					ns.share:Update()
					ns.SourcesChanged()
				end },
			{ kind = "checkbox", key = "shareFinds", label = L["Share My Finds"], default = true,
				tooltip = L["Sends what you find to party, guild and friends who use Recipe Vacuum."],
				note = L["Others can tell your characters are one player, and see where you found drops and fish."],
				onChange = function() ns.share:Update() end },
		} },
		{ heading = L["Personal Finds"], place = "features", rows = {
			{ kind = "checkbox", key = "selfFound", label = L["Track Personal Finds"], default = true,
				tooltip = L["Remembers the trainers, vendors, quests and loot you see, on every character."] },
			{ kind = "checkbox", key = "announceNewFinds", label = L["Show Chat Alerts"], default = true, under = "selfFound",
				tooltip = L["Prints a message in chat after visits and windows with new recipes."] },
		} },
	})
	toolkit:RegisterCommands(module, ns.commands)
	toolkit:FinishModule(module)
end
