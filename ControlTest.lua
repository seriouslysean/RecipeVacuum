-- Working-build Settings pages for the gamepad reachability test. Stripped from releases (docs/development.md, "Control Test").
local addonName, ns = ...

--@debug@

-- Counts and stops are named up here. The page table below is the only description of the rows.
local PLAIN_ROWS = 3 -- the matrix's short plain page
local GROUP_COUNT = 3
local GROUP_ROWS = 6 -- 18 checkboxes, the matrix's long plain page
local TYPE_ROWS = 4 -- enough that "only the first row" is visible
local EMOTE_ROWS = 8
local SLIDER_MIN = 1
local SLIDER_MAX = 5
local SLIDER_STEP = 1
local SLIDER_DEFAULT = 3
local LABEL_PARENTS = 3 -- how far up from the focused control to read its row label
local CATEGORY_NAME = "Control Test"
local SETTING_PREFIX = "RVCT_"
local EMOTE_TOKEN = "BOW" -- C_ChatInfo.PerformEmote token; the deprecated DoEmote calls the same
local STOPS = { "Off", "Low", "Medium", "High", "Max" }

-- Session values only. Each run reloads, so nothing here is kept in the saved file.
local values = {}
local pagesByName = {}
local previousPage = "none"

-- One page per shape, numbered in the order the matrix walks them. Docs hold the run protocol.
-- Skipped, and why: docs/development.md, "Control Test".
local PAGES = {
	{ name = "1 Plain Checkboxes", rows = {
		{ kind = "checkbox", count = PLAIN_ROWS, key = "plain", label = "Plain Checkbox", tooltip = "A plain checkbox." },
	} },
	{ name = "2 Grouped Checkboxes", rows = {
		{ kind = "groups", groups = GROUP_COUNT, count = GROUP_ROWS },
	} },
	{ name = "3 Shown When On", rows = {
		{ kind = "checkbox", key = "shownsource", label = "Shown Source", tooltip = "Shows the next rows while this is on.", default = true },
		{ kind = "shown", count = TYPE_ROWS, key = "shown", label = "Shown Checkbox", when = "shownsource", tooltip = "Shown only while Shown Source is on." },
	} },
	{ name = "4 Search Tags", rows = {
		{ kind = "search", count = TYPE_ROWS, key = "tagged", label = "Tagged Checkbox", tooltip = "Search settings for this row's tag." },
	} },
	{ name = "5 Indented Checkboxes", rows = {
		-- On by default, so the indented rows stay enabled while reachability is measured.
		{ kind = "checkbox", key = "indentparent", label = "Parent Checkbox", tooltip = "Turns the rows under it on and off.", default = true },
		{ kind = "child", count = TYPE_ROWS, key = "indent", label = "Indented Checkbox", parent = "indentparent", tooltip = "Indented under the parent checkbox." },
	} },
	{ name = "6 Named Stops", rows = {
		{ kind = "slider", count = TYPE_ROWS, key = "stops", label = "Named Stops", tooltip = "A slider with the stops Off through Max." },
	} },
	{ name = "7 Button Rows", rows = {
		{ kind = "button", count = TYPE_ROWS, key = "button", label = "Button", button = "Press", tooltip = "Logs the press." },
	} },
	{ name = "8 Checkbox And Slider", rows = {
		{ kind = "checkboxslider", count = TYPE_ROWS, key = "combo", label = "Checkbox Slider", slider = "Level",
			tooltip = "A checkbox and a slider on one row.", sliderTooltip = "The level beside the checkbox." },
	} },
	{ name = "9 Registered Rows", rows = {
		{ kind = "register", count = TYPE_ROWS, key = "registered", label = "Registered Checkbox", tooltip = "Added by Register Initializer." },
	} },
	{ name = "10 Open From Code", rows = {
		-- Names are pages in this table, plus the parent category. Looked up when the button is pressed.
		{ kind = "open", targets = { "1 Plain Checkboxes", "2 Grouped Checkboxes", "11 Checkbox And Button", CATEGORY_NAME } },
	} },
	{ name = "11 Checkbox And Button", rows = {
		{ kind = "header", label = "Emotes" },
		{ kind = "checkboxbutton", count = EMOTE_ROWS, key = "bow", label = "Bow", button = "Bow", tooltip = "Bows when you press the button." },
	} },
	-- A deliberate Lua error, then the gamepad Interact action: whether Blizzard's error window breaks Interact for the session.
	{ name = "13 Lua Error", rows = {
		{ kind = "luaerror", label = "Raise Lua Error", button = "Raise", tooltip = "Raises a Lua error. Then close the error window and press Interact on a target." },
	} },
	-- Last on purpose. Opening the menu traps the cursor until reload.
	{ name = "12 Dropdown Last", rows = {
		{ kind = "dropdown", count = TYPE_ROWS, key = "dropdown", label = "Dropdown", tooltip = "Opening this menu breaks navigation until you reload." },
	} },
}

local function CategoryName(category)
	if not (category and category.GetName) then return "unknown" end
	local ok, name = pcall(category.GetName, category)
	if ok and type(name) == "string" and name ~= "" and not issecretvalue(name) then return name end
	return "unknown"
end

local function CurrentPage()
	if SettingsPanel and SettingsPanel.GetCurrentCategory then
		local ok, category = pcall(SettingsPanel.GetCurrentCategory, SettingsPanel)
		if ok then
			local name = CategoryName(category)
			if name ~= "unknown" then return name end
		end
	end
	return previousPage
end

local function RegionText(region)
	if not (region and region.GetText) then return end
	local ok, text = pcall(region.GetText, region)
	if ok and type(text) == "string" and text ~= "" and not issecretvalue(text) then return text end
end

-- The focused control is often the inner checkbox. The row label sits on a parent.
local function ButtonLabel(button)
	if not button then return "none" end
	local text = RegionText(button)
	if text then return text end
	local current = button
	for _ = 1, LABEL_PARENTS do
		if not (current and current.GetParent) then break end
		local ok, parent = pcall(current.GetParent, current)
		if not ok then break end
		current = parent
		text = RegionText(current and current.Text) or RegionText(current and current.Title) or RegionText(current)
		if text then return text end
	end
	local name = button.GetName and button:GetName()
	if type(name) == "string" and name ~= "" then return name end
	return "unnamed"
end

local function VisibleRows()
	if not (SettingsPanel and SettingsPanel.GetSettingsList) then return 0 end
	local ok, list = pcall(SettingsPanel.GetSettingsList, SettingsPanel)
	local box = ok and list and list.ScrollBox
	if not (box and box.GetFrames) then return 0 end
	local framesOk, frames = pcall(box.GetFrames, box)
	if not framesOk or type(frames) ~= "table" then return 0 end
	local count = 0
	for _, frame in ipairs(frames) do
		if frame and frame.IsShown and frame:IsShown() then count = count + 1 end
	end
	return count
end

-- Read-only. The report's dump is active group, focusedKey, the current button, and the container snapshot against visible rows.
local function ReadSnapshot()
	local nav = SmartNavigation
	local info = nav and nav.activeInfo
	if type(info) ~= "table" then
		return ("group none focusedKey nil inGroup no page %s button none inSnapshot no snapshot 0 visible %d"):format(
			CurrentPage(), VisibleRows())
	end
	local groups = info.buttonGroups
	local active = "none"
	local buttons
	if type(groups) == "table" then
		if type(groups.focusedGroup) == "table" then
			active = "focused"
		elseif type(groups.mainGroup) == "table" then
			active = "main"
		end
		-- The settings rows live on the Container sub-group, even when that group is not the active one.
		local sub = groups.subGroups
		local container = type(sub) == "table" and sub.Container
		local scroll = container and type(container.scrollFrames) == "table" and container.scrollFrames[1]
		buttons = scroll and scroll.buttons
	end
	local snapshot = type(buttons) == "table" and #buttons or 0
	local button
	if nav.GetCurrentButton then
		local buttonOk, current = pcall(nav.GetCurrentButton, nav)
		if buttonOk then button = current end
	end
	local inSnapshot = (button and type(buttons) == "table" and tContains(buttons, button)) and "yes" or "no"
	local inGroup = "no"
	if type(nav.IsInFocusGroup) == "function" then
		local groupOk, value = pcall(nav.IsInFocusGroup, nav)
		if groupOk and value then inGroup = "yes" end
	end
	local key = info.focusedKey
	return ("group %s focusedKey %s inGroup %s page %s button %s inSnapshot %s snapshot %d visible %d"):format(
		active, key == nil and "nil" or tostring(key), inGroup, CurrentPage(), ButtonLabel(button), inSnapshot, snapshot, VisibleRows())
end

local function Snapshot()
	local ok, line = pcall(ReadSnapshot)
	if not ok then return "read failed " .. tostring(line) end
	return line
end

-- T2. Out of combat only. Not called on category display: that would change the thing being measured.
local function RefreshNavigation()
	local before = Snapshot()
	ns.Trace("CT navrefresh before %s", before)
	if InCombatLockdown() then
		ns.Trace("CT navrefresh skipped combat")
		return "Navigation refresh skipped during combat."
	end
	if not (SmartNavigation and type(SmartNavigation.RefreshButtonGroups) == "function") then
		ns.Trace("CT navrefresh missing")
		return "Navigation refresh is not available."
	end
	local ok, problem = pcall(SmartNavigation.RefreshButtonGroups, SmartNavigation)
	if not ok then ns.Trace("CT navrefresh error %s", tostring(problem)) end
	ns.Trace("CT navrefresh after %s", Snapshot())
	return "Navigation refresh logged."
end

local function DumpNavigation()
	ns.Trace("CT navdump %s", Snapshot())
	return "Navigation state logged."
end

-- Same command table as Troubleshooting.lua, inserted at load so they are registered with the rest.
ns.commands = ns.commands or {}
table.insert(ns.commands, { action = "navdump", description = "Log the gamepad navigation state", troubleshooting = true, quiet = true,
	run = function() ns.Log(DumpNavigation()) end })
table.insert(ns.commands, { action = "navrefresh", description = "Refresh gamepad navigation and log it", troubleshooting = true, quiet = true,
	run = function() ns.Log(RefreshNavigation()) end })

local function OnChanged(pageName, label)
	return function(_, value)
		ns.Trace("CT change %s %s %s", pageName, label, tostring(value))
	end
end

local function Indexed(spec, index)
	local many = (spec.count or 1) > 1
	local key = many and (spec.key .. index) or spec.key
	local label = many and (spec.label .. " " .. index) or spec.label
	return key, label
end

local function AddSetting(category, key, label, varType, default)
	local setting = Settings.RegisterAddOnSetting(category, SETTING_PREFIX .. key, key, values, varType, label, default)
	return setting
end

local function AddCheckbox(ctx, key, label, tooltip, default)
	local setting = AddSetting(ctx.category, key, label, Settings.VarType.Boolean, default and true or false)
	setting:SetValueChangedCallback(OnChanged(ctx.page.name, label))
	local initializer = Settings.CreateCheckbox(ctx.category, setting, tooltip)
	ctx.made[key] = initializer
	return initializer
end

-- The stand-ins omit a few initializer methods. In game they are on the row.
-- The device may not exist yet: this file's load callback can run before the core's.
local function Try(object, method, ...)
	local func = object and object[method]
	if type(func) == "function" then return func(object, ...) end
	if ns.device then ns.Trace("CT missing %s", method) end
end

local function NamedStops()
	local options = Settings.CreateSliderOptions(SLIDER_MIN, SLIDER_MAX, SLIDER_STEP)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return STOPS[value] or tostring(value)
	end)
	return options
end

local function DropdownOptions()
	local container = Settings.CreateControlTextContainer()
	for index, label in ipairs(STOPS) do
		container:Add(index, label)
	end
	return container:GetData()
end

local function AddHeader(ctx, label)
	ctx.layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(label))
end

local function AddButton(ctx, label, buttonText, tooltip, onClick)
	local function Press(...)
		ns.Trace("CT press %s %s", ctx.page.name, label)
		if onClick then onClick(...) end
	end
	-- false: do not add search tags. Search tags are their own page.
	ctx.layout:AddInitializer(CreateSettingsButtonInitializer(label, buttonText, Press, tooltip, false))
end

local ROW = {}

function ROW.luaerror(ctx, spec)
	AddButton(ctx, spec.label, spec.button, spec.tooltip, function() error("Control Test: deliberate error") end)
end

function ROW.header(ctx, spec)
	AddHeader(ctx, spec.label)
end

function ROW.checkbox(ctx, spec)
	for index = 1, spec.count or 1 do
		local key, label = Indexed(spec, index)
		AddCheckbox(ctx, key, label, spec.tooltip, spec.default)
	end
end

function ROW.groups(ctx, spec)
	for group = 1, spec.groups do
		AddHeader(ctx, "Group " .. group)
		for index = 1, spec.count do
			local key = ("group%dchoice%d"):format(group, index)
			local label = ("Group %d Choice %d"):format(group, index)
			AddCheckbox(ctx, key, label, "A plain checkbox.", false)
		end
	end
end

function ROW.child(ctx, spec)
	for index = 1, spec.count or 1 do
		local key, label = Indexed(spec, index)
		local initializer = AddCheckbox(ctx, key, label, spec.tooltip, false)
		local parent = ctx.made[spec.parent]
		-- The predicate is the addon function this page exists to measure.
		Try(initializer, "SetParentInitializer", parent, function() return values[spec.parent] and true or false end)
	end
end

function ROW.shown(ctx, spec)
	for index = 1, spec.count or 1 do
		local key, label = Indexed(spec, index)
		local initializer = AddCheckbox(ctx, key, label, spec.tooltip, false)
		local when = spec.when
		Try(initializer, "AddShownPredicate", function() return values[when] and true or false end)
	end
end

function ROW.search(ctx, spec)
	for index = 1, spec.count or 1 do
		local key, label = Indexed(spec, index)
		local initializer = AddCheckbox(ctx, key, label, spec.tooltip, false)
		Try(initializer, "AddSearchTags", "vacuumtag" .. index)
	end
end

function ROW.slider(ctx, spec)
	for index = 1, spec.count or 1 do
		local key, label = Indexed(spec, index)
		local setting = AddSetting(ctx.category, key, label, Settings.VarType.Number, SLIDER_DEFAULT)
		setting:SetValueChangedCallback(OnChanged(ctx.page.name, label))
		Settings.CreateSlider(ctx.category, setting, NamedStops(), spec.tooltip)
	end
end

function ROW.button(ctx, spec)
	for index = 1, spec.count or 1 do
		local _, label = Indexed(spec, index)
		AddButton(ctx, label, spec.button, spec.tooltip)
	end
end

-- Built from the fields the mixin reads, not the helper. The helper also adds search tags from addon code.
function ROW.checkboxslider(ctx, spec)
	for index = 1, spec.count or 1 do
		local key, label = Indexed(spec, index)
		local sliderKey = key .. "level"
		local checkbox = AddSetting(ctx.category, key, label, Settings.VarType.Boolean, false)
		local slider = AddSetting(ctx.category, sliderKey, label .. " " .. spec.slider, Settings.VarType.Number, SLIDER_DEFAULT)
		checkbox:SetValueChangedCallback(OnChanged(ctx.page.name, label))
		slider:SetValueChangedCallback(OnChanged(ctx.page.name, label .. " " .. spec.slider))
		local data = { name = label, tooltip = spec.tooltip, cbSetting = checkbox, cbLabel = label, cbTooltip = spec.tooltip,
			sliderSetting = slider, sliderOptions = NamedStops(), sliderLabel = spec.slider, sliderTooltip = spec.sliderTooltip }
		ctx.layout:AddInitializer(Settings.CreateSettingInitializer("SettingsCheckboxSliderControlTemplate", data))
	end
end

-- Same registration as Create Checkbox, through the secure registrar, so this page is only that route.
function ROW.register(ctx, spec)
	for index = 1, spec.count or 1 do
		local key, label = Indexed(spec, index)
		local setting = AddSetting(ctx.category, key, label, Settings.VarType.Boolean, false)
		setting:SetValueChangedCallback(OnChanged(ctx.page.name, label))
		Settings.RegisterInitializer(ctx.category, Settings.CreateCheckboxInitializer(setting, nil, spec.tooltip))
	end
end

function ROW.open(ctx, spec)
	for _, target in ipairs(spec.targets) do
		local label = "Open " .. target
		AddButton(ctx, label, "Open", "Opens that settings page from this button.", function()
			local category = pagesByName[target]
			local id = category and category.GetID and category:GetID()
			if id then
				Settings.OpenToCategory(id)
			else
				ns.Trace("CT press %s %s missing", ctx.page.name, label)
			end
		end)
	end
end

-- The mixin reads buttonText and OnButtonClick. The button stays usable while the checkbox is off.
-- The secure builder also tags the setting's name, so this page carries that tag as well.
function ROW.checkboxbutton(ctx, spec)
	for index = 1, spec.count or 1 do
		local key, label = Indexed(spec, index)
		local setting = AddSetting(ctx.category, key, label, Settings.VarType.Boolean, false)
		setting:SetValueChangedCallback(OnChanged(ctx.page.name, label))
		local function Press()
			local ok, result = pcall(C_ChatInfo.PerformEmote, EMOTE_TOKEN)
			ns.Trace("CT press %s %s emote %s", ctx.page.name, label, ok and tostring(result) or ("failed " .. tostring(result)))
		end
		local data = Settings.CreateSettingInitializerData(setting, nil, spec.tooltip)
		data.buttonText = spec.button
		data.OnButtonClick = Press
		data.clickRequiresSet = false
		ctx.layout:AddInitializer(Settings.CreateSettingInitializer("SettingsCheckboxWithButtonControlTemplate", data))
	end
end

function ROW.dropdown(ctx, spec)
	for index = 1, spec.count or 1 do
		local key, label = Indexed(spec, index)
		local setting = AddSetting(ctx.category, key, label, Settings.VarType.Number, SLIDER_DEFAULT)
		setting:SetValueChangedCallback(OnChanged(ctx.page.name, label))
		Settings.CreateDropdown(ctx.category, setting, DropdownOptions, spec.tooltip)
	end
end

-- On every page, after the rows under test, so Last Row means the d-pad got through the page.
local function AddTrailer(ctx, pageIndex)
	AddButton(ctx, "Refresh Navigation", "Refresh", "Rebuilds gamepad navigation and logs the counts.", function()
		RefreshNavigation()
	end)
	AddCheckbox(ctx, "last" .. pageIndex, "Last Row", "The last row on this page.", false)
end

local function Build()
	local main = Settings.RegisterVerticalLayoutCategory(CATEGORY_NAME)
	pagesByName[CATEGORY_NAME] = main
	for index, page in ipairs(PAGES) do
		local category, layout = Settings.RegisterVerticalLayoutSubcategory(main, page.name)
		pagesByName[page.name] = category
		local ctx = { page = page, category = category, layout = layout, made = {} }
		for _, spec in ipairs(page.rows) do
			local build = ROW[spec.kind]
			if build then
				build(ctx, spec)
			else
				ns.Trace("CT unknown row %s", tostring(spec.kind))
			end
		end
		AddTrailer(ctx, index)
	end
	Settings.RegisterAddOnCategory(main)
	for _, page in ipairs(PAGES) do
		for _, spec in ipairs(page.rows) do
			for _, target in ipairs(spec.targets or {}) do
				if not pagesByName[target] then ns.Log("Control Test is missing the page " .. target) end
			end
		end
	end
end

-- Under securecallfunction, and it returns before FocusContainer. A post-hook on SelectCategory would sit on
-- that call (CallbackRegistry.lua:210, Blizzard_SettingsPanel.lua:836).
local function OnCategoryChanged(_, category)
	local name = CategoryName(category)
	pcall(ns.Trace, "CT show %s from %s", name, previousPage)
	previousPage = name
end

-- The settings readme registers addon categories on ADDON_LOADED, and nothing finalizes the category list later.
EventUtil.ContinueOnAddOnLoaded(addonName, function()
	EventRegistry:RegisterCallback("Settings.CategoryChanged", OnCategoryChanged, pagesByName)
	Build()
end)
--@end-debug@
