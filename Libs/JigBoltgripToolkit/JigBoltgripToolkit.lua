-- Shared home for Jig Boltgrip's Toolkit modules. Each module embeds this file; LibStub keeps the newest.
-- One Settings category for the toolkit, one subcategory per installed module.
local MAJOR, MINOR = "JigBoltgripToolkit-1.0", 74
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
	return
end

lib.title = "Jig Boltgrip's Toolkit"

-- Player-facing text goes through AceLocale-3.0 so other languages can register; without it English stands
-- (docs/standards.md, "Translations").
local L
do
	local AceLocale = LibStub("AceLocale-3.0", true)
	local english = AceLocale and AceLocale:NewLocale("JigBoltgripToolkit", "enUS", true) or {}
	for _, text in ipairs({
		"%s commands:", "Troubleshooting", "List these commands",
		"Prints these commands in your chat window, with what each one does.",
		"Commands", "Type these in chat, or run them here. /%s help lists them all.", "Run",
		"Working Build", "Read the working log. Working builds only.",
		"Working Log", "Show",
		"Opens every module's working log in the copy window.",
		"Links", "Copy link", "Website", "CurseForge", "Find it in Options, then %s, %s, %s.",
		"Open the options", "Saved data is from a newer version of %s; it was left unchanged.",
		"Self Found", "Public", "Short range.", "Medium range.", "Long range.",
		"Also tracks what your party, guild and friends find.", "Boltgrip's %s %s.",
	}) do
		english[text] = true
	end
	L = AceLocale and AceLocale:GetLocale("JigBoltgripToolkit")
		or setmetatable({}, { __index = function(_, text) return text end })
end
lib.modules = lib.modules or {}
lib.records = lib.records or {} -- module records made by NewModule, by addon name, before settings load

-- Header for modules' key bindings: a module's Bindings.xml uses category="BINDING_HEADER_JIGBOLTGRIPTOOLKIT".
BINDING_HEADER_JIGBOLTGRIPTOOLKIT = lib.title

-- Every page, the toolkit's own included, uses only Blizzard's vertical-layout initializers: a canvas page came up
-- empty and broke the controller on the Deck (docs/options.md, "Toolkit page").
function lib:GetCategory()
	if not self.category then
		self.category, self.layout = Settings.RegisterVerticalLayoutCategory(self.title)
		-- Open in the AddOns list, so the modules show; Blizzard reads the flag securely (Blizzard_Category.lua:114-123).
		self.category:SetExpanded(true)
		Settings.RegisterAddOnCategory(self.category)
	end
	return self.category, self.layout
end

-- Links from the standard TOC fields X-Website and X-Curse-Project-ID. LaunchURL and CopyToClipboard
-- are restricted, so a button opens the copy window with the address selected.
local CURSEFORGE_PROJECT_URL = "https://www.curseforge.com/projects/"

local function ModuleLinks(addonName)
	local links = {}
	local website = C_AddOns.GetAddOnMetadata(addonName, "X-Website")
	if website then table.insert(links, { L["Website"], website }) end
	local curse = C_AddOns.GetAddOnMetadata(addonName, "X-Curse-Project-ID")
	if curse then table.insert(links, { L["CurseForge"], CURSEFORGE_PROJECT_URL .. curse }) end
	return links
end

-- Chat. Everything a toolkit addon prints goes through lib:Say, lib:Print or lib:PrintBlock, so the
-- family reads as one (docs/standards.md, "Voice").
local MARK = "|TInterface\\WorldMap\\GEAR_64GREY:0|t" -- the world map's gear, at the line's height
-- A blank the gear's size (Blizzard's inline spacer), so rows under a marked line start where its text
-- does, as a tooltip's lines sit under its heading.
local ALIGN = "|TInterface\\Common\\spacer:0|t "
-- The family's own line color: a teal that matches none of the game's chat colors.
local LINE_COLOR = { r = 0x5B / 255, g = 0xD9 / 255, b = 0xDE / 255 }
local NAME_LINE_MIX = 0.25 -- share of the line color in a device's name, so the names sit together

local function AddLine(text)
	DEFAULT_CHAT_FRAME:AddMessage(text, LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b)
end

-- Text in the module's class color (RAID_CLASS_COLORS, read when printing), mixed a little toward the
-- line color: the device's name, and its commands in help.
local function InDeviceColor(module, text)
	local class = module and module.class and RAID_CLASS_COLORS[module.class]
	if not class then
		return text
	end
	local function Mix(channel)
		return math.floor((class[channel] * (1 - NAME_LINE_MIX) + LINE_COLOR[channel] * NAME_LINE_MIX) * 255 + 0.5)
	end
	return ("|cff%02x%02x%02x%s|r"):format(Mix("r"), Mix("g"), Mix("b"), text)
end

local function DeviceName(module)
	return InDeviceColor(module, module.title)
end

-- A voiced line: the mark, "Boltgrip's", the device's name and the noise it makes (no end mark; the library adds
-- the period), then the report, robot-speak beats each ending in "!". line is a Voice.lua entry
-- ({ noise, report, reportOne }): the arguments format the report, and a first argument of 1 picks reportOne.
function lib:Say(module, line, ...)
	local noise, report = line, ...
	if type(line) == "table" then
		noise = line.noise
		report = (... == 1 and line.reportOne) or line.report
		if type(report) == "string" and select("#", ...) > 0 then report = report:format(...) end
	end
	assert(type(noise) == "string" and noise ~= "" and type(report) == "string" and report ~= "",
		("%s: a voiced line needs a noise and a report (docs/standards.md, \"Voice\")"):format(tostring(module.title)))
	AddLine(("%s %s %s"):format(MARK, L["Boltgrip's %s %s."]:format(DeviceName(module), noise), report))
end

-- A voiced line said once ever: db[key] remembers it, for the first time a module changes something the
-- player did not set (docs/standards.md, "Game settings"). Returns whether it spoke.
function lib:SayOnce(module, db, key, line, ...)
	if db[key] then
		return false
	end
	db[key] = true
	self:Say(module, line, ...)
	return true
end

-- A plain line with the mark: an error's text, a development command's answer.
function lib:Print(text)
	AddLine(MARK .. " " .. text)
end

-- Several lines that belong together: the header carries the mark, the rows sit under its text.
function lib:PrintBlock(header, rows)
	self:Print(header)
	for _, row in ipairs(rows) do
		AddLine(ALIGN .. row)
	end
end

-- Asked where the answer is used, never kept: the client switches interface style on INPUT_DEVICE_INTERFACE_TRANSITION
-- without a reload (Blizzard_SharedXML/InputUtil.lua).
local function GamepadUI()
	return InputUtil ~= nil and InputUtil.IsGamepadUIEnabled ~= nil and InputUtil.IsGamepadUIEnabled() or false
end
lib.IsGamepadUI = GamepadUI

-- A copy window is of no use without a keyboard, so under the gamepad interface the address goes to chat.
local function ShowLink(title, url)
	if GamepadUI() then
		lib:Print(url)
	else
		lib:ShowText(title, url)
	end
end

-- Values the client may hide from addons (issecretvalue). Readable is false for nil and for a hidden value;
-- Describe is tostring that never touches one; GUID gives a GUID's kind and its numeric ID ("Creature",
-- 1234), nothing for an unreadable or missing GUID. An Item or Player GUID has no ID field, so its ID is nil.
function lib.Readable(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end

function lib.Describe(value)
	if issecretvalue and issecretvalue(value) then
		return "<secret>"
	end
	return tostring(value)
end

function lib.GUID(guid)
	if not lib.Readable(guid) or type(guid) ~= "string" then
		return nil
	end
	local kind, _, _, _, _, id = strsplit("-", guid)
	return kind, tonumber(id)
end

-- A module's record exists from file load, so every file can name the module to the kit before the Settings
-- category does (RegisterModule fills it in later). command is the slash word, the addon's name in lower
-- case unless given.
function lib:NewModule(addonName, class, command)
	local module = self.records[addonName]
	if not module then
		module = { addon = addonName, title = C_AddOns.GetAddOnMetadata(addonName, "Title"),
			notes = C_AddOns.GetAddOnMetadata(addonName, "Notes") }
		self.records[addonName] = module
	end
	module.class = class or module.class
	module.command = command or module.command or addonName:lower()
	return module
end

-- Saved data: schema, ordered migrations and defaults, run once the saved variable has loaded (docs/standards.md,
-- "Data"). A save from a newer build is left untouched and the module runs on an empty copy.
local function CopyDefault(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, item in pairs(value) do copy[key] = CopyDefault(item) end
	return copy
end

-- A keyed table of defaults is filled key by key, so a key added to a nested table reaches saves that already have it; a list is
-- one value, as a player's shorter list must not be topped up.
local function FillDefaults(db, defaults)
	for key, value in pairs(defaults or {}) do
		if db[key] == nil then
			db[key] = CopyDefault(value)
		elseif type(value) == "table" and type(db[key]) == "table" and value[1] == nil then
			FillDefaults(db[key], value)
		end
	end
end

-- The saved variable as a table to use, and whether it is the saved one: a value that is not a table, or from a newer build, is
-- left as it is and the module runs on an empty copy.
local function UsableSave(self, module, globalName, current)
	local saved = _G[globalName]
	if saved ~= nil and type(saved) ~= "table" then
		self:Trace(module, "SAVED %s is a %s, not a table; left unchanged, running on an empty copy", globalName, type(saved))
		return {}, false
	end
	local result = saved or {}
	if type(result.schema) == "number" and result.schema > current then
		return {}, false, true
	end
	return result, true
end

-- Each table runs the steps above its own schema number, so a character table is brought up on its own login, whatever the
-- account's table has already done. A character table with no number is taken as current: it was made before the number was kept, and no step ran for it.
local function Upgrade(target, steps, from, to, ...)
	for step = from + 1, to do
		if steps and steps[step] then steps[step](target, ...) end
		target.schema = step
	end
	target.schema = to
end

function lib:LoadSaved(module, globalName, spec)
	local db, usable, newer = UsableSave(self, module, globalName, spec.schema)
	local characterDb, characterUsable, characterNewer
	if spec.character then
		characterDb, characterUsable, characterNewer = UsableSave(self, module, spec.character, spec.schema)
	end
	if newer or characterNewer then
		self:Print(spec.newer or L["Saved data is from a newer version of %s; it was left unchanged."]:format(module.title))
	end
	-- Both saved variables are written together or not at all: a step, a stamp or a default written into one while the other
	-- is left alone would pair data of two builds. Either one newer (or not a table) leaves both as they are, and the module
	-- runs on empty copies.
	if not (usable and (characterUsable ~= false)) then
		self:Trace(module, "SAVED %s left unchanged; running on empty copies", globalName)
		db, characterDb = {}, characterDb and {}
		FillDefaults(db, spec.defaults)
		db.schema = spec.schema
		if characterDb then
			FillDefaults(characterDb, spec.characterDefaults)
			characterDb.schema = spec.schema
		end
		return db, characterDb
	end
	_G[globalName] = db
	if characterDb then _G[spec.character] = characterDb end
	local version = type(db.schema) == "number" and db.schema or (spec.legacy and spec.legacy(db)) or spec.schema
	-- An unnumbered character table is taken as current (docs/standards.md, "Saved data"), whatever the account's number is.
	local characterVersion = characterDb and (type(characterDb.schema) == "number" and characterDb.schema or spec.schema)
	-- The account's steps get the character table too, as the first character's login runs them (once, for the account).
	Upgrade(db, spec.migrations, version, spec.schema, characterDb)
	if characterDb then Upgrade(characterDb, spec.characterMigrations, characterVersion, spec.schema) end
	FillDefaults(db, spec.defaults)
	if characterDb then FillDefaults(characterDb, spec.characterDefaults) end
	return db, characterDb
end

-- One registration per addon, so a second copy loading the same module cannot add a second page.
-- class is a RAID_CLASS_COLORS key ("DRUID") for the device's name; without one the line color is used.
function lib:RegisterModule(addonName, class)
	for _, existing in ipairs(self.modules) do
		if existing.addon == addonName then
			existing.class = class or existing.class
			return existing
		end
	end
	local title = C_AddOns.GetAddOnMetadata(addonName, "Title")
	local notes = C_AddOns.GetAddOnMetadata(addonName, "Notes")
	local parent = self:GetCategory()
	local category, layout = Settings.RegisterVerticalLayoutSubcategory(parent, title)
	local module = self.records[addonName] or { addon = addonName }
	module.title, module.notes, module.category, module.layout = title, notes, category, layout
	module.class = class or module.class
	table.insert(self.modules, module)
	return module
end

-- No Open row per module: the AddOns list already shows each module's page under the toolkit, and under the gamepad
-- interface a button could only say where the page is (docs/options.md, "Toolkit page"). Kept empty because
-- MINOR 66 to 69 copies call it from their working-build rows.
function lib:AddModuleRows() end

-- Selecting our category from addon code is blocked under the gamepad interface (docs/standards.md, "Gamepad UI");
-- there the player is told where the page is instead.
function lib:OpenOptions(module)
	if GamepadUI() then
		self:Print(L["Find it in Options, then %s, %s, %s."]:format(ADDONS, self.title, module.title))
	else
		Settings.OpenToCategory(module.category:GetID())
	end
end

-- Working builds. A module calls these from its own debug-only block, so a release never does; the library
-- file itself is the same in every build. One listener and one record serve every module.

-- Temporary values, never saved (docs/standards.md, "Game settings"): asked on only, and put back when something reverts them.
local WORKING_CVARS = {
	scriptErrors = "1",
	-- Logs/taint.log names the access that tainted a blocked call, which no event or stack shows; level 2
	-- is what Forever addon maintainers ask for when the gamepad UI blames an addon.
	taintLog = "2",
}

local function ApplyWorkingCVars()
	for name, value in pairs(WORKING_CVARS) do
		if C_CVar.GetCVar(name) ~= value then
			C_CVar.SetTempCVar(name, value)
			lib:LogAll(("working build: %s set to %s for this session"):format(name, value))
		end
	end
end

-- Shows Lua errors and reports actions the client blocked, so a fault while developing is seen.
function lib:EnableWorkingBuild()
	ApplyWorkingCVars()
	if self.blockedListener then
		return
	end
	self.blockedListener = CreateFrame("Frame")
	self.blockedListener:RegisterEvent("ADDON_ACTION_BLOCKED")
	self.blockedListener:RegisterEvent("ADDON_ACTION_FORBIDDEN")
	self.blockedListener:RegisterEvent("CVAR_UPDATE")
	self.blockedListener:SetScript("OnEvent", function(_, event, addon, action)
		if event == "CVAR_UPDATE" then
			if WORKING_CVARS[addon] then ApplyWorkingCVars() end -- another addon reverted one
			return
		end
		local line = ("%s: %s, %s"):format(event, tostring(addon), tostring(action))
		lib:Print(line)
		-- Shared context: every log keeps it, with the call stack, to read after a reload.
		lib:LogAll(line)
		lib:LogAll(debugstack(2, 12, 0))
	end)
	-- "Interface action failed because of an AddOn": gamepad navigation shows it for a call from tainted
	-- code without firing either event above (Blizzard_GamepadSmartNavigation, EnsureIsSecure), so the
	-- message itself is logged where Blizzard prints it (ChatFrameUtil.lua), with the stack that led there.
	if ChatFrameUtil and ChatFrameUtil.AddSystemMessage then
		hooksecurefunc(ChatFrameUtil, "AddSystemMessage", function(text)
			if lib.Readable(text) and text == INTERFACE_ACTION_BLOCKED then
				lib:LogAll("interface action blocked (no event): " .. tostring(text))
				lib:LogAll(debugstack(3, 12, 0))
			end
		end)
	end
	-- Gamepad navigation, one line per d-pad release: where the cursor landed, and whether its state is
	-- tainted and by which addon (issecurevariable), since tainted state makes it drop the move
	-- (SmartNavigation.lua, HandleNavigationInput calls EnsureIsSecure first).
	EventUtil.ContinueOnAddOnLoaded("Blizzard_GamepadSmartNavigation", function()
		local directions = {}
		for name, direction in pairs(SMART_NAV_INPUT_DIRECTION) do directions[direction] = name end
		local function Taint(t, key)
			local secure, addon = issecurevariable(t, key)
			return secure and "clean" or ("tainted by " .. tostring(addon))
		end
		hooksecurefunc(SmartNavigation, "HandleNavigationInput", function(nav, isDown, direction)
			if isDown then return end
			local button = nav.currentButton
			local data = button and button.GetElementData and button:GetElementData()
			local recipe = type(data) == "table" and data.recipeInfo and data.recipeInfo.recipeID
			lib:LogAll(("pad %s -> %s%s | cursor %s"):format(directions[direction] or "?",
				button and button.GetDebugName and button:GetDebugName() or "nothing",
				recipe and (" recipe " .. recipe) or "", Taint(nav, "currentButton")))
		end)
	end)
	-- Lua errors, as Blizzard's error window receives them (Blizzard_ScriptErrorsFrame.lua, DisplayMessageInternal);
	-- the client's own error handler list takes secure code only (AddLuaErrorHandler asserts issecure()).
	EventUtil.ContinueOnAddOnLoaded("Blizzard_ScriptErrorsFrame", function()
		hooksecurefunc(ScriptErrorsFrame, "DisplayMessageInternal", function(_, message, _, stack)
			if not issecretvalue(message) then
				lib:LogAll("Lua error: " .. tostring(message))
				if stack and not issecretvalue(stack) then lib:LogAll(stack) end
			end
		end)
	end)
end

-- The log lives in the module's own saved table, since the library has none (docs/standards.md, "Working
-- build helpers"). Trimming LOG_TRIM at once means a full log is not shifted on every new line.
local LOG_LINES, LOG_TRIM = 20000, 1000
local LOG_REFRESH_SECONDS = 0.25 -- an open log window rebuilds at most this often
lib.LOG_LINES, lib.LOG_TRIM = LOG_LINES, LOG_TRIM
lib.logs = lib.logs or {}
lib.logOrder = lib.logOrder or {} -- addon names in the order their logs started, for /boltgrip log

-- A paused log takes no shared context.
function lib:LogAll(line)
	for _, addon in ipairs(self.logOrder) do
		local log = self.logs[addon]
		if log.watching then self:Log(log.module, line) end
	end
end

-- Whether the module's log is taking lines, so a caller can skip building one.
function lib:IsLogging(module)
	local log = self.logs[module.addon]
	return log ~= nil and log.watching == true
end

-- One listener for every module's watch: each event is registered once and passed to every watching
-- module that asked for it, after the kit's own zone context.
-- IDs first, since both addons place things by them; names follow for a reader.
local function ZoneLine()
	local mapID = C_Map.GetBestMapForUnit("player")
	local info = mapID and C_Map.GetMapInfo(mapID)
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	local areas = position and C_MapExplorationInfo.GetExploredAreaIDsAtPosition(mapID, position)
	return ("zone %s areas %s | %s | %s"):format(tostring(mapID), areas and table.concat(areas, ",") or "-",
		info and info.name or "?", GetSubZoneText() or "")
end
-- Context every log keeps while watching: where the player is, which input is in use (a report reads
-- each line against it), and each screenshot, which is the player's way to mark a moment worth reading.
local CONTEXT_EVENTS = {
	ZONE_CHANGED_NEW_AREA = ZoneLine, ZONE_CHANGED = ZoneLine, ZONE_CHANGED_INDOORS = ZoneLine,
	GAME_PAD_ACTIVE_CHANGED = function(isActive)
		return "input: " .. (isActive and "gamepad" or "keyboard and mouse")
	end,
	SCREENSHOT_SUCCEEDED = function() return "screenshot taken: " .. date("%m%d%y_%H%M%S") end,
}

local function UpdateWatchEvents()
	local frame = lib.watchFrame
	if not frame then
		frame = CreateFrame("Frame")
		lib.watchFrame = frame
		frame:SetScript("OnEvent", function(_, event, ...)
			if CONTEXT_EVENTS[event] then
				lib:LogAll(CONTEXT_EVENTS[event](...))
			end
			for _, addon in ipairs(lib.logOrder) do
				local log = lib.logs[addon]
				local handler = log.watching and log.handlers[event]
				if handler then
					local ok, problem = pcall(handler, ...)
					if not ok then
						local line = ("Malfunction in %s! %s"):format(event, tostring(problem))
						lib:Log(log.module, line)
						lib:Print(("%s: %s"):format(log.module.title, line))
					end
				end
			end
		end)
	end
	frame:UnregisterAllEvents()
	local any = false
	for _, addon in ipairs(lib.logOrder) do
		local log = lib.logs[addon]
		if log.watching then
			any = true
			for event in pairs(log.handlers) do frame:RegisterEvent(event) end
		end
	end
	if any then
		for event in pairs(CONTEXT_EVENTS) do frame:RegisterEvent(event) end
	end
end

-- The game's own CPU measurement, read as Blizzard's AddonList.lua (GetAddonMetricPercent) reads it.
local function ProfilerLine(addon)
	if not (C_AddOnProfiler and C_AddOnProfiler.IsEnabled()) then return nil end
	local metric = Enum.AddOnProfilerMetric
	local function Share(which)
		local app, overall = C_AddOnProfiler.GetApplicationMetric(which), C_AddOnProfiler.GetOverallMetric(which)
		local own = C_AddOnProfiler.GetAddOnMetric(addon, which)
		local total = app - overall + own
		return total > 0 and own / total * 100 or 0
	end
	return ("CPU game's measure: session average %.3f ms (%.2f%% of frame time) | recent %.2f%% | peak %.2f ms | frames over 1 ms %d, 5 ms %d, 10 ms %d"):format(
		C_AddOnProfiler.GetAddOnMetric(addon, metric.SessionAverageTime), Share(metric.SessionAverageTime),
		Share(metric.RecentAverageTime), C_AddOnProfiler.GetAddOnMetric(addon, metric.PeakTime),
		C_AddOnProfiler.GetAddOnMetric(addon, metric.CountTimeOver1Ms), C_AddOnProfiler.GetAddOnMetric(addon, metric.CountTimeOver5Ms),
		C_AddOnProfiler.GetAddOnMetric(addon, metric.CountTimeOver10Ms))
end

-- How the game is being played: language, screen, UI scale and gamepad, so a report reads on its own.
local function DeviceLine()
	local width, height = GetPhysicalScreenSize()
	local pad = C_GamePad and C_GamePad.IsEnabled()
	return ("device: locale %s | screen %sx%s | UI scale %s | gamepad %s, device %s"):format(tostring(GetLocale()),
		tostring(width), tostring(height), tostring(UIParent and UIParent:GetEffectiveScale()),
		pad and "on" or "off", tostring(pad and C_GamePad.GetActiveDeviceID() or "-"))
end

local function WriteTimings()
	for _, log in pairs(lib.logs) do
		local lines = log.watching and lib:TimingLines(log.module) or {}
		local cpu = log.watching and ProfilerLine(log.module.addon)
		if #lines > 0 or cpu then
			local version, build = GetBuildInfo()
			lib:Log(log.module, "")
			lib:Log(log.module, ("%s PERF session on %s (%s), %s level %d"):format(date("%Y-%m-%d %H:%M:%S"), version,
				build, UnitName("player") or UNKNOWN, UnitLevel("player") or 0), true)
			if cpu then lib:Log(log.module, cpu) end
			for _, line in ipairs(lines) do
				lib:Log(log.module, line)
			end
		end
	end
end

-- Starts the module's log once its saved table is loaded; resumes a watch left on.
function lib:StartLog(module, saved, handlers)
	self:EnableWorkingBuild()
	-- Without its saved table a module keeps no log; a working build must not break over it.
	if type(saved) ~= "table" then
		self:Print(("%s: no saved table for the log yet; nothing is logged this session."):format(tostring(module.title)))
		return
	end
	local log = self.logs[module.addon]
	if not log then
		log = {}
		self.logs[module.addon] = log
		self.logOrder[#self.logOrder + 1] = module.addon
	end
	log.module, log.saved, log.handlers = module, saved, handlers or {}
	self:AddWorkingSection(module)
	if module.workingSection then self:ShowBuilds() end
	saved.devLog = saved.devLog or {}
	if not self.logWriter then
		self.logWriter = CreateFrame("Frame")
		self.logWriter:RegisterEvent("PLAYER_LOGOUT")
		self.logWriter:SetScript("OnEvent", WriteTimings)
	end
	-- A working build always logs: there is no switch to turn it off (docs/standards.md, "Working build").
	saved.watch = nil
	-- Session header: one line per load, so each log reads on its own.
	local version, build = GetBuildInfo()
	self:Log(module, "")
	self:Log(module, ("%s session: client %s (%s) | addon %s | %s, level %d | %s"):format(date("%Y-%m-%d %H:%M:%S"),
		version, build, C_AddOns.GetAddOnMetadata(module.addon, "Version") or "?", UnitName("player") or "?",
		UnitLevel("player") or 0, ZoneLine()), true)
	self:Log(module, DeviceLine())
	if not log.watching then
		self:SetWatch(module, true, true)
	end
end

-- A line for the module's log while it is logging; nothing otherwise, and nothing in a release, where no
-- log is started. For events worth reading back but not worth a chat line (sharing, timers). With format
-- arguments the line is built only while logging, so a call costs nothing otherwise.
function lib:Trace(module, line, ...)
	local log = self.logs[module.addon]
	if log and log.watching then
		self:Log(module, select("#", ...) > 0 and line:format(...) or line)
	end
end

-- Every event a module's frames receive, counted and written once a second as "EVENT name xN", so the log
-- shows what fired around a problem without each handler tracing it. The kit's own frames call this from
-- their one dispatcher; the count costs nothing while not logging.
lib.eventCounts = lib.eventCounts or {}
function lib:CountEvent(module, event)
	local log = self.logs[module.addon]
	if not (log and log.watching) then return end
	local state = self.eventCounts[module.addon]
	if not state then
		state = { counts = {} }
		self.eventCounts[module.addon] = state
	end
	state.counts[event] = (state.counts[event] or 0) + 1
	if not state.flushing then
		state.flushing = true
		C_Timer.After(1, function()
			state.flushing = false
			local names = {}
			for name in pairs(state.counts) do names[#names + 1] = name end
			table.sort(names)
			for _, name in ipairs(names) do
				lib:Trace(module, state.counts[name] > 1 and ("EVENT %s x%d"):format(name, state.counts[name]) or "EVENT " .. name)
			end
			state.counts = {}
		end)
	end
end

-- A frame that listens for events (docs/standards.md, "Working build helpers"): the kit sets its one OnEvent, which
-- counts the event for the log and runs handlers[event](...). options: unit = { EVENT = "player" }, later = { EVENT = true }.
function lib:EventFrame(module, handlers, options)
	options = options or {}
	local frame = CreateFrame("Frame")
	for event in pairs(handlers) do
		local unit = options.unit and options.unit[event]
		-- A game update that drops an event makes the module slower, not broken (Blizzard_Console.lua guards the same way).
		if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
			lib:Trace(module, "EVENT %s is not a client event; not registered", event)
		elseif unit then
			frame:RegisterUnitEvent(event, unit)
		elseif not (options.later and options.later[event]) then
			frame:RegisterEvent(event)
		end
	end
	frame:SetScript("OnEvent", function(_, event, ...)
		lib:CountEvent(module, event)
		local handler = handlers[event]
		if handler then handler(...) end
	end)
	return frame
end

-- Counts a frame's events by a hook. Kept for older modules; a SetScript("OnEvent") after it drops the
-- count, which is why new frames come from EventFrame.
function lib:WatchEvents(module, frame)
	frame:HookScript("OnEvent", function(_, event)
		lib:CountEvent(module, event)
	end)
end

-- A dated line already carries its own date, so it is not stamped again.
function lib:Log(module, line, dated)
	local log = self.logs[module.addon]
	if not log then return end
	local lines = log.saved.devLog
	lines[#lines + 1] = (dated or line == "") and line or date("%H:%M:%S ") .. line
	if #lines > LOG_LINES then
		local over = #lines - (LOG_LINES - LOG_TRIM)
		-- Trimmed in one pass, not by removing the first line again and again.
		local total = #lines
		for index = 1, total - over do lines[index] = lines[index + over] end
		for index = total - over + 1, total do lines[index] = nil end
		log.saved.devLogRun = math.max((log.saved.devLogRun or 1) - over, 1)
		if log.viewStart then log.viewStart = math.max(log.viewStart - over, 1) end
	end
	-- An open log window follows on a short delay, however many lines arrive: a rebuild joins every line kept.
	if self:IsTextShown() and (self.textFrame.log == log or self.textFrame.log == "all") and not self.refreshQueued then
		self.refreshQueued = true
		C_Timer.After(LOG_REFRESH_SECONDS, function()
			lib.refreshQueued = nil
			local shown = lib:IsTextShown() and lib.textFrame.log
			if shown == "all" then
				lib:ShowAllLogs(lib.textFrame.allLines, true)
			elseif shown then
				lib:ShowLog(shown.module, nil, true)
			end
		end)
	end
end

-- The copy window: the current run, a command's own lines, or with all, everything kept.
function lib:ShowLog(module, all, refresh)
	local log = self.logs[module.addon]
	if not log then return end
	local lines = log.saved.devLog
	local first = all and 1 or math.min(log.viewStart or log.saved.devLogRun or 1, #lines + 1)
	self:ShowText(module.title .. ": Log", table.concat(lines, "\n", first), refresh)
	self.textFrame.log = log
end

-- /boltgrip log: every module's log in one copy window, a section per module under its title. Not merged
-- by time: lines carry only the time of day, so a merge across days or reloads would interleave wrongly.
function lib:ShowAllLogs(all, refresh)
	local sections = {}
	for _, addon in ipairs(self.logOrder) do
		local log = self.logs[addon]
		local lines = log.saved.devLog
		local first = all and 1 or math.min(log.viewStart or log.saved.devLogRun or 1, #lines + 1)
		sections[#sections + 1] = log.module.title .. "\n" .. table.concat(lines, "\n", first)
	end
	self:ShowText(self.title .. ": Log", table.concat(sections, "\n\n"), refresh)
	self.textFrame.log, self.textFrame.allLines = "all", all
end

-- The next line starts a new run; a running watch keeps its run unless forced.
function lib:StartRun(module, force)
	local log = self.logs[module.addon]
	if log and (force or not log.saved.watch) then
		log.saved.devLogRun = #log.saved.devLog + 1
	end
end

-- Watch: the module's handlers ({ [event] = function(...) }) run on their events and log what they see;
-- an error is logged and shown, not lost. Saved, so it resumes after a reload.
function lib:SetWatch(module, on, quiet)
	local log = self.logs[module.addon]
	if not log then return end
	if on and not log.saved.watch then
		self:StartRun(module, true)
		self:Log(module, date("%Y-%m-%d %H:%M:%S") .. " watch on | " .. ZoneLine(), true)
	end
	log.watching = on or nil
	log.saved.watch = on and true or false
	UpdateWatchEvents()
	if not quiet then
		self:Print(("%s: %s"):format(module.title, on and "Watch enabled!" or "Watch disabled!"))
	end
end

-- Wraps a working-build command: logs a header (time, command, client, addon version, character, then
-- the module's own lines from details()), runs it, and shows its lines in the copy window.
function lib:LoggedCommand(module, action, run, details)
	return function(text)
		local log = self.logs[module.addon]
		if not log then return run(text) end
		local version, build = GetBuildInfo()
		local _, faction = UnitFactionGroup("player")
		self:Log(module, "")
		self:StartRun(module)
		log.viewStart = #log.saved.devLog + 1
		self:Log(module, ("%s /%s %s"):format(date("%Y-%m-%d %H:%M:%S"), module.command or module.addon:lower(), action), true)
		self:Log(module, ("client %s (%s) | addon %s | %s, %s, level %d"):format(version, build,
			C_AddOns.GetAddOnMetadata(module.addon, "Version") or "?", UnitName("player"), tostring(faction),
			UnitLevel("player")))
		for _, line in ipairs(details and details() or {}) do
			self:Log(module, line)
		end
		run(text)
		self:ShowLog(module)
	end
end

-- One switch and one viewer for every module that started a log. Release builds start none, so these
-- do nothing there and are not listed.
local WORKING_BUILD_ROWS = {
	"/boltgrip log [all|clear] - Show every addon's log; \"all\" shows everything kept, \"clear\" empties them",
}

local function KitCommand(name, word)
	if #lib.logOrder == 0 or name ~= "log" then
		return false
	end
	word = (word or ""):lower()
	if word == "clear" then
		for _, addon in ipairs(lib.logOrder) do
			local saved = lib.logs[addon].saved
			saved.devLog, saved.devLogRun = {}, nil
		end
		lib:Print("Logs purged!")
	elseif word == "all" or word == "" then
		for _, addon in ipairs(lib.logOrder) do
			lib.logs[addon].viewStart = nil
		end
		lib:ShowAllLogs(word == "all")
	else
		lib:Print(WORKING_BUILD_ROWS[1])
	end
	return true
end

-- Timing: each name keeps its run count, total and slowest run, per module, for the session.
lib.timings = lib.timings or {}

function lib:TimeMs(module, name, ms)
	local record = self.timings[module.addon]
	if not record then
		record = { order = {} }
		self.timings[module.addon] = record
	end
	local entry = record[name]
	if not entry then
		entry = { count = 0, total = 0, max = 0 }
		record[name] = entry
		record.order[#record.order + 1] = name
	end
	entry.count, entry.total = entry.count + 1, entry.total + ms
	if ms > entry.max then entry.max = ms end
end

-- Times a call that began at started (from debugprofilestop()).
function lib:Time(module, name, started)
	self:TimeMs(module, name, debugprofilestop() - started)
end

-- The module's timings as lines, for its log or a window.
function lib:TimingLines(module)
	local lines, record = {}, self.timings[module.addon]
	for _, name in ipairs(record and record.order or {}) do
		local entry = record[name]
		lines[#lines + 1] = ("PERF %-24s runs %5d | average %7.2f ms | slowest %7.2f ms | total %8.1f ms"):format(
			name, entry.count, entry.total / entry.count, entry.max, entry.total)
	end
	return lines
end

-- Options pages are data built from Blizzard's controls, so every page matches. The data shape follows
-- AceConfig's options tables; the row kinds and fields are in docs/standards.md, "Options".

-- Tooltip text of a row: its tooltip, one line per option for a choice, then its note. The tooltip is the
-- only place addon text can sit beside a Blizzard control without a row of our own.
local function RowTooltip(row)
	local lines = { row.tooltip }
	for _, choice in ipairs(row.kind == "choice" and row.values or {}) do
		-- Each option as a gold heading over its sentence, the way Blizzard's tooltips set a name over its text;
		-- settings text takes no colons.
		if choice.description then
			lines[#lines + 1] = "\n" .. NORMAL_FONT_COLOR:WrapTextInColorCode(choice.label)
			lines[#lines + 1] = choice.description
		end
	end
	lines[#lines + 1] = row.note
	return #lines > 0 and table.concat(lines, "\n") or nil
end

-- A choice is Blizzard's slider whose value is the option's position. The setting reads and writes
-- through this table, so the module's saved value stays its own and an unknown saved value reads as the default.
local function ChoiceStore(db, values, default)
	local function position(value)
		for index, choice in ipairs(values) do
			if choice.value == value then return index end
		end
	end
	local defaultPosition = assert(position(default), "a choice row's default must be one of its values")
	return setmetatable({}, {
		__index = function(_, key) return position(db[key]) or defaultPosition end,
		__newindex = function(_, key, index) db[key] = values[index].value end,
	}), defaultPosition
end

local VAR_TYPES = { boolean = "Boolean", number = "Number", string = "String" }

-- One order on every page (docs/standards.md, "Options"); each section says its place.
-- Key bindings come after the game's other settings, as Blizzard's Keybindings page does (docs/options.md, "Order and grouping").
local SECTION_PLACES = { sources = 1, features = 2, blizzard = 3, keys = 4 }

-- Blizzard's sections in the order of its own Settings pages, read from the game's order table
-- (Blizzard_SettingsDefinitions_Frame, GameplaySettingsGroup.lua); a page not in it, such as Audio,
-- comes after those, in the order the module lists it.
local function BlizzardOrder(heading)
	local order = CUSTOM_GAMEPLAY_SETTINGS_ORDER
	return order and order[heading] or math.huge
end

local function OrderedSections(sections)
	local ordered = {}
	for index, section in ipairs(sections) do
		local rank = assert(SECTION_PLACES[section.place], ("section %q needs a place: sources, features or blizzard"):format(
			tostring(section.heading)))
		-- A sources section is exactly one row of the kit's source choices, plus any rows under it (sharing).
		if section.place == "sources" then
			assert(section.rows[1] and section.rows[1].kind == "choice",
				("section %q: the source choice comes first"):format(section.heading))
			local choices = 0
			for _, row in ipairs(section.rows) do
				if row.kind == "choice" then
					assert(lib.sourceChoiceSets[row.values], ("section %q: the choice must come from SourceChoices"):format(section.heading))
					choices = choices + 1
				end
			end
			assert(choices == 1, ("section %q needs exactly one source choice"):format(section.heading))
		end
		if section.place == "blizzard" and section.heading == SETTINGS_KEYBINDINGS_LABEL then rank = SECTION_PLACES.keys end
		ordered[#ordered + 1] = { section = section, rank = rank, index = index,
			blizzard = section.place == "blizzard" and BlizzardOrder(section.heading) or 0 }
	end
	table.sort(ordered, function(left, right)
		if left.rank ~= right.rank then return left.rank < right.rank end
		if left.blizzard ~= right.blizzard then return left.blizzard < right.blizzard end
		return left.index < right.index
	end)
	for index, entry in ipairs(ordered) do ordered[index] = entry.section end
	return ordered
end

-- Source choices are the kit's: names, openings and the friends line, so every module reads the same.
-- The module gives its own whole sentences, since a sentence built around a slotted word cannot be
-- translated well; spec's fields are in docs/standards.md, "Options".
lib.SOURCE_LEVEL = { SELF = 1, FRIENDS = 2, PUBLIC = 3 }
local SOURCE_CHOICES = {
	{ name = L["Self Found"], opening = L["Short range."], text = function(spec) return spec.self end },
	{ name = FRIENDS, opening = L["Medium range."],
		text = function(spec) return spec.friends and L["Also tracks what your party, guild and friends find."] end },
	{ name = L["Public"], opening = L["Long range."], text = function(spec) return spec.public end },
}

-- Values from here are marked, so BuildOptions can refuse source choices built by hand.
lib.sourceChoiceSets = lib.sourceChoiceSets or setmetatable({}, { __mode = "k" })

function lib:SourceChoices(spec)
	assert(type(spec.self) == "string", "SourceChoices needs spec.self, the module's sentence for what it tracks alone")
	local choices = {}
	self.sourceChoiceSets[choices] = true
	for level, choice in ipairs(SOURCE_CHOICES) do
		local text = choice.text(spec)
		if text then
			choices[#choices + 1] = { value = level, label = choice.name,
				description = spec.openings == false and text or (choice.opening .. " " .. text) }
		end
	end
	return choices
end

function lib:BuildOptions(module, db, sections)
	local category, layout, settings, rows = module.category, module.layout, {}, {}
	for _, section in ipairs(OrderedSections(sections)) do
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(section.heading, section.tooltip))
		for _, row in ipairs(section.rows) do
			local setting, initializer
			local store, default = db, row.default
			if row.kind == "choice" then store, default = ChoiceStore(db, row.values, row.default) end
			if row.key then
				setting = Settings.RegisterAddOnSetting(category, module.addon .. "_" .. row.key, row.key, store,
					Settings.VarType[VAR_TYPES[type(default)]], row.label, default)
				settings[row.key] = setting
			end
			if row.kind == "checkbox" then
				initializer = Settings.CreateCheckbox(category, setting, RowTooltip(row))
				if row.under then
					-- A child built before its parent would silently stay a top-level, always-clickable row.
					local parent = assert(rows[row.under], ("row %q: under %q must name a checkbox listed above it"):format(
						tostring(row.key), tostring(row.under)))
					initializer:SetParentInitializer(parent, function() return settings[row.under]:GetValue() end)
				end
			elseif row.kind == "choice" then
				-- Blizzard's standard slider: addon-owned dropdowns and rows taint the Gamepad UI (docs/standards.md, "Gamepad UI").
				local options = Settings.CreateSliderOptions(1, #row.values, 1)
				options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(index)
					return row.values[index] and row.values[index].label or ""
				end)
				initializer = Settings.CreateSlider(category, setting, options, RowTooltip(row))
			elseif row.kind == "keybinding" then
				-- Blizzard's own key binding row, as the Controls page shows the Interact Key (Controls.lua).
				local bindingIndex = C_KeyBindings.GetBindingIndex(row.binding)
				if bindingIndex then
					initializer = CreateKeybindingEntryInitializer(bindingIndex, true)
					initializer:AddSearchTags(GetBindingName(row.binding))
					layout:AddInitializer(initializer)
				else
					-- A binding the game does not know leaves no row; say so rather than lose it unseen.
					lib:Print(("%s: no key binding %s, so its row is left out."):format(module.title, tostring(row.binding)))
				end
			end
			if setting and row.onChange then
				setting:SetValueChangedCallback(function(_, value)
					row.onChange(row.kind == "choice" and row.values[value].value or value)
				end)
			end
			if row.key then rows[row.key] = initializer end
		end
	end
	return settings
end

-- Working builds get buttons, since a gamepad has no keyboard. The toolkit's page holds only the kit's watch switch and
-- log viewer, named with the verb on the button as Blizzard's rows are; no reload row, the game menu has one
-- (docs/options.md, "Toolkit page"). A module's own development commands go on its own page.
local function AddKitWorkingRows()
	local _, layout = lib:GetCategory()
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["Working Build"],
		L["Read the working log. Working builds only."]))
	layout:AddInitializer(CreateSettingsButtonInitializer(L["Working Log"], L["Show"], function() KitCommand("log") end,
		L["Opens every module's working log in the copy window."], false))
end

local function AddWorkingRows(module)
	local command, working = lib.commands[module.command or ""], {}
	for _, entry in ipairs(command and command.entries or {}) do
		if entry.troubleshooting then table.insert(working, entry) end
	end
	if not lib.kitWorkingRows then
		lib.kitWorkingRows = true
		AddKitWorkingRows()
	end
	if #working == 0 then return end
	module.layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["Working Build"]))
	for _, entry in ipairs(working) do
		module.layout:AddInitializer(CreateSettingsButtonInitializer(entry.label or ("/" .. command.name .. " " .. entry.action),
			entry.button or L["Run"], function() entry.run("") end, entry.description, false))
	end
end

-- Working builds name themselves in the top-left corner as "jbg57 / rv.a81c4ef@08 / sc.7bd31fa+@42": kit MINOR, then
-- each module's short name (module.short, else the capitals of its title) and the first word of its TOC Version.
function lib:ShowBuilds()
	local parts = { "jbg" .. MINOR }
	for _, name in ipairs(self.logOrder or {}) do
		local module = self.logs[name] and self.logs[name].module
		if module and module.workingSection then
			local short = module.short or (module.title or name):gsub("[^%u]", ""):lower()
			local stamp = (C_AddOns.GetAddOnMetadata(name, "Version") or "?"):match("^(%S+)") or "?"
			table.insert(parts, short .. "." .. stamp)
		end
	end
	if not self.buildText then
		self.buildText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		self.buildText:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 4, -4)
	end
	self.buildText:SetText(table.concat(parts, " / "))
end

function lib:AddWorkingSection(module)
	if module.workingSection or not module.finished then return end
	local command = self.commands[module.command or ""]
	local hasCommands = false
	for _, entry in ipairs(command and command.entries or {}) do
		if entry.troubleshooting then hasCommands = true end
	end
	if not (hasCommands or self.logs[module.addon]) then return end
	module.workingSection = true
	self:ShowBuilds()
	if self.workingBuilt then return AddWorkingRows(module) end
	self.workingQueue = self.workingQueue or {}
	table.insert(self.workingQueue, module)
	if not self.workingWaiter then
		self.workingWaiter = true
		EventUtil.ContinueOnPlayerLogin(function()
			lib.workingBuilt = true
			for _, queued in ipairs(lib.workingQueue) do AddWorkingRows(queued) end
		end)
	end
end

function lib:FinishModule(module)
	local command = self.commands[module.command or ""]
	if command then
		local rows = {}
		for _, entry in ipairs(command.entries) do
			if entry.action ~= "" and not entry.troubleshooting then
				table.insert(rows, entry)
			end
		end
		if #rows > 0 then
			module.layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["Commands"],
				L["Type these in chat, or run them here. /%s help lists them all."]:format(command.name)))
			for _, entry in ipairs(rows) do
				-- The button's click handler gets the button, not typed words: run it as the bare command.
				module.layout:AddInitializer(CreateSettingsButtonInitializer(
					entry.label or ("/" .. command.name .. " " .. entry.action), entry.button or L["Run"], function() entry.run("") end,
					entry.note and (entry.description .. "\n" .. entry.note) or entry.description, false))
			end
		end
	end
	module.finished = true
	lib:AddWorkingSection(module)
	local links = ModuleLinks(module.addon)
	if #links > 0 then
		module.layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["Links"]))
		for _, link in ipairs(links) do
			module.layout:AddInitializer(CreateSettingsButtonInitializer(link[1], L["Copy link"], function()
				ShowLink(module.title .. ": " .. link[1], link[2])
			end, link[2], false))
		end
	end
end

-- Movable window with selectable text for copying out of the game. Blizzard parts only; Escape closes
-- it through UISpecialFrames.
-- refresh: replace the text of a window already open, without taking focus or reselecting.
function lib:ShowText(title, text, refresh)
	local frame = self.textFrame
	if not frame then
		frame = CreateFrame("Frame", "JigBoltgripToolkitTextFrame", UIParent, "BasicFrameTemplateWithInset")
		frame:SetSize(640, 420)
		frame:SetPoint("CENTER")
		frame:SetFrameStrata("DIALOG")
		frame:SetMovable(true)
		frame:EnableMouse(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", frame.StartMoving)
		frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
		frame.Title = frame.TitleText or frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		frame.Title:SetPoint("TOP", 0, -5)
		table.insert(UISpecialFrames, frame:GetName())
		frame.ScrollingEditBox = CreateFrame("Frame", nil, frame, "ScrollingEditBoxTemplate")
		frame.ScrollingEditBox:SetPoint("TOPLEFT", 14, -32)
		frame.ScrollingEditBox:SetPoint("BOTTOMRIGHT", -30, 12)
		frame.ScrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
		frame.ScrollBar:SetPoint("TOPLEFT", frame.ScrollingEditBox, "TOPRIGHT", 6, 0)
		frame.ScrollBar:SetPoint("BOTTOMLEFT", frame.ScrollingEditBox, "BOTTOMRIGHT", 6, 0)
		ScrollUtil.RegisterScrollBoxWithScrollBar(frame.ScrollingEditBox:GetScrollBox(), frame.ScrollBar)
		-- The text opens selected, so the box has focus and takes Escape; close then.
		frame.ScrollingEditBox:GetEditBox():HookScript("OnEscapePressed", function()
			frame:Hide()
		end)
		self.textFrame = frame
	end
	frame.log = nil -- set again by the log views; any other text is not a log
	frame.Title:SetText(title)
	frame.ScrollingEditBox:SetText(text)
	frame:Show()
	if refresh then return end
	local editBox = frame.ScrollingEditBox:GetEditBox()
	editBox:SetFocus()
	editBox:HighlightText()
end

function lib:IsTextShown()
	return self.textFrame and self.textFrame:IsShown()
end

-- One table of entries drives the chat help and the Commands rows (fields in docs/standards.md, "Options").
-- Troubleshooting entries show in chat help only. Full slash names, not aliases,
-- since clashes resolve unpredictably (ChatFrameUtil.lua imports SlashCmdList).
lib.commands = lib.commands or {}

-- Rows in Blizzard's own help shape, "/command <arguments> - What it does", with the command in the
-- device's color. help itself is not listed. The chat frame indents a wrapped line on its own.

local function AddEntries(rows, command, troubleshooting)
	local any = false
	for _, entry in ipairs(command.entries) do
		if (entry.troubleshooting or false) == troubleshooting and entry.action ~= "help" then
			if troubleshooting and not any then
				-- A section heading in the game's heading gold, as a tooltip's headings are; its rows sit one step in.
				table.insert(rows, NORMAL_FONT_COLOR:WrapTextInColorCode(L["Troubleshooting"]))
			end
			any = true
			local slash = "/" .. command.name .. (entry.action ~= "" and " " .. entry.action or "")
				.. (entry.usage and " " .. entry.usage or "")
			table.insert(rows, ("%s%s - %s"):format(troubleshooting and ALIGN or "", InDeviceColor(command.module, slash), entry.description))
		end
	end
end

function lib:PrintHelp(name)
	local command = self.commands[name]
	local rows = {}
	AddEntries(rows, command, false)
	AddEntries(rows, command, true)
	self:PrintBlock(L["%s commands:"]:format(command.title), rows)
end

-- A method, so slash handlers made by an older copy of this file run the newest code.
function lib:Dispatch(name, message)
	local command = self.commands[name]
	local action, arguments = strtrim(message or ""):match("^(%S*)%s*(.-)$")
	action = action:lower()
	for _, entry in ipairs(command.entries) do
		if entry.action == action then
			entry.run(arguments)
			return
		end
	end
	self:PrintHelp(name)
end

local function SetSlashHandler(name)
	local key = "BOLTGRIP_" .. name:upper()
	_G["SLASH_" .. key .. "1"] = "/" .. name
	SlashCmdList[key] = function(message)
		lib:Dispatch(name, message)
	end
end

-- Registers a module's command table; name is its slash word, e.g. "recipevacuum".
-- name is optional: without it the slash word is the module's command (NewModule). The kit adds the
-- "open the options" entry first and "help" last, unless the table has its own.
function lib:RegisterCommands(module, name, entries)
	if type(name) == "table" then
		name, entries = nil, name
	end
	name = (name or module.command or module.addon):lower()
	module.command = name
	local hasHelp, hasOptions = false, false
	for _, entry in ipairs(entries) do
		hasHelp = hasHelp or entry.action == "help"
		hasOptions = hasOptions or entry.action == ""
	end
	if not hasOptions then
		table.insert(entries, 1, { action = "", description = L["Open the options"], run = function()
			lib:OpenOptions(module)
		end })
	end
	if not hasHelp then
		table.insert(entries, { action = "help", description = L["List these commands"],
			note = L["Prints these commands in your chat window, with what each one does."], run = function()
			lib:PrintHelp(name)
		end })
	end
	self.commands[name] = { name = name, title = module.title, entries = entries, module = module }
	SetSlashHandler(name)
end

-- On upgrade, commands an older copy registered get this copy's handlers.
for name in pairs(lib.commands) do
	SetSlashHandler(name)
end

SLASH_BOLTGRIP1 = "/boltgrip"
SlashCmdList.BOLTGRIP = function(message)
	local name, rest = strtrim(message or ""):match("^(%S*)%s*(.-)$")
	if KitCommand(name:lower(), rest) then
		return
	end
	if lib.commands[name:lower()] then
		lib:Dispatch(name:lower(), rest)
		return
	end
	local rows = {}
	for _, module in ipairs(lib.modules) do
		if module.command then
			table.insert(rows, ("/%s - %s"):format(module.command, module.title))
		end
	end
	if #lib.logOrder > 0 then
		for _, row in ipairs(WORKING_BUILD_ROWS) do
			table.insert(rows, row)
		end
	end
	lib:PrintBlock(lib.title .. ": /boltgrip <module> <command>", rows)
end

-- Sharing between players who run the same module (docs/sharing.md). The library owns the transport, the
-- batch checks and the log lines; a module supplies its row shape. State is on the library table and every
-- behavior is a method on lib.shareMethods, so a newer copy's code runs for a share an older copy made.
local MAX_WIRE_NUMBER = 2 ^ 32 -- IDs, revisions and times on the wire are unsigned 32 bit
local SEND_LIMIT = 4000 -- encoded bytes per reply, about 16 AceComm chunks
local RECEIVE_LIMIT = 6000 -- larger replies are rejected before decoding
local EXPANDED_LIMIT = 65536 -- decompressed bytes accepted before CBOR decoding
local MAX_ROWS = 64
local REQUEST_TIMEOUT = 30
local REQUEST_RETRIES = 2 -- re-asks after a timeout
local MAX_COLLECTION_ID_LENGTH = 32
local COLLECTION_ID_RANGE = 1000000000 -- a collection ID is its creation time and a random number below this
local MAX_CACHED_REPLIES = 4
local REPLY_DELAY = 3 -- seconds a channel's probes are collected before one answer goes out
local WHISPER_ERROR_WINDOW = 10 -- seconds after a send in which the game's "no such player" line counts
local CLOCK_SKEW = 300 -- seconds a peer's clock may run ahead
local MAX_PREFIX_LENGTH = 16 -- the client's limit for an addon message prefix
-- Message kinds, the first letter of every message. The letters are the wire format.
local KIND = { HELLO = "H", ANSWER = "A", OFFER = "O", GET = "G", DATA = "D" }
local DISCOVERY_CHANNELS = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }
local SHARE_EVENTS = {
	"GROUP_ROSTER_UPDATE", "GROUP_JOINED", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE",
	"FRIENDLIST_UPDATE", "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_INFO_CHANGED",
	"BN_CONNECTED", "BN_DISCONNECTED", "CHAT_SERVER_RECONNECTED", "PLAYER_REGEN_ENABLED", "CHAT_MSG_SYSTEM",
}

lib.shares = lib.shares or {} -- by addon name
lib.shareList = lib.shareList or {} -- in creation order, for the one event frame
lib.shareMethods = lib.shareMethods or {}
local Share = lib.shareMethods

-- What a module's row checks are built from; every module checks rows the same way.
lib.wire = lib.wire or {}
local wire = lib.wire
wire.MAX = MAX_WIRE_NUMBER
wire.CLOCK_SKEW = CLOCK_SKEW

function wire.ID(value)
	return type(value) == "number" and value > 0 and value < MAX_WIRE_NUMBER and value == math.floor(value)
end

function wire.Number(value)
	return type(value) == "number" and value >= 0 and value < MAX_WIRE_NUMBER
end

function wire.Coordinate(value)
	return type(value) == "number" and value >= 0 and value <= 1
end

function wire.Flag(value)
	return type(value) == "boolean"
end

-- A time a peer reports: not further ahead than a skewed clock explains.
function wire.Time(value)
	return wire.ID(value) and value <= GetServerTime() + CLOCK_SKEW
end

-- A name to show: bounded, with no control characters or escape pipes.
function wire.Name(value, maxLength)
	return type(value) == "string" and #value <= maxLength and not value:find("[%c|]")
end

-- A field a row may leave out: absent, or passing the check.
function wire.Optional(check, value, ...)
	return value == nil or check(value, ...)
end

local function Trace(share, text, ...)
	if lib:IsLogging(share.module) then
		lib:Trace(share.module, "SHARE " .. text:format(...))
	end
end

local function NewCollectionID()
	return ("%d-%d"):format(GetServerTime(), math.random(COLLECTION_ID_RANGE))
end

local function Encode(rows)
	local bytes = C_EncodingUtil.SerializeCBOR(rows)
	local compressed = bytes and C_EncodingUtil.CompressString(bytes, Enum.CompressionMethod.Deflate)
	return compressed and C_EncodingUtil.EncodeBase64(compressed)
end

local function Decode(text)
	if #text > RECEIVE_LIMIT then return nil end
	local compressed = C_EncodingUtil.DecodeBase64(text)
	local bytes = compressed and C_EncodingUtil.DecompressString(compressed, Enum.CompressionMethod.Deflate)
	if not bytes or #bytes > EXPANDED_LIMIT then return nil end
	return C_EncodingUtil.DeserializeCBOR(bytes)
end

local function ParseHeader(message)
	local kind, id, number, rest = message:match("^(%u) (%d+%-%d+) (%d+)(.*)$")
	local revision = tonumber(number)
	if not revision or revision >= MAX_WIRE_NUMBER or #id > MAX_COLLECTION_ID_LENGTH then return nil end
	return kind, id, revision, rest
end

local function IsGroupMember(name)
	if UnitInParty(name) then return true end
	local index = UnitInRaid(name)
	return not issecretvalue(index) and index ~= nil
end

local function IsGuildMemberByName(name)
	return IsInGuild() and C_GuildInfo.MemberExistsByName(name)
end

-- spec: protocol (a number in both prefixes), kinds (set of row kinds this version reads), wire(entry, context)
-- -> row, validate(row) -> ok[, reason], merge(rows) -> whether anything changed, sending(), receiving(), and
-- optionally changed() after a request's rows were merged and prefix, a shorter name when the addon's is too long.
function lib:NewShare(module, spec)
	assert(type(spec.protocol) == "number" and type(spec.kinds) == "table" and type(spec.wire) == "function"
		and type(spec.validate) == "function" and type(spec.merge) == "function"
		and type(spec.sending) == "function" and type(spec.receiving) == "function",
		"NewShare: protocol, kinds, wire, validate, merge, sending and receiving are required (docs/sharing.md)")
	-- A module loaded again in the same Lua state replaces its share; the old one stops listening.
	local existing = self.shares[module.addon]
	if existing then
		existing:Connect(false)
		for index, share in ipairs(self.shareList) do
			if share == existing then table.remove(self.shareList, index) break end
		end
	end
	assert(spec.prefix == nil or type(spec.prefix) == "string", "NewShare: prefix must be a string")
	local prefix = (spec.prefix or module.addon) .. spec.protocol
	assert(#prefix + 1 <= MAX_PREFIX_LENGTH, ("NewShare: the prefix %sD is over %d characters"):format(prefix, MAX_PREFIX_LENGTH))
	local share = setmetatable({
		module = module, spec = spec, prefix = prefix, dataPrefix = prefix .. "D", testPrefix = prefix .. "T",
		revisions = {}, friends = {}, waiting = {}, replied = {}, cachedReplies = {}, whispered = {}, unreachable = {},
		replyTimers = {}, bnetPresence = {}, changedFriends = {}, inWorld = IsLoggedIn() == true,
	}, { __index = self.shareMethods })
	self.shares[module.addon] = share
	table.insert(self.shareList, share)
	self:ShareFrame()
	return share
end

-- One frame and one listener serve every module's share.
function lib:ShareFrame()
	if not self.shareFrame then
		self.shareFrame = CreateFrame("Frame")
		self.shareFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
		self.shareFrame:SetScript("OnEvent", function(_, event, ...)
			lib:ShareEvent(event, ...)
		end)
	end
	return self.shareFrame
end

-- The connection events are on while any share is connected.
function lib:UpdateShareEvents()
	local frame = self:ShareFrame()
	local wanted = false
	for _, share in ipairs(self.shareList) do
		wanted = wanted or share.enabled
	end
	for _, event in ipairs(SHARE_EVENTS) do
		if wanted then frame:RegisterEvent(event) else frame:UnregisterEvent(event) end
	end
end

function lib:ShareEvent(event, ...)
	-- The frame's events go into every sharing module's working-build log. An older copy's frame already counts the modules it
	-- watched (shareWatched, kept on the library), by a hook that stays; those are not counted again here.
	local watched = self.shareWatched
	for _, share in ipairs(self.shareList) do
		if not (watched and watched[share.module.addon]) then
			self:CountEvent(share.module, event)
		end
	end
	for _, share in ipairs(self.shareList) do
		share:OnEvent(event, ...)
	end
end

-- Loads the saved exchange (db.exchange: collection ID, revision counter, the revision received from each peer)
-- and the session's revision log. each(add) calls add(entry, context) for every entry of the module's own
-- found layer; an entry with no revision gets the next one.
function Share:Load(db, each)
	if not db.exchange then
		db.exchange = { id = NewCollectionID(), revision = 0, received = {} }
	end
	local exchange = db.exchange
	self.exchange = exchange
	wipe(self.revisions)
	local unrevised = {}
	each(function(entry, context)
		local row = { rev = entry.rev, entry = entry, context = context }
		table.insert(entry.rev and self.revisions or unrevised, row)
	end)
	table.sort(self.revisions, function(a, b) return a.rev < b.rev end)
	local highest = self.revisions[#self.revisions] and self.revisions[#self.revisions].rev or 0
	if highest > exchange.revision then
		-- A counter behind its revisions was reset: renumber under a new ID so peers resync.
		exchange.id, exchange.revision = NewCollectionID(), highest
		Trace(self, "counter was behind its revisions: new collection %s at %d", exchange.id, highest)
	end
	for _, row in ipairs(unrevised) do
		exchange.revision = exchange.revision + 1
		row.entry.rev, row.rev = exchange.revision, exchange.revision
		table.insert(self.revisions, row)
	end
	Trace(self, "loaded collection %s at revision %d, %d entries (%d newly numbered)", exchange.id, exchange.revision,
		#self.revisions, #unrevised)
end

-- A new or changed entry of the found layer: it gets the next revision and peers are told.
function Share:Mark(entry, context)
	local exchange = self.exchange
	exchange.revision = exchange.revision + 1
	entry.rev = exchange.revision
	table.insert(self.revisions, { rev = entry.rev, entry = entry, context = context })
	self:ScheduleOffer()
end

-- Rows after revision `after`, oldest first, up to `limit`; returns the rows and the revision they cover.
function Share:Since(after, limit)
	local rows, through = {}, after
	for _, row in ipairs(self.revisions) do
		-- Stale: the entry changed again and a newer row covers it.
		if row.rev > after and row.entry.rev == row.rev then
			if #rows >= limit then
				return rows, through
			end
			table.insert(rows, self.spec.wire(row.entry, row.context))
			through = row.rev
		end
	end
	return rows, self.exchange.revision
end

-- Checks a received batch and hands the valid rows of known kinds to the module. Returns whether anything
-- changed and how many rows were dropped as invalid; nil for a batch that is not a list of rows (nothing written).
function Share:Merge(rows, maxRows)
	local spec = self.spec
	if type(rows) ~= "table" then
		Trace(self, "batch rejected: not a list")
		return nil
	end
	if #rows > (maxRows or MAX_ROWS) then
		Trace(self, "batch rejected: %d rows, over the limit of %d", #rows, maxRows or MAX_ROWS)
		return nil
	end
	local count, skipped, unknown = 0, 0, 0
	local known = {}
	for index, row in pairs(rows) do
		if not wire.ID(index) or index > #rows or type(row) ~= "table" then
			Trace(self, "batch rejected: row %s is not in a list of tables", tostring(index))
			return nil
		end
		-- One bad row is dropped, not the batch: the same batch would be refused every time it is asked for.
		if spec.kinds[row.k] then
			local ok, reason = spec.validate(row)
			if ok then
				known[#known + 1] = row
			else
				skipped = skipped + 1
				Trace(self, "row %d rejected: %s %s", index, tostring(row.k), reason or "failed its checks")
			end
		else
			-- A kind a newer version added: skipped, not a reason to refuse the batch.
			unknown = unknown + 1
		end
		count = count + 1
	end
	if count ~= #rows then
		Trace(self, "batch rejected: the list has gaps")
		return nil
	end
	if unknown > 0 then Trace(self, "%d rows of kinds this version does not read were skipped", unknown) end
	local changed = spec.merge(known) and true or false
	Trace(self, "merged %d of %d rows, %d rejected: %s", #known, #rows, skipped, changed and "changed" or "nothing new")
	return changed, skipped
end

function Share:Wanted()
	return self.spec.sending() or self.spec.receiving()
end

function Share:IsTrusted(name)
	return self.friends[name] or IsGuildMemberByName(name) or IsGroupMember(name)
end

function Share:Ready()
	if not self.enabled then return false end
	if C_ChatInfo.InChatMessagingLockdown() then
		self.deferred = true
		return false
	end
	return true
end

-- A whisper to someone the game cannot reach is answered with the system line ERR_CHAT_PLAYER_NOT_FOUND_S;
-- it is only read, so a failed name is not whispered again until it has been offline.
function Share:WhisperSent(target)
	self.whispered[target] = GetTime()
end

function Share:Send(text, channel, target)
	if channel == "WHISPER" and self.unreachable[target] then
		Trace(self, "not sent to %s: the game could not reach them", target)
		return
	end
	Trace(self, "sent %s to %s%s", text, channel, target and (" " .. target) or "")
	if channel == "WHISPER" then
		self.comm:SendCommMessage(self.prefix, text, channel, target, "BULK", function(name) self:WhisperSent(name) end, target)
	else
		self.comm:SendCommMessage(self.prefix, text, channel, target, "BULK")
	end
end

function Share:SendData(text, target)
	if self.unreachable[target] then
		Trace(self, "not sent to %s: the game could not reach them", target)
		return
	end
	self.comm:SendCommMessage(self.dataPrefix, text, "WHISPER", target, "BULK", function(name) self:WhisperSent(name) end, target)
end

function Share:OnSystem(message)
	if not next(self.whispered) or issecretvalue(message) then return end
	if not lib.notFoundPattern then
		lib.notFoundPattern = "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%s", "(.+)") .. "$"
	end
	local now = GetTime()
	for target, sent in pairs(self.whispered) do
		if now - sent > WHISPER_ERROR_WINDOW then self.whispered[target] = nil end
	end
	local name = message:match(lib.notFoundPattern)
	local sent = name and self.whispered[name]
	if sent then
		self.whispered[name] = nil
		self.unreachable[name] = true
		Trace(self, "the game says %s is not playing: not whispered again until offline", name)
	end
end

-- A player who does not share offers revision 0, so no one asks for their finds.
function Share:Offer(kind)
	local exchange = self.exchange
	return ("%s %s %d"):format(kind, exchange.id, self.spec.sending() and exchange.revision or 0)
end

function Share:Broadcast(kind)
	local message = self:Offer(kind)
	local sent = 0
	if self.guild then self:Send(message, "GUILD") sent = sent + 1 end
	if self.home then self:Send(message, self.home) sent = sent + 1 end
	if self.instance then self:Send(message, "INSTANCE_CHAT") sent = sent + 1 end
	for name in pairs(self.friends) do
		if self.replied[name] and not IsGuildMemberByName(name) and not IsGroupMember(name) then
			self:Send(message, "WHISPER", name)
			sent = sent + 1
		end
	end
	Trace(self, "%s sent to %d channels or friends", message, sent)
end

function Share:ScheduleOffer()
	wipe(self.cachedReplies)
	if not self.enabled then return end
	-- A trainer or merchant visit finds entries over many frames; one offer goes out once they stop, as answers do (REPLY_DELAY).
	if self.offerTimer then self.offerTimer:Cancel() end
	self.offerTimer = C_Timer.NewTimer(REPLY_DELAY, function()
		self.offerTimer = nil
		if self:Ready() then self:Broadcast(KIND.OFFER) end
	end)
end

-- Builds the reply for one request, halving the row count until it fits SEND_LIMIT; cached per starting
-- revision, so a new entry clears it.
function Share:Reply(after)
	local cached = self.cachedReplies[after]
	if cached then return cached end
	local started = debugprofilestop()
	local limit = MAX_ROWS
	while true do
		local rows, through = self:Since(after, limit)
		local encoded = Encode(rows)
		if not encoded then return nil end
		if #encoded <= SEND_LIMIT or limit <= 1 then
			local message = ("%s %s %d %d %s"):format(KIND.DATA, self.exchange.id, after, through, encoded)
			-- A peer asking from every revision cannot grow the cache past a few replies.
			local held = 0
			for _ in pairs(self.cachedReplies) do held = held + 1 end
			if held >= MAX_CACHED_REPLIES then wipe(self.cachedReplies) end
			self.cachedReplies[after] = message
			lib:Time(self.module, "share reply", started)
			return message
		end
		limit = math.floor(limit / 2)
	end
end

function Share:FinishRequest()
	if self.active and self.active.timer then self.active.timer:Cancel() end
	self.active = nil
	if self.changedDirty then
		self.changedDirty = nil
		if self.spec.changed then self.spec.changed() end
	end
	self:NextPeer()
end

function Share:Ask(peer)
	Trace(self, "asked %s for entries %d to %d (%d tries left)", peer.sender, peer.after, peer.tip, peer.retries)
	if peer.timer then peer.timer:Cancel() end
	self:SendData(("%s %s %d"):format(KIND.GET, peer.id, peer.after), peer.sender)
	peer.timer = C_Timer.NewTimer(REQUEST_TIMEOUT, function()
		if self.active ~= peer then return end
		Trace(self, "no answer from %s", peer.sender)
		if peer.retries > 0 and self:Ready() and self:IsTrusted(peer.sender) then
			peer.retries = peer.retries - 1
			self:Ask(peer)
		else
			Trace(self, "gave up on %s", peer.sender)
			self:FinishRequest()
		end
	end)
end

-- One request at a time; the rest wait.
function Share:NextPeer()
	if self.active or not self:Ready() then return end
	for sender, peer in pairs(self.waiting) do
		self.waiting[sender] = nil
		peer.after = self.exchange.received[peer.id] or 0
		if peer.after < peer.tip and self:IsTrusted(sender) then
			self.active = peer
			self:Ask(peer)
			return
		end
		Trace(self, "dropped the wait for %s: nothing to ask or no longer trusted", sender)
	end
end

function Share:QueuePeer(sender, id, tip)
	-- Revision 0 is a peer that does not share (Offer); it says nothing about our cursor for it.
	if tip == 0 then return end
	local received = self.exchange.received
	-- Tip below what we saved: that collection was reset, restart from zero.
	if received[id] and tip < received[id] then
		Trace(self, "collection %s from %s restarted (tip %d, we had %d)", id, sender, tip, received[id])
		received[id] = 0
	end
	if (received[id] or 0) >= tip then return end
	local peer = self.active and self.active.sender == sender and self.active or self.waiting[sender]
	if peer and peer.id == id then
		peer.tip = math.max(peer.tip, tip)
	else
		self.waiting[sender] = { sender = sender, id = id, tip = tip, retries = REQUEST_RETRIES }
		Trace(self, "%s is ahead of us (collection %s at %d, we have %d): queued%s", sender, id, tip, received[id] or 0,
			self.active and ", waiting for the request in progress" or "")
	end
	self:NextPeer()
end

-- One answer per channel after a quiet moment, as another addon version check does (Loader.lua, GROUP_FORMED).
function Share:ScheduleChannelReply(channel)
	if self.replyTimers[channel] then
		self.replyTimers[channel]:Cancel()
		Trace(self, "another probe on %s: answer delayed again", channel)
	end
	self.replyTimers[channel] = C_Timer.NewTimer(REPLY_DELAY, function()
		self.replyTimers[channel] = nil
		if self:Ready() then
			self:Send(self:Offer(KIND.ANSWER), channel)
		end
	end)
end

function Share:OnProbe(message, channel, sender)
	if not self:Ready() or issecretvalue(sender) or issecretvalue(message) then return end
	if channel == "WHISPER" then
		if not self:IsTrusted(sender) then
			Trace(self, "probe from %s ignored: not a friend, guild member or group member", sender)
			return
		end
	elseif not DISCOVERY_CHANNELS[channel] then
		Trace(self, "probe from %s ignored: not on a channel we use (%s)", sender, tostring(channel))
		return
	end
	local kind, id, revision, rest = ParseHeader(message)
	if not kind or rest ~= "" then
		Trace(self, "probe from %s ignored: unreadable header", sender)
		return
	end
	if id == self.exchange.id then return end
	Trace(self, "heard %s from %s on %s: collection %s at %d", kind, sender, channel, id, revision)
	if kind == KIND.HELLO then
		if channel == "WHISPER" then
			-- Friends outside guild and group: answer the prober directly.
			local now = GetTime()
			if not self.replied[sender] or now - self.replied[sender] >= REPLY_DELAY then
				self.replied[sender] = now
				self:Send(self:Offer(KIND.ANSWER), "WHISPER", sender)
			else
				Trace(self, "no second answer to %s within %d seconds", sender, REPLY_DELAY)
			end
		else
			self:ScheduleChannelReply(channel)
		end
	elseif kind == KIND.ANSWER then
		self.replied[sender] = GetTime()
	elseif kind ~= KIND.OFFER then
		Trace(self, "probe from %s ignored: unknown kind %s", sender, kind)
		return
	end
	if self.spec.receiving() then
		self:QueuePeer(sender, id, revision)
	else
		Trace(self, "not taking entries from %s: receiving is off", sender)
	end
end

function Share:OnData(message, channel, sender)
	if not self:Ready() or issecretvalue(sender) or issecretvalue(message) then return end
	local started = debugprofilestop()
	self:HandleData(message, channel, sender)
	lib:Time(self.module, "share data", started)
end

function Share:HandleData(message, channel, sender)
	if channel ~= "WHISPER" then
		Trace(self, "data from %s ignored: not a whisper (%s)", sender, tostring(channel))
		return
	end
	if not self:IsTrusted(sender) then
		Trace(self, "data from %s ignored: not a friend, guild member or group member", sender)
		return
	end
	local kind, id, after, rest = ParseHeader(message)
	local exchange = self.exchange
	if kind == KIND.GET then
		if not self.spec.sending() or rest ~= "" or id ~= exchange.id or after >= exchange.revision then
			Trace(self, "request from %s ignored: sending off, malformed, another collection or nothing after %d", sender, after or -1)
			return
		end
		local reply = self:Reply(after)
		Trace(self, "%s asked for entries after %d: %s", sender, after, reply and ("sent " .. #reply .. " bytes") or "nothing to send")
		if reply then self:SendData(reply, sender) end
	elseif kind == KIND.DATA and self.spec.receiving() then
		-- Accept only the reply to our own request.
		local peer = self.active
		if not peer or peer.sender ~= sender or peer.id ~= id or peer.after ~= after then
			Trace(self, "data from %s ignored: not the reply to our request", sender)
			return
		end
		local through, encoded = rest:match("^ (%d+) (%S+)$")
		through = tonumber(through)
		if not through or through <= after or through >= MAX_WIRE_NUMBER then
			Trace(self, "data from %s ignored: unreadable header", sender)
			return
		end
		local ok, rows = pcall(Decode, encoded)
		local changed, skipped
		if ok and rows then changed, skipped = self:Merge(rows) end
		Trace(self, "received %d bytes from %s, entries %d to %d: %s", #encoded, sender, after, through,
			not (ok and rows) and "could not be read" or changed == nil and "rejected, nothing written"
			or ("%d rows, %d skipped, %s"):format(#rows, skipped, changed and "merged" or "nothing new"))
		if changed == nil then
			-- Asked for again it would fail the same way, so the cursor moves past it.
			exchange.received[id] = through
			self:FinishRequest()
			return
		end
		-- The sender may have found more since its probe.
		peer.tip = math.max(peer.tip, through)
		self.changedDirty = self.changedDirty or changed
		exchange.received[id] = through
		if through < peer.tip then
			peer.after, peer.retries = through, REQUEST_RETRIES
			self:Ask(peer)
		else
			self:FinishRequest()
		end
	else
		Trace(self, "data from %s ignored: kind %s while receiving is %s", sender, tostring(kind), self.spec.receiving() and "on" or "off")
	end
end

-- Event driven: broadcast once on joining each channel, whisper only newly online friends who won't get the group or guild probe.
function Share:RefreshChannels(force)
	local group = IsInGroup(LE_PARTY_CATEGORY_HOME) and
		(IsInRaid(LE_PARTY_CATEGORY_HOME) and "RAID" or "PARTY")
	local instanced = IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
	local inGuild = IsInGuild()
	local guildReady = inGuild and GetNumGuildMembers() > 0
	if inGuild and not guildReady then
		if not self.rosterRequested then
			self.rosterRequested = true
			C_GuildInfo.GuildRoster()
		end
	else
		self.rosterRequested = nil
	end
	local probe = self:Offer(KIND.HELLO)
	if guildReady and (not self.guild or force) then self:Send(probe, "GUILD") end
	if group and (group ~= self.home or force) then self:Send(probe, group) end
	if instanced and (not self.instance or force) then self:Send(probe, "INSTANCE_CHAT") end
	self.home, self.instance, self.guild = group, instanced, guildReady
end

-- BN_FRIEND_INFO_CHANGED also fires for zone or status changes, so reachable character names are compared before the roster is rebuilt.
local function BattleNetCharacters(index, online)
	local names = ""
	for j = 1, C_BattleNet.GetFriendNumGameAccounts(index) do
		local game = C_BattleNet.GetFriendGameAccountInfo(index, j)
		-- A whisper only goes to a character it can reach: online in this game, on this realm, same faction.
		if game and game.isOnline and game.isInCurrentRegion and game.clientProgram == BNET_CLIENT_WOW
			and game.wowProjectID == WOW_PROJECT_ID and game.characterName and game.characterName ~= ""
			and game.realmID == GetRealmID() and game.factionName == UnitFactionGroup("player") then
			local name = Ambiguate(game.characterName, "none")
			names = names .. "\n" .. name
			if online then online[name] = true end
		end
	end
	return names
end

function Share:RefreshFriends(force)
	local online = {}
	for i = 1, C_FriendList.GetNumFriends() do
		local info = C_FriendList.GetFriendInfoByIndex(i)
		if info and info.connected then online[Ambiguate(info.name, "none")] = true end
	end
	wipe(self.bnetPresence)
	for i = 1, BNGetNumFriends() do self.bnetPresence[i] = BattleNetCharacters(i, online) end
	-- A name the game could not reach is tried again once it has been offline.
	for name in pairs(self.unreachable) do
		if not online[name] then self.unreachable[name], self.whispered[name] = nil, nil end
	end
	local probe = self:Offer(KIND.HELLO)
	local previous = self.friends
	self.friends = online
	for name in pairs(online) do
		if (force or not previous[name]) and not IsGuildMemberByName(name) and not IsGroupMember(name) then
			self:Send(probe, "WHISPER", name)
		end
	end
end

function Share:Refresh()
	self.scheduled = nil
	if not self:Ready() then return end
	if self.channelDirty then self:RefreshChannels(self.forceChannels) end
	if not self.friendDirty then
		for index in pairs(self.changedFriends) do
			if self.bnetPresence[index] ~= BattleNetCharacters(index) then
				self.friendDirty = true
				break
			end
		end
	end
	wipe(self.changedFriends)
	if self.friendDirty then self:RefreshFriends(self.forceFriends) end
	self.channelDirty, self.friendDirty, self.forceChannels, self.forceFriends = nil, nil, nil, nil
end

function Share:ScheduleRefresh()
	if not self.scheduled then
		self.scheduled = true
		C_Timer.After(0, function() self:Refresh() end)
	end
end

function Share:OnEvent(event, index)
	if event == "PLAYER_ENTERING_WORLD" and not self.inWorld then
		self.inWorld = true
		if self:Wanted() then self:Connect(true) end
		return
	end
	if not self.enabled then return end
	if event == "CHAT_MSG_SYSTEM" then
		self:OnSystem(index)
		return
	end
	if event == "CHAT_SERVER_RECONNECTED" or (self.deferred and not C_ChatInfo.InChatMessagingLockdown()) then
		self.deferred = nil
		self.channelDirty, self.friendDirty, self.forceChannels, self.forceFriends = true, true, true, true
	elseif event == "GROUP_JOINED" then
		self.home, self.instance = nil, nil
		self.channelDirty = true
	elseif event == "GROUP_ROSTER_UPDATE" or event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
		self.channelDirty = true
	elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
		return
	elseif event == "BN_FRIEND_INFO_CHANGED" and index then
		self.changedFriends[index] = true
	else
		self.friendDirty = true
	end
	self:ScheduleRefresh()
end

-- After a sharing setting changes: the connection follows whether either direction is wanted, a player who
-- starts sharing advertises at once, and one who stops receiving drops pending requests.
function Share:Update()
	self:Connect(self:Wanted())
	if not self.enabled then return end
	if not self.spec.receiving() then
		if self.active and self.active.timer then self.active.timer:Cancel() end
		self.active = nil
		wipe(self.waiting)
	end
	self:ScheduleOffer()
end

function Share:Connect(value)
	if not self.inWorld or (self.enabled or false) == value then return end
	self.enabled = value
	Trace(self, "%s on prefixes %s and %s", value and "connected" or "disconnected", self.prefix, self.dataPrefix)
	lib:UpdateShareEvents()
	if value then
		if not self.comm then
			self.comm = {}
			LibStub("AceComm-3.0"):Embed(self.comm)
		end
		self.comm:RegisterComm(self.prefix, function(_, message, channel, sender) self:OnProbe(message, channel, sender) end)
		self.comm:RegisterComm(self.dataPrefix, function(_, message, channel, sender) self:OnData(message, channel, sender) end)
		self.channelDirty, self.friendDirty, self.forceChannels, self.forceFriends = true, true, true, true
		C_FriendList.ShowFriends()
		self:ScheduleRefresh()
	else
		self.comm:UnregisterComm(self.prefix)
		self.comm:UnregisterComm(self.dataPrefix)
		if self.active and self.active.timer then self.active.timer:Cancel() end
		self.active = nil
		wipe(self.waiting)
		for channel, timer in pairs(self.replyTimers) do
			timer:Cancel()
			self.replyTimers[channel] = nil
		end
		wipe(self.friends)
		wipe(self.whispered)
		wipe(self.replied)
		wipe(self.bnetPresence)
		wipe(self.changedFriends)
		wipe(self.cachedReplies)
		self.home, self.instance, self.guild, self.deferred, self.rosterRequested, self.changedDirty = nil, nil, nil, nil, nil, nil
	end
end

-- One-account check: every reply is built by the real code, checked against the limits, decoded, handed to
-- merge(rows) (the module's, onto a scratch copy of its data) and whispered back over a test prefix.
-- summary() adds the module's own line. Not covered: choosing who to share with, and the probe exchange.
local TEST_TIMEOUT = 60

function Share:SelfTest(report, merge, summary)
	local exchange = self.exchange
	local messages, after, rowsSent, largest = {}, 0, 0, 0
	wipe(self.cachedReplies)
	while after < exchange.revision do
		local message = self:Reply(after)
		if not message then return report("FAIL: the reply after revision " .. after .. " could not be encoded") end
		local kind, id, replyAfter, rest = ParseHeader(message)
		local through, encoded = (rest or ""):match("^ (%d+) (%S+)$")
		through = tonumber(through)
		if kind ~= KIND.DATA or id ~= exchange.id or replyAfter ~= after or not through or through <= after then
			return report("FAIL: the reply after revision " .. after .. " has a header the receiver would reject")
		end
		if #encoded > SEND_LIMIT then
			report(("WARN: a reply is %d bytes, over the %d send limit (one row too large to split)"):format(#encoded, SEND_LIMIT))
		end
		local ok, rows = pcall(Decode, encoded)
		if not (ok and rows) then return report("FAIL: the reply after revision " .. after .. " does not decode") end
		local merged, changed, skipped = pcall(merge, rows)
		if not merged or changed == nil or skipped > 0 then
			return report("FAIL: the receiver's validation rejects the reply after revision " .. after)
		end
		messages[#messages + 1], rowsSent, largest = message, rowsSent + #rows, math.max(largest, #message)
		after = through
	end
	wipe(self.cachedReplies)
	report(("Encode and decode: %d replies, %d rows, largest %d bytes%s"):format(#messages, rowsSent, largest,
		summary and ("; " .. summary()) or ""))
	if #messages == 0 then return report("Nothing to send: nothing recorded yet") end
	if not self.comm then
		self.comm = {}
		LibStub("AceComm-3.0"):Embed(self.comm)
	end
	local comm, received, started = self.comm, 0, GetTime()
	local timeout = C_Timer.NewTimer(TEST_TIMEOUT, function()
		comm:UnregisterComm(self.testPrefix)
		report(("FAIL: %d of %d replies came back within %d s (the game may not deliver a whisper to yourself)"):format(
			received, #messages, TEST_TIMEOUT))
	end)
	comm:RegisterComm(self.testPrefix, function(_, message, channel)
		received = received + 1
		if channel ~= "WHISPER" or message ~= messages[received] then
			timeout:Cancel()
			comm:UnregisterComm(self.testPrefix)
			return report("FAIL: reply " .. received .. " arrived changed")
		end
		if received == #messages then
			timeout:Cancel()
			comm:UnregisterComm(self.testPrefix)
			report(("Through the game and back: %d of %d replies arrived unchanged in %.1f s"):format(
				received, #messages, GetTime() - started))
		end
	end)
	local me = UnitName("player")
	for _, message in ipairs(messages) do
		comm:SendCommMessage(self.testPrefix, message, "WHISPER", me, "BULK")
	end
	report(("Whispering %d replies to %s; the result follows"):format(#messages, me))
end
