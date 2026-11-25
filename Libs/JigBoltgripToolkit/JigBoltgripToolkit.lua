-- Shared home for Jig Boltgrip's Toolkit modules. Each module embeds this file; LibStub keeps the newest.
-- One Settings category for the toolkit, one subcategory per installed module.
local MAJOR, MINOR = "JigBoltgripToolkit-1.0", 30
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
	return
end

lib.title = "Jig Boltgrip's Toolkit"
lib.modules = lib.modules or {}

-- Header for modules' key bindings: a module's Bindings.xml uses category="BINDING_HEADER_JIGBOLTGRIPTOOLKIT".
BINDING_HEADER_JIGBOLTGRIPTOOLKIT = lib.title

-- Settings pages use only Blizzard's vertical-layout initializers, so they look native and the Settings
-- search finds them (it searches vertical layouts only: Blizzard_SettingsPanel.lua). Button rows pass
-- false for search tags, as Blizzard does.
function lib:GetCategory()
	if not self.category then
		self.category, self.layout = Settings.RegisterVerticalLayoutCategory(self.title)
		self.layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(ADDONS or "AddOns"))
		Settings.RegisterAddOnCategory(self.category)
	end
	return self.category, self.layout
end

local function ShowLink(title, url)
	lib:ShowText(title, url)
end

-- Links from standard TOC fields (X-Website as other addons, X-Curse-Project-ID
-- as Can I Mog It and another addon). LaunchURL and CopyToClipboard are restricted, so a button opens the
-- copy window with the address selected, as another addon Discord link does.
local function ModuleLinks(addonName)
	local links = {}
	local website = C_AddOns.GetAddOnMetadata(addonName, "X-Website")
	if website then table.insert(links, { "Website", website }) end
	local curse = C_AddOns.GetAddOnMetadata(addonName, "X-Curse-Project-ID")
	if curse then table.insert(links, { "CurseForge", "https://www.curseforge.com/projects/" .. curse }) end
	return links
end

-- Chat. Everything a toolkit addon prints goes through lib:Say, lib:Print or lib:PrintBlock, so the
-- family reads as one (docs/standards.md, "Voice").
local MARK = "|TInterface\\WorldMap\\GEAR_64GREY:0|t" -- the world map's gear, at the line's height
-- A blank the gear's size (Blizzard's inline spacer), so rows under a marked line start where its text
-- does, as a tooltip's lines sit under its heading.
local ALIGN = "|TInterface\\Common\\spacer:0|t "
local PREFIX = "Boltgrip's"
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

-- A voiced line: the mark, "Boltgrip's", the device's name and the noise it makes, then its own report.
-- noise is a short present-tense phrase with no end mark ("whirs and rattles"); the library adds the
-- period. report is one or more robot-speak beats, each ending in "!" ("Intake complete! 2 recipes from X!").
function lib:Say(module, noise, report)
	assert(type(noise) == "string" and noise ~= "" and type(report) == "string" and report ~= "",
		("%s: a voiced line needs a noise and a report (docs/standards.md, \"Voice\")"):format(tostring(module.title)))
	AddLine(("%s %s %s %s. %s"):format(MARK, PREFIX, DeviceName(module), noise, report))
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

-- Registers a module by addon folder name; returns its settings category and layout. Call
-- lib:FinishModule(module) after adding the module's rows. class is the class whose color the
-- device's name takes in chat, a key of RAID_CLASS_COLORS such as "DRUID"; without one the name is
-- the line color.
function lib:RegisterModule(addonName, class)
	for _, existing in ipairs(self.modules) do
		if existing.addon == addonName then
			existing.class = class or existing.class
			return existing
		end
	end
	local title = C_AddOns.GetAddOnMetadata(addonName, "Title")
	local notes = C_AddOns.GetAddOnMetadata(addonName, "Notes")
	local parent, parentLayout = self:GetCategory()
	local category, layout = Settings.RegisterVerticalLayoutSubcategory(parent, title)
	local module = { addon = addonName, title = title, notes = notes, category = category, layout = layout, class = class }
	table.insert(self.modules, module)
	parentLayout:AddInitializer(CreateSettingsButtonInitializer(title, OPEN or "Open", function()
		Settings.OpenToCategory(category:GetID())
	end, notes, false))
	return module
end

-- Custom options rows (notes, cards) are built in Lua on Blizzard's BackdropTemplate, which the options
-- list never uses itself, so they pool apart from Blizzard's rows. No XML of our own: a named template
-- in an embedded library is defined once per addon that embeds it, and the second definition warns.
local ROW_TEMPLATE = "BackdropTemplate"
local NOTE_LEFT = 37 -- where Blizzard's row labels start (SettingsAddOnDisabledLabelTemplate)

-- Shows one kind of custom row on a pooled frame and hides the other.
local function UseRow(frame, kind)
	if frame.Note then frame.Note:SetShown(kind == "note") end
	for _, card in ipairs(frame.cards or {}) do card:SetShown(kind == "cards") end
end

-- A note under an options row: gray, wrapped, in plain words, for what a hover tooltip alone would hide.
-- The row's height is measured from the text.
local NOTE_WIDTH = 520    -- room for a note beside the options list's left margin
local NOTE_GAP = 8        -- space below a note, before the next row
local measure

function lib:AddNote(layout, text)
	local initializer = Settings.CreateElementInitializer(ROW_TEMPLATE, { text = text })
	initializer.GetExtent = function()
		if not measure then
			measure = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			measure:Hide()
		end
		measure:SetWidth(NOTE_WIDTH)
		measure:SetText(text)
		return math.ceil(measure:GetStringHeight()) + NOTE_GAP
	end
	initializer.InitFrame = function(_, frame)
		if not frame.Note then
			frame.Note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			frame.Note:SetPoint("TOPLEFT", NOTE_LEFT, 0)
			frame.Note:SetJustifyH("LEFT")
			frame.Note:SetJustifyV("TOP")
		end
		UseRow(frame, "note")
		frame.Note:SetWidth(NOTE_WIDTH)
		frame.Note:SetText(text)
		frame.Note:SetTextColor(GRAY_FONT_COLOR:GetRGB())
	end
	layout:AddInitializer(initializer)
	return initializer
end

-- Working builds. A module calls these from its own debug-only block, so a release never does; the library
-- file itself is the same in every build. One listener and one record serve every module.

-- Shows Lua errors and reports actions the client blocked, so a fault while developing is seen.
function lib:EnableWorkingBuild()
	C_CVar.SetCVar("scriptErrors", "1")
	if self.blockedListener then
		return
	end
	self.blockedListener = CreateFrame("Frame")
	self.blockedListener:RegisterEvent("ADDON_ACTION_BLOCKED")
	self.blockedListener:RegisterEvent("ADDON_ACTION_FORBIDDEN")
	self.blockedListener:SetScript("OnEvent", function(_, event, addon, action)
		local line = ("%s: %s, %s"):format(event, tostring(addon), tostring(action))
		lib:Print(line)
		-- Shared context: every log keeps it, with the call stack, to read after a reload.
		lib:LogAll(line)
		lib:LogAll(debugstack(2, 12, 0))
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

-- Working-build log: per module, kept in the module's own saved table (the library has none) as
-- saved.devLog (lines), saved.devLogRun (where the current run starts) and saved.watch (watch left on).
-- Lines are timestamped so a long watch reads as a timeline; the last LOG_LINES are kept (owner,
-- 2026-11-25, for an always-on log: 20,000 lines, about 1.1 MB and 17 ms per load, working builds only).
-- Past the cap the oldest LOG_TRIM go at once, so a full log is not shifted on every new line and never
-- holds more than LOG_LINES.
local LOG_LINES, LOG_TRIM = 20000, 1000
lib.LOG_LINES, lib.LOG_TRIM = LOG_LINES, LOG_TRIM
lib.logs = lib.logs or {}
lib.logOrder = lib.logOrder or {} -- addon names in the order their logs started, for /boltgrip log

-- Shared context for every log that is logging (blocked actions, Lua errors, zone changes); a paused
-- log takes none (Astra review).
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
-- IDs first (the map and the explored area IDs at the player's spot, as both addons place things), then the
-- names for a person reading it.
local function ZoneLine()
	local mapID = C_Map.GetBestMapForUnit("player")
	local info = mapID and C_Map.GetMapInfo(mapID)
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	local areas = position and C_MapExplorationInfo.GetExploredAreaIDsAtPosition(mapID, position)
	return ("zone %s areas %s | %s | %s"):format(tostring(mapID), areas and table.concat(areas, ",") or "-",
		info and info.name or "?", GetSubZoneText() or "")
end
local CONTEXT_EVENTS = { ZONE_CHANGED_NEW_AREA = true, ZONE_CHANGED = true, ZONE_CHANGED_INDOORS = true }

local function UpdateWatchEvents()
	local frame = lib.watchFrame
	if not frame then
		frame = CreateFrame("Frame")
		lib.watchFrame = frame
		frame:SetScript("OnEvent", function(_, event, ...)
			if CONTEXT_EVENTS[event] then
				for _, addon in ipairs(lib.logOrder) do
					local log = lib.logs[addon]
					if log.watching then lib:Log(log.module, ZoneLine()) end
				end
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

-- At logout each log gets the session's timings, as one dated block.
local function WriteTimings()
	for _, log in pairs(lib.logs) do
		local lines = lib:TimingLines(log.module)
		if #lines > 0 then
			local version, build = GetBuildInfo()
			lib:Log(log.module, "")
			lib:Log(log.module, ("%s PERF session on %s (%s), %s level %d"):format(date("%Y-%m-%d %H:%M:%S"), version,
				build, UnitName("player") or UNKNOWN, UnitLevel("player") or 0), true)
			for _, line in ipairs(lines) do
				lib:Log(log.module, line)
			end
		end
	end
end

-- Starts the module's log once its saved table is loaded; resumes a watch left on.
function lib:StartLog(module, saved, handlers)
	local log = self.logs[module.addon]
	if not log then
		log = {}
		self.logs[module.addon] = log
		self.logOrder[#self.logOrder + 1] = module.addon
	end
	log.module, log.saved, log.handlers = module, saved, handlers or {}
	saved.devLog = saved.devLog or {}
	if not self.logWriter then
		self.logWriter = CreateFrame("Frame")
		self.logWriter:RegisterEvent("PLAYER_LOGOUT")
		self.logWriter:SetScript("OnEvent", WriteTimings)
	end
	-- Session header: one line per load, so each log reads on its own.
	local version, build = GetBuildInfo()
	self:Log(module, "")
	self:Log(module, ("%s session: client %s (%s) | addon %s | %s, level %d | %s"):format(date("%Y-%m-%d %H:%M:%S"),
		version, build, C_AddOns.GetAddOnMetadata(module.addon, "Version") or "?", UnitName("player") or "?",
		UnitLevel("player") or 0, ZoneLine()), true)
	-- A working build logs from the start, always (owner, 2026-11-25: "don't I want an always on debug mode
	-- while testing?"); /boltgrip watch off pauses it and is remembered.
	if saved.watch ~= false and not log.watching then
		self:SetWatch(module, true, true)
	end
end

-- A line for the module's log while it is logging; nothing otherwise, and nothing in a release, where no
-- log is started. For events worth reading back but not worth a chat line (sharing, timers).
function lib:Trace(module, line)
	local log = self.logs[module.addon]
	if log and log.watching then
		self:Log(module, line)
	end
end

-- Appends one line; a dated line (or an empty one) is kept as it is.
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
	-- An open log window follows, once per frame however many lines arrive, keeping the reader's place.
	if self:IsTextShown() and (self.textFrame.log == log or self.textFrame.log == "all") and not self.refreshQueued then
		self.refreshQueued = true
		C_Timer.After(0, function()
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

-- /boltgrip watch on|off and /boltgrip log [all|clear]: one switch and one viewer for every module that
-- started a log (owner, 2026-11-25: kit commands only). Release builds start no logs, so these do nothing
-- there and are not listed.
local WORKING_BUILD_ROWS = {
	"/boltgrip watch on|off - Pause or resume logging what each addon sees (on by default)",
	"/boltgrip log [all|clear] - Show every addon's log; \"all\" shows everything kept, \"clear\" empties them",
}

local function KitCommand(name, word)
	if #lib.logOrder == 0 or (name ~= "watch" and name ~= "log") then
		return false
	end
	word = (word or ""):lower()
	if name == "watch" then
		local anyOn, titles = false, {}
		for _, addon in ipairs(lib.logOrder) do
			anyOn = anyOn or lib.logs[addon].watching ~= nil
		end
		local on = word == "on" or (word == "" and not anyOn)
		for _, addon in ipairs(lib.logOrder) do
			local module = lib.logs[addon].module
			lib:SetWatch(module, on, true)
			titles[#titles + 1] = module.title
		end
		lib:Print(("Watch %s: %s."):format(on and "enabled" or "disabled", table.concat(titles, ", ")))
	elseif word == "clear" then
		for _, addon in ipairs(lib.logOrder) do
			local saved = lib.logs[addon].saved
			saved.devLog, saved.devLogRun = {}, nil
		end
		lib:Print("Logs purged!")
	else
		for _, addon in ipairs(lib.logOrder) do
			lib.logs[addon].viewStart = nil
		end
		lib:ShowAllLogs(word == "all")
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

-- Options pages. A module describes its page as data and lib:BuildOptions builds it from Blizzard's own
-- controls, so every toolkit page has the same headings, labels, notes and spacing (docs/standards.md,
-- "Options"). The data shape follows AceConfig's options tables; the drawing is Blizzard's.
--
--   lib:BuildOptions(module, db, sections), sections = { { heading = text, rows = { row, ... } }, ... }
--   Every row may have a note: gray text under it, for what the one-sentence tooltip cannot hold.
--   { kind = "checkbox", key, label, tooltip, default, onChange, under = key of a checkbox it is indented under }
--   { kind = "dropdown", key, label, tooltip, default, values = { { value, label }, ... }, onChange }
--   { kind = "cards", key, label, default, values = { { value, label, icon, text }, ... }, onChange }
--   { kind = "keybinding", binding = the Bindings.xml name }
-- Saved values live in db[key]; the setting is named "<addon>_<key>". Returns the settings by key.

-- Cards: a choice shown as a row of cards, laid out like the game's ruleset choice.
local CARD_WIDTH, CARD_HEIGHT, CARD_GAP = 184, 198, 12
local CARDS_ROW_HEIGHT = 214 -- the cards plus the space below them
local CARD_LEFT = 37 -- where Blizzard's own controls start
local CARD_TITLE_TOP, CARD_ICON_TOP, CARD_ICON_SIZE = -14, -40, 48
local CARD_TEXT_TOP, CARD_TEXT_INSET = -100, 12
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- Blizzard's round portrait mask
-- Spell icons carry a dark border; it is cut away before the round mask, as Blizzard does for round icons.
local ICON_EDGE = 0.08
local UNCHOSEN_ALPHA = 0.55 -- the cards not chosen are dimmed
local CHOSEN_BACKGROUND = { r = 0.16, g = 0.13, b = 0.05 } -- a warm dark behind the gold border

local function CreateCard(parent, index, choice, setting)
	local card = CreateFrame("Button", nil, parent, "TooltipBackdropTemplate")
	card:SetSize(CARD_WIDTH, CARD_HEIGHT)
	card:SetPoint("TOPLEFT", CARD_LEFT + (index - 1) * (CARD_WIDTH + CARD_GAP), 0)
	card.value = choice[1]
	local title = card:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, CARD_TITLE_TOP)
	title:SetText(choice[2])
	local icon = card:CreateTexture(nil, "ARTWORK")
	icon:SetSize(CARD_ICON_SIZE, CARD_ICON_SIZE)
	icon:SetPoint("TOP", 0, CARD_ICON_TOP)
	icon:SetTexture(choice[3])
	icon:SetTexCoord(ICON_EDGE, 1 - ICON_EDGE, ICON_EDGE, 1 - ICON_EDGE)
	local mask = card:CreateMaskTexture()
	mask:SetAllPoints(icon)
	mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	icon:AddMaskTexture(mask)
	local text = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOP", 0, CARD_TEXT_TOP)
	text:SetWidth(CARD_WIDTH - 2 * CARD_TEXT_INSET) -- a set width and no line limit, so the text wraps
	text:SetWordWrap(true)
	text:SetMaxLines(0)
	text:SetJustifyH("CENTER")
	text:SetJustifyV("TOP")
	text:SetText(choice[4])
	card.Title, card.Icon = title, icon
	card:SetScript("OnEnter", function() card:SetAlpha(1) end)
	card:SetScript("OnLeave", function() card:SetAlpha(card.chosen and 1 or UNCHOSEN_ALPHA) end)
	card:SetScript("OnClick", function() setting:SetValue(card.value) end)
	return card
end

local function ShowChoice(frame, value)
	for _, card in ipairs(frame.cards) do
		local chosen = card.value == value
		local background = chosen and CHOSEN_BACKGROUND or TOOLTIP_DEFAULT_BACKGROUND_COLOR
		card:SetBackdropBorderColor((chosen and NORMAL_FONT_COLOR or TOOLTIP_DEFAULT_COLOR):GetRGB())
		card:SetBackdropColor(background.r, background.g, background.b)
		card.Title:SetTextColor((chosen and NORMAL_FONT_COLOR or DISABLED_FONT_COLOR):GetRGB())
		card.Icon:SetDesaturated(not chosen)
		card.chosen = chosen
		card:SetAlpha((chosen or card:IsMouseOver()) and 1 or UNCHOSEN_ALPHA)
	end
end

local function AddCards(layout, setting, values)
	local initializer = Settings.CreateElementInitializer(ROW_TEMPLATE, {})
	local shown -- the list's frame for this row while it is on screen
	initializer.GetExtent = function()
		return CARDS_ROW_HEIGHT
	end
	initializer.InitFrame = function(_, frame)
		-- A pooled frame may already hold another card row's cards; they are made for this one.
		if frame.cardValues ~= values then
			for _, card in ipairs(frame.cards or {}) do card:Hide() end
			frame.cards, frame.cardValues = nil, values
		end
		if not frame.cards then
			frame.cards = {}
			for index, choice in ipairs(values) do
				frame.cards[index] = CreateCard(frame, index, choice, setting)
			end
		end
		UseRow(frame, "cards")
		shown = frame
		ShowChoice(frame, setting:GetValue())
	end
	initializer.Resetter = function()
		shown = nil
	end
	layout:AddInitializer(initializer)
	return function(value)
		if shown then ShowChoice(shown, value) end
	end
end

local VAR_TYPES = { boolean = "Boolean", number = "Number", string = "String" }

-- Every module's page has one order (owner, 2026-11-25: "The order needs to be aligned between both addons"):
-- the sources cards, then the module's own features, then sections Blizzard names (Key Binding, Combat,
-- Sound) in Blizzard's order; the kit's Commands and Links follow (FinishModule). Each section says its place.
local SECTION_PLACES = { sources = 1, features = 2, blizzard = 3 }

-- Blizzard's own sections in the order its Settings pages show them; one not listed comes after these.
local function BlizzardOrder()
	local order = {}
	for index, heading in ipairs({ KEY_BINDING, COMBAT, SOUND }) do order[heading] = index end
	return setmetatable(order, { __index = function() return 99 end })
end

local function OrderedSections(sections)
	local ordered = {}
	for index, section in ipairs(sections) do
		local rank = assert(SECTION_PLACES[section.place], ("section %q needs a place: sources, features or blizzard"):format(
			tostring(section.heading)))
		-- A sources section is exactly one row of the kit's cards, plus any rows under it (sharing).
		if section.place == "sources" then
			assert(section.rows[1] and section.rows[1].kind == "cards",
				("section %q: the cards come first"):format(section.heading))
			local cards = 0
			for _, row in ipairs(section.rows) do
				if row.kind == "cards" then
					assert(lib.sourceCardSets[row.values], ("section %q: cards must come from SourceCards"):format(section.heading))
					cards = cards + 1
				end
			end
			assert(cards == 1, ("section %q needs exactly one row of cards"):format(section.heading))
		end
		ordered[#ordered + 1] = { section = section, rank = rank, index = index,
			blizzard = section.place == "blizzard" and BlizzardOrder()[section.heading] or 0 }
	end
	table.sort(ordered, function(left, right)
		if left.rank ~= right.rank then return left.rank < right.rank end
		if left.blizzard ~= right.blizzard then return left.blizzard < right.blizzard end
		return left.index < right.index
	end)
	for index, entry in ipairs(ordered) do ordered[index] = entry.section end
	return ordered
end

-- Sources cards, the same in every module (owner, 2026-11-25: "These words don't match how recipe vacuum
-- works which feels like a miss"): the levels, names, icons, range openings and each card's sentence are
-- the kit's; the module names only the game thing it tracks.
--   spec.what      what the module tracks, in game terms ("recipes", "the Fishing skill each zone needs")
--   spec.friends   true when the module shares with party, guild and friends; otherwise no Friends card
--   spec.public    what Public adds ("recipes people link in chat"); nil leaves out the Public card
--   spec.openings  false leaves out the range openings (owner, 2026-11-25, Tackletron: "Game terms, no range opening")
lib.SOURCE_LEVEL = { SELF = 1, FRIENDS = 2, PUBLIC = 3 }
local SOURCE_CARDS = {
	{ name = "Self Found", icon = "Interface\\Icons\\INV_Misc_Spyglass_03", opening = "Short range.",
		text = function(spec)
			return ("Tracks only %s you see for yourself."):format(spec.what)
		end },
	{ name = "Friends", icon = "Interface\\Icons\\INV_Misc_GroupLooking", opening = "Medium range.",
		text = function(spec) return spec.friends and "Also tracks what your party, guild and friends find." end },
	{ name = "Public", icon = "Interface\\Icons\\Ability_Warrior_BattleShout", opening = "Long range.",
		text = function(spec) return spec.public and ("Also tracks %s."):format(spec.public) end },
}

-- Cards from here are marked, so BuildOptions can refuse cards built by hand (owner, 2026-11-25: rules baked in).
lib.sourceCardSets = lib.sourceCardSets or setmetatable({}, { __mode = "k" })

function lib:SourceCards(spec)
	assert(type(spec.what) == "string", "SourceCards needs spec.what, the game thing the module tracks")
	local cards = {}
	self.sourceCardSets[cards] = true
	for level, card in ipairs(SOURCE_CARDS) do
		local text = card.text(spec)
		if text then
			cards[#cards + 1] = { level, card.name, card.icon, spec.openings == false and text or (card.opening .. " " .. text) }
		end
	end
	return cards
end

function lib:BuildOptions(module, db, sections)
	local category, layout, settings, rows = module.category, module.layout, {}, {}
	for _, section in ipairs(OrderedSections(sections)) do
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(section.heading))
		for _, row in ipairs(section.rows) do
			local setting, initializer, showChoice
			if row.key then
				setting = Settings.RegisterAddOnSetting(category, module.addon .. "_" .. row.key, row.key, db,
					Settings.VarType[VAR_TYPES[type(row.default)]], row.label, row.default)
				settings[row.key] = setting
			end
			if row.kind == "checkbox" then
				initializer = Settings.CreateCheckbox(category, setting, row.tooltip)
				local parent = row.under and rows[row.under]
				if parent then
					initializer:SetParentInitializer(parent, function() return settings[row.under]:GetValue() end)
				end
			elseif row.kind == "dropdown" then
				initializer = Settings.CreateDropdown(category, setting, function()
					local container = Settings.CreateControlTextContainer()
					for _, choice in ipairs(row.values) do
						container:Add(choice[1], choice[2])
					end
					return container:GetData()
				end, row.tooltip)
			elseif row.kind == "cards" then
				showChoice = AddCards(layout, setting, row.values)
			elseif row.kind == "keybinding" then
				-- Blizzard's own key binding row, as the Controls page shows the Interact Key (Controls.lua).
				local bindingIndex = C_KeyBindings.GetBindingIndex(row.binding)
				if bindingIndex then
					initializer = CreateKeybindingEntryInitializer(bindingIndex, true)
					initializer:AddSearchTags(GetBindingName(row.binding))
					layout:AddInitializer(initializer)
				end
			end
			if setting and (row.onChange or showChoice) then
				setting:SetValueChangedCallback(function(_, value)
					if showChoice then showChoice(value) end
					if row.onChange then row.onChange(value) end
				end)
			end
			if row.key then rows[row.key] = initializer end
			if row.note then self:AddNote(layout, row.note) end
		end
	end
	return settings
end

-- Closing sections every module page shares: commands and links.
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
			module.layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Commands",
				"Type these in chat, or run them here. /" .. command.name .. " help lists them all."))
			for _, entry in ipairs(rows) do
				module.layout:AddInitializer(CreateSettingsButtonInitializer(
					"/" .. command.name .. " " .. entry.action, "Run", entry.run, entry.description, false))
				-- entry.note says what the command does in a sentence or two; the description is the short form.
				self:AddNote(module.layout, entry.note or entry.description)
			end
		end
	end
	local links = ModuleLinks(module.addon)
	if #links > 0 then
		module.layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Links"))
		for _, link in ipairs(links) do
			module.layout:AddInitializer(CreateSettingsButtonInitializer(link[1], "Copy link", function()
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
	frame.log = nil -- set again by the log views; any other text is not a log (Astra review)
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

-- Each module registers a table of entries that drives the chat help and the Commands rows. An entry:
-- { action = "" | word, usage = arguments shown in help ("on|off"), description, run = function(arguments),
-- troubleshooting = true for diagnostics }.
-- Troubleshooting entries ship in every build and show in the chat help under their own heading, not on
-- the settings page (as other addons). Each module answers to /boltgrip <module>
-- and /<module>; full names, not aliases, since slash clashes resolve unpredictably (ChatFrameUtil.lua
-- imports SlashCmdList).
lib.commands = lib.commands or {}

-- Rows in Blizzard's own help shape, "/command <arguments> - What it does", with the command in the
-- device's color. help itself is not listed. The chat frame indents a wrapped line on its own.

local function AddEntries(rows, command, troubleshooting)
	local any = false
	for _, entry in ipairs(command.entries) do
		if (entry.troubleshooting or false) == troubleshooting and entry.action ~= "help" then
			if troubleshooting and not any then
				-- A section heading in the game's heading gold, as a tooltip's headings are; its rows sit one step in.
				table.insert(rows, NORMAL_FONT_COLOR:WrapTextInColorCode("Troubleshooting"))
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
	self:PrintBlock(("%s commands:"):format(command.title), rows)
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
function lib:RegisterCommands(module, name, entries)
	name = name:lower()
	module.command = name
	local hasHelp = false
	for _, entry in ipairs(entries) do
		hasHelp = hasHelp or entry.action == "help"
	end
	if not hasHelp then
		table.insert(entries, { action = "help", description = "List these commands",
			note = "Prints these commands in your chat window, with what each one does.", run = function()
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
