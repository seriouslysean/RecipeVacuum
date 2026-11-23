local addonName, ns = ...

-- The mode uses the existing sharing preference, including an earlier opt-out.
local function GetSourceModes()
	local modes = Settings.CreateControlTextContainer()
	modes:Add(true, "Everything", "Show every recipe you don't know yet, with the sources you, your friends, guild and group have found.")
	modes:Add(false, "Self Found", "Show only recipes you have seen yourself at a trainer, vendor or quest, and pause sharing.")
	return modes:GetData()
end

local options = {
	{
		key = "selfFound",
		name = "Record personal finds",
		tooltip = "Remember recipes from the trainers and vendors you visit, even on characters without that profession.",
		default = true,
	},
	{
		key = "announceNewFinds",
		name = "Announce new finds",
		tooltip = "Print one message in your chat window after a visit with new recipe sources.",
		default = true,
	},
}

-- Called once the saved variables are loaded.
function ns.InitSettings()
	local toolkit = LibStub("JigBoltgripToolkit-1.0")
	local category, layout = toolkit:RegisterModule(
		C_AddOns.GetAddOnMetadata(addonName, "Title"),
		C_AddOns.GetAddOnMetadata(addonName, "Notes"))

	local mode = Settings.RegisterAddOnSetting(category, addonName .. "_shareWithFriends", "shareWithFriends",
		ns.db, Settings.VarType.Boolean, "Recipe sources", true)
	Settings.CreateDropdown(category, mode, GetSourceModes,
		"Choose which discoveries appear in the profession window. Both modes keep your saved finds.")
	mode:SetValueChangedCallback(function(_, shared)
		ns.SetSharing(shared)
		ns.SourcesChanged()
	end)
	for _, option in ipairs(options) do
		local setting = Settings.RegisterAddOnSetting(category, addonName .. "_" .. option.key, option.key,
			ns.db, Settings.VarType.Boolean, option.name, option.default)
		Settings.CreateCheckbox(category, setting, option.tooltip)
	end
	layout:AddInitializer(CreateSettingsButtonInitializer("Personal finds", "Export Finds", ns.ExportFinds,
		"Copy your trainer and vendor observations as JSON to send to the toolkit maintainer.", true))
end
