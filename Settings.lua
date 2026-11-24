local addonName, ns = ...

local LEVEL = ns.LEVEL
local LEVEL_SETTING = addonName .. "_sourceLevel"

-- How far the vacuum listens; each level includes the one before (docs/data.md, "Levels").
local function GetSourceLevels()
	local levels = Settings.CreateControlTextContainer()
	levels:Add(LEVEL.SELF, "Self Found", "Only what you see yourself: trainers, vendors, quests and loot. Sharing is paused.")
	levels:Add(LEVEL.FRIENDS, "Friends", "Also what your party, raid, guild and friends see, link or share.")
	levels:Add(LEVEL.PUBLIC, "Public", "Also recipes linked in public chat.")
	return levels:GetData()
end

-- The first-run question (Heard.lua) answers through the same setting as the options page.
function ns.ChooseLevel(level)
	ns.db.levelChosen = true
	Settings.SetValue(LEVEL_SETTING, level)
end

local function Checkbox(category, key, name, tooltip, default, onChange)
	local setting = Settings.RegisterAddOnSetting(category, addonName .. "_" .. key, key,
		ns.db, Settings.VarType.Boolean, name, default)
	if onChange then
		setting:SetValueChangedCallback(onChange)
	end
	return Settings.CreateCheckbox(category, setting, tooltip), setting
end

-- Player commands; Troubleshooting.lua adds diagnostics. One table drives the chat help and the
-- Commands rows.
ns.commands = ns.commands or {}
table.insert(ns.commands, 1, { action = "", description = "Open Recipe Vacuum's options", run = function()
	Settings.OpenToCategory(ns.module.category:GetID())
end })
table.insert(ns.commands, 2, { action = "export", description = "Copy your finds as JSON to send to the maintainer", run = function()
	ns.ExportFinds()
end })

-- Called once saved variables load. Sections follow Blizzard's pages; explanations go in row tooltips.
-- Labels are capitalized as Blizzard's options are ("Auto Loot", "Enable Sound").
function ns.InitSettings()
	local toolkit = LibStub("JigBoltgripToolkit-1.0")
	local module = toolkit:RegisterModule(addonName)
	ns.module = module
	local category, layout = module.category, module.layout

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Recipe Sources"))
	local level = Settings.RegisterAddOnSetting(category, LEVEL_SETTING, "sourceLevel",
		ns.db, Settings.VarType.Number, "Recipe Sources", LEVEL.FRIENDS)
	Settings.CreateDropdown(category, level, GetSourceLevels,
		"Choose how far Recipe Vacuum listens for recipes. Everything it comes across is kept at every level.")
	level:SetValueChangedCallback(function(_, value)
		ns.SetSharing(value >= LEVEL.FRIENDS)
		ns.SourcesChanged()
	end)

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Personal Finds"))
	local record, recordSetting = Checkbox(category, "selfFound", "Record Personal Finds",
		"Remember recipe sources from the trainers, vendors, quests and loot you see, even on characters without that profession.", true)
	local announce = Checkbox(category, "announceNewFinds", "Announce New Finds",
		"Print one message in your chat window after a visit with new recipe sources.", true)
	-- Indented under Record Personal Finds; active only while it is on.
	announce:SetParentInitializer(record, function() return recordSetting:GetValue() end)
	-- Export Finds is a command, so it appears once, under Commands.

	toolkit:RegisterCommands(module, "recipevacuum", ns.commands)
	toolkit:FinishModule(module)
end
