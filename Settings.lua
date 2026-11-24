local addonName, ns = ...

-- Reuses the sharing preference, including an earlier opt-out.
local function GetSourceModes()
	local modes = Settings.CreateControlTextContainer()
	modes:Add(true, "Everything", "Show every recipe you don't know yet, with the sources you, your friends, guild and group have found.")
	modes:Add(false, "Self Found", "Show only recipes you have seen yourself at a trainer, vendor or quest, and pause sharing.")
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
table.insert(ns.commands, 2, { action = "export", description = "Copy your trainer and vendor finds as JSON to send to the maintainer", run = function()
	ns.ExportFinds()
end })

-- Called once saved variables load. Sections follow Blizzard's pages; explanations go in row tooltips.
function ns.InitSettings()
	local toolkit = LibStub("JigBoltgripToolkit-1.0")
	local module = toolkit:RegisterModule(addonName)
	ns.module = module
	local category, layout = module.category, module.layout

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Recipe sources"))
	local mode = Settings.RegisterAddOnSetting(category, addonName .. "_shareWithFriends", "shareWithFriends",
		ns.db, Settings.VarType.Boolean, "Recipe sources", true)
	Settings.CreateDropdown(category, mode, GetSourceModes,
		"Choose which discoveries appear in the profession window. Both modes keep your saved finds.")
	mode:SetValueChangedCallback(function(_, shared)
		ns.SetSharing(shared)
		ns.SourcesChanged()
	end)

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Personal finds"))
	local record, recordSetting = Checkbox(category, "selfFound", "Record personal finds",
		"Remember recipes from the trainers and vendors you visit, even on characters without that profession.", true)
	local announce = Checkbox(category, "announceNewFinds", "Announce new finds",
		"Print one message in your chat window after a visit with new recipe sources.", true)
	-- Indented under Record personal finds; active only while it is on.
	announce:SetParentInitializer(record, function() return recordSetting:GetValue() end)
	-- Export Finds is a command, so it appears once, under Commands.

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Display"))
	Checkbox(category, "fullColorIcons", "Full color source icons",
		"Show the source icons next to unlearned recipes in full color instead of dimmed.", false,
		function() ns.RefreshRows() end)

	toolkit:RegisterCommands(module, "recipevacuum", ns.commands)
	toolkit:FinishModule(module)
end
