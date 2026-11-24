local addonName, ns = ...

-- Reuses the sharing preference, including an earlier opt-out.
local function GetSourceModes()
	local modes = Settings.CreateControlTextContainer()
	modes:Add(true, "Everything", "Show every recipe you don't know yet, with the sources you, your friends, guild and group have found.")
	modes:Add(false, "Self Found", "Show only recipes whose source you have seen yourself, and pause sharing.")
	return modes:GetData()
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
	local mode = Settings.RegisterAddOnSetting(category, addonName .. "_shareWithFriends", "shareWithFriends",
		ns.db, Settings.VarType.Boolean, "Recipe Sources", true)
	Settings.CreateDropdown(category, mode, GetSourceModes,
		"Choose which discoveries appear in the profession window. Both modes keep your saved finds.")
	mode:SetValueChangedCallback(function(_, shared)
		ns.SetSharing(shared)
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
