local addonName, ns = ...

local LEVEL = ns.LEVEL
local LEVEL_SETTING = addonName .. "_sourceLevel"

local function Checkbox(category, key, name, tooltip, default, onChange)
	local setting = Settings.RegisterAddOnSetting(category, addonName .. "_" .. key, key,
		ns.db, Settings.VarType.Boolean, name, default)
	if onChange then
		setting:SetValueChangedCallback(onChange)
	end
	return Settings.CreateCheckbox(category, setting, tooltip), setting
end

-- Player commands; Troubleshooting.lua adds diagnostics. One table drives the chat help and the Commands rows.
ns.commands = ns.commands or {}
table.insert(ns.commands, 1, { action = "", description = "Open Recipe Vacuum's options", run = function()
	Settings.OpenToCategory(ns.module.category:GetID())
end })
table.insert(ns.commands, 2, { action = "export", description = "Copy your finds as JSON to send to the maintainer", run = function()
	ns.ExportFinds()
end })

-- Called once saved variables load. Sections follow Blizzard's pages; labels are capitalized as Blizzard's are.
function ns.InitSettings()
	local toolkit = LibStub("JigBoltgripToolkit-1.0")
	local module = toolkit:RegisterModule(addonName, ns.device.class)
	ns.module = module
	local category, layout = module.category, module.layout

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Recipe Sources"))
	local level = Settings.RegisterAddOnSetting(category, LEVEL_SETTING, "sourceLevel",
		ns.db, Settings.VarType.Number, "Recipe Sources", LEVEL.FRIENDS)
	local showChoice = ns.AddLevelCards(layout, level)
	level:SetValueChangedCallback(function(_, value)
		showChoice(value)
		ns.SetSharing(value >= LEVEL.FRIENDS)
		ns.SourcesChanged()
	end)

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Personal Finds"))
	local record, recordSetting = Checkbox(category, "selfFound", "Record Personal Finds",
		"Remember recipe sources from the trainers, vendors, quests and loot you see, even on characters without that profession.", true)
	local announce = Checkbox(category, "announceNewFinds", "Announce New Finds",
		"Print one message in your chat window after a visit with new recipe sources.", true)
	-- Indented under Record Personal Finds, active only while it is on.
	announce:SetParentInitializer(record, function() return recordSetting:GetValue() end)

	toolkit:RegisterCommands(module, "recipevacuum", ns.commands)
	toolkit:FinishModule(module)
end
