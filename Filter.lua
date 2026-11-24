local _, ns = ...

local function IsShowUnlearnedChecked()
	return ns.db.showUnlearned
end

-- Forever turns Show Unlearned off after every list rebuild, so enabling it always makes Blizzard
-- rebuild the list. Unlearned.lua then adds our recipes.
function ns.RefreshList()
	C_TradeSkillUI.SetShowUnlearned(true)
end

local function ToggleShowUnlearned()
	ns.db.showUnlearned = not ns.db.showUnlearned
	ns.RefreshList()
end

local function IsShowUnavailableChecked()
	return ns.db.showUnavailable
end

local function ToggleShowUnavailable()
	ns.db.showUnavailable = not ns.db.showUnavailable
	if ns.db.showUnlearned then
		ns.RefreshList()
	end
end

-- Sources submenu, laid out like Blizzard's Professions.InitSourcesFilter.
local sourceFilterKeys = ns.sourceFilterKeys

local IsSourceChecked = ns.IsSourceShown

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
		local label = key == "unknown" and UNKNOWN or ns.sourceTypes[key].label
		submenu:CreateCheckbox(label, IsSourceChecked, ToggleSource, key)
	end
end

Menu.ModifyMenu("MENU_PROFESSIONS_FILTER", function(_, rootDescription)
	if not ns.CanShowUnlearned() then
		return
	end
	rootDescription:CreateDivider()
	rootDescription:CreateTitle(ns.title)
	rootDescription:CreateCheckbox(PROFESSION_RECIPES_SHOW_UNLEARNED or "Show Unlearned",
		IsShowUnlearnedChecked, ToggleShowUnlearned)
	-- Blizzard's word for what a character can't learn, from its trainer filter.
	rootDescription:CreateCheckbox(UNAVAILABLE or "Unavailable", IsShowUnavailableChecked, ToggleShowUnavailable)
	AddSourcesSubmenu(rootDescription)
end)

-- Blizzard's filter reset (red X) also resets ours. Forever shows the X whenever the menu opens,
-- because its default check expects Show Unlearned on; left alone.
EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
	hooksecurefunc(Professions, "SetDefaultFilters", function()
		ns.db.showUnlearned, ns.db.showUnavailable = true, true
		wipe(ns.db.sourceFilter)
		ns.RefreshList()
	end)
end)
