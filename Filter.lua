local addonName, ns = ...
local moduleTitle = C_AddOns.GetAddOnMetadata(addonName, "Title")

local function IsShowUnlearnedChecked()
	return ns.db.showUnlearned
end

-- Forever turns the client's Show Unlearned off after every list rebuild, so turning it on
-- always changes it, which makes Blizzard rebuild the list. Unlearned.lua then adds the
-- unlearned recipes to match the player's choices.
function ns.RefreshList()
	C_TradeSkillUI.SetShowUnlearned(true)
end

local function ToggleShowUnlearned()
	ns.db.showUnlearned = not ns.db.showUnlearned
	ns.RefreshList()
end

-- The Sources submenu, laid out like Blizzard's own (Professions.InitSourcesFilter). It
-- filters the unlearned recipes, by the sources Recipe Vacuum knows for them.
local sourceFilterKeys = { "trainer", "vendor", "quest", "drop", "unknown", "unobtainable" }

-- Unobtainable is off unless checked; every other key is on unless unchecked.
local function IsSourceChecked(key)
	if key == "unobtainable" then
		return ns.db.sourceFilter[key] == true
	end
	return ns.db.sourceFilter[key] ~= false
end

local function ToggleSource(key)
	ns.db.sourceFilter[key] = not IsSourceChecked(key)
	if ns.db.showUnlearned then
		ns.RefreshList()
	end
end

local function SetAllSources(checked)
	for _, key in ipairs(sourceFilterKeys) do
		ns.db.sourceFilter[key] = checked
	end
	if ns.db.showUnlearned then
		ns.RefreshList()
	end
	return MenuResponse.Refresh
end

local function AddSourcesSubmenu(rootDescription)
	local submenu = rootDescription:CreateButton(SOURCES or "Sources")
	submenu:CreateButton(CHECK_ALL or "Check All", SetAllSources, true)
	submenu:CreateButton(UNCHECK_ALL or "Uncheck All", SetAllSources, false)
	for _, key in ipairs(sourceFilterKeys) do
		local label = (key == "unknown" and UNKNOWN) or (key == "unobtainable" and ns.UNOBTAINABLE)
			or ns.sourceTypes[key].label
		submenu:CreateCheckbox(label, IsSourceChecked, ToggleSource, key)
	end
end

Menu.ModifyMenu("MENU_PROFESSIONS_FILTER", function(_, rootDescription)
	if not ns.CanShowUnlearned() then
		return
	end
	rootDescription:CreateDivider()
	rootDescription:CreateTitle(moduleTitle)
	rootDescription:CreateCheckbox(PROFESSION_RECIPES_SHOW_UNLEARNED or "Show Unlearned",
		IsShowUnlearnedChecked, ToggleShowUnlearned)
	AddSourcesSubmenu(rootDescription)
end)
