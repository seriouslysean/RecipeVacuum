-- Offline specs: the real library file loaded more than once through the real LibStub, as happens
-- when two addons embed copies. Client functions are stubs.
-- busted        (JBT_LIBRARY defaults to JigBoltgripToolkit.lua, JBT_LIBSTUB to tests/LibStub.lua)
-- The specs build one client step by step, so `it` blocks run in file order and later ones read what
-- earlier ones set up.
local LIBRARY = os.getenv("JBT_LIBRARY") or "JigBoltgripToolkit.lua"
-- LibStub (public domain) is kept in tests/ so the library's checks need nothing beside it.
local LIBSTUB = os.getenv("JBT_LIBSTUB") or "tests/LibStub.lua"

local source, CURRENT, toolkit, ran

-- The client's globals must be the real ones: the library is loaded through the real LibStub and reads
-- them from there, while busted gives each spec function a private environment that would hide them.
local G = getfenv(0)
local function real(fn)
	return function(...) setfenv(fn, G); return fn(...) end
end

-- A fresh client: globals the library reads, and a record of what it shows the player.
local chat, buttons, epsilonText
local function NewClient()
	chat, buttons = {}, {}
	LibStub = nil
	dofile(LIBSTUB)
	SlashCmdList = {}
	NORMAL_FONT_COLOR = { WrapTextInColorCode = function(_, text) return "|cffffd100" .. text .. "|r" end }
	GRAY_FONT_COLOR = { WrapTextInColorCode = function(_, text) return "|cff808080" .. text .. "|r" end }
	ChatTypeInfo = { SYSTEM = { r = 1, g = 1, b = 0, id = 1 }, MONSTER_SAY = { r = 1, g = 1, b = 0.5, id = 12 } }
	DEFAULT_CHAT_FRAME = { AddMessage = function(_, text, r, g, b) table.insert(chat, text); chat.color = { r, g, b } end }
	RAID_CLASS_COLORS = { MAGE = { r = 0, g = 0, b = 1 } }
	FRIENDS = "Friends" -- Blizzard's global string, enUS
	IsLoggedIn = function() return false end
	CreateFrame = function() return { SetScript = function() end, RegisterEvent = function() end } end
	EventUtil = { ContinueOnPlayerLogin = function(callback) callback() end, ContinueOnAddOnLoaded = function() end }
	C_Timer = { After = function() end }
	-- Blizzard's Settings page order (GameplaySettingsGroup.lua), enUS titles.
	CUSTOM_GAMEPLAY_SETTINGS_ORDER = { ["Combat"] = 10, ["Keybindings"] = 14 }
	SETTINGS_KEYBINDINGS_LABEL = "Keybindings"
	CONTEXT_ACTION_LABEL_OPEN = "Open"
	function strtrim(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end
	C_AddOns = { GetAddOnMetadata = function(addon, field)
		if field == "Title" then return addon .. " title" end
	end }
	local function Category()
		return { GetID = function() return 1 end, SetExpanded = function() end }, { AddInitializer = function(_, row) table.insert(buttons, row) end,
			GetInitializers = function() return buttons end }
	end
	Settings = {
		RegisterVerticalLayoutCategory = Category,
		RegisterCanvasLayoutCategory = function(frame, title)
			table.insert(buttons, { canvas = title })
			return (Category())
		end,
		RegisterVerticalLayoutSubcategory = Category,
		RegisterAddOnCategory = function() end,
		OpenToCategory = function() end,
	}
	MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
	function CreateSettingsListSectionHeaderInitializer(title) return { header = title } end
	function CreateSettingsButtonInitializer(title, _, click, tooltip) return { button = title, click = click, tooltip = tooltip } end
end
setfenv(NewClient, G)

-- Loads the library as a copy with the given MINOR.
local function Load(minor)
	local copy = source:gsub('("JigBoltgripToolkit%-1%.0", )%d+', "%1" .. minor, 1)
	assert(loadstring(copy, "JigBoltgripToolkit@" .. minor))()
end

local function Count(list, field, value)
	local count = 0
	for _, row in ipairs(list) do
		if row[field] == value then count = count + 1 end
	end
	return count
end

-- An addon's startup: register the module and one command that records its argument.
local function StartAddon(addon, slash)
	local tk = LibStub("JigBoltgripToolkit-1.0")
	local module = tk:RegisterModule(addon)
	tk:RegisterCommands(module, slash, {
		{ action = "go", description = "Go", run = function(arguments) ran = addon .. ":" .. arguments end },
	})
	tk:FinishModule(module)
end

describe("load order", function()
	local busted_it, busted_setup = it, setup
	local function it(name, fn) busted_it(name, real(fn)) end
	local function setup(fn) busted_setup(real(fn)) end

	setup(function()
		source = assert(io.open(LIBRARY)):read("*a")
		CURRENT = tonumber(source:match('"JigBoltgripToolkit%-1%.0", (%d+)'))
	end)

	-- Each row: the MINOR of the copy the first addon embeds, then of the second addon's copy.
	local orders = {
		{ name = "same copy twice", first = 0, second = 0 },
		{ name = "newer copy loads second", first = 0, second = 1 },
		{ name = "older copy loads second", first = 1, second = 0 },
	}
	for _, order in ipairs(orders) do
		local first, second
		it(order.name .. ": newest copy is the one in use", function()
			first, second = CURRENT + order.first, CURRENT + order.second
			NewClient()
			Load(first)
			StartAddon("Alpha", "alpha")
			Load(second)
			StartAddon("Beta", "beta")
			local _, minor = LibStub("JigBoltgripToolkit-1.0")
			assert(minor == math.max(first, second), order.name .. ": newest copy is the one in use")
		end)
		it(order.name .. ": first addon's own command still runs", function()
			ran = nil
			SlashCmdList.BOLTGRIP_ALPHA("go one")
			assert(ran == "Alpha:one", order.name .. ": first addon's own command still runs")
		end)
		it(order.name .. ": /boltgrip reaches the second addon", function()
			ran = nil
			SlashCmdList.BOLTGRIP("beta go two")
			assert(ran == "Beta:two", order.name .. ": /boltgrip reaches the second addon")
		end)
		it(order.name .. ": /boltgrip reaches the first addon", function()
			ran = nil
			SlashCmdList.BOLTGRIP("alpha go three")
			assert(ran == "Alpha:three", order.name .. ": /boltgrip reaches the first addon")
		end)
		it(order.name .. ": no Open row per addon", function()
			assert(Count(buttons, "button", "Alpha title") == 0 and Count(buttons, "button", "Beta title") == 0,
				order.name .. ": no Open row per addon")
		end)
		it(order.name .. ": no canvas page", function()
			assert(Count(buttons, "canvas", "Jig Boltgrip's Toolkit") == 0, order.name .. ": no canvas page")
		end)
	end

	-- Fails if a working-build line reads like a player's line: it must be grey and tagged.
	it("a debug line is grey and tagged [Debug]", function()
		NewClient()
		Load(CURRENT)
		LibStub("JigBoltgripToolkit-1.0"):Debug("probe")
		local line = chat[#chat]
		assert(line:find("|cff808080[Debug] probe|r", 1, true) ~= nil, "a debug line is grey and tagged [Debug]")
	end)

	-- Fails if a blocked action's scan misses a gamepad field an addon wrote, so the writer stays unnamed.
	it("a blocked action names gamepad fields an addon tainted", function()
		NewClient()
		Load(CURRENT)
		local manager = { RemoveSet = function() end, coreSet = {} }
		GamepadSharedUtility = { InputBindingManager = manager }
		issecurevariable = function(t, key) if t == manager and key == "RemoveSet" then return false, "Tackletron" end return true end
		local fields = LibStub("JigBoltgripToolkit-1.0"):ScanTaint()
		GamepadSharedUtility, issecurevariable = nil, nil
		assert(#fields == 1 and fields[1] == "tainted field path=GamepadSharedUtility.InputBindingManager.RemoveSet addon=Tackletron",
			"a blocked action names gamepad fields an addon tainted")
	end)

	-- Fails if a working build's reset leaves a once-only line silenced, or misses a module's own flag.
	it("the once-only reset clears every module's once-ever flags", function()
		NewClient()
		Load(CURRENT)
		local tk = LibStub("JigBoltgripToolkit-1.0")
		local one, two = { addon = "One", title = "One" }, { addon = "Two", title = "Two" }
		local dbOne, dbTwo = {}, { tipShown = true }
		tk:SayOnce(one, dbOne, "told", "noise", "Report!")
		tk:RememberOnce(two, dbTwo, "tipShown")
		local cleared = tk:ResetOnce()
		assert(cleared == 2 and dbOne.told == nil and dbTwo.tipShown == nil and tk:SayOnce(one, dbOne, "told", "noise", "Report!"),
			"the once-only reset clears every module's once-ever flags")
	end)

	-- Fails if the kit's log line drifts from logfmt: key order, quoting, nil, booleans or the ms rounding.
	it("the kit writes logfmt lines", function()
		NewClient()
		Load(CURRENT)
		local tk = LibStub("JigBoltgripToolkit-1.0")
		local line = tk.LogLine("list shown", "id", 171, "name", "Mana Well", "kept", true, "gone", nil, "ms", 1.44, "tiny_ms", 0.044,
			"rate", 2.5, "big", 1795795181)
		assert(line == 'list shown id=171 name="Mana Well" kept=true gone=- ms=1.4 tiny_ms=0.04 rate=2.5 big=1795795181',
			"the kit writes logfmt lines: " .. line)
		assert(not pcall(tk.LogLine, "bad", "NotSnake", 1), "a key that is not snake_case is refused")
		assert(tk.IsLogEvent("trainer read") and not tk.IsLogEvent("trainer read again now") and not tk.IsLogEvent("x=%d"),
			"an event is one to three lowercase words")
	end)

	-- Starting the same addon twice (a module file loaded again) adds nothing.
	it("registering a module again returns the same module", function()
		NewClient()
		Load(CURRENT)
		StartAddon("Alpha", "alpha")
		local rows = #buttons
		toolkit = LibStub("JigBoltgripToolkit-1.0")
		assert(toolkit:RegisterModule("Alpha") == toolkit.modules[1] and #toolkit.modules == 1 and #buttons == rows,
			"registering a module again returns the same module")
	end)

	-- An unknown command prints the help, which names every command.
	it("unknown command prints the help", function()
		chat = {}
		SlashCmdList.BOLTGRIP_ALPHA("nonsense")
		local help = table.concat(chat, "\n")
		assert(help:find("/alpha go", 1, true) and not help:find("/alpha help", 1, true) and true or false,
			"unknown command prints the help")
	end)

	-- A troubleshooting section: a gold heading, its commands one step further in. Fails if the heading
	-- reads like a command row or its commands lose the extra step.
	local SPACER = "|TInterface\\Common\\spacer:0|t "
	local heading, probe
	it("a troubleshooting heading is gold and not a command row", function()
		local tk = LibStub("JigBoltgripToolkit-1.0")
		local m = tk:RegisterModule("Gamma")
		tk:RegisterCommands(m, "gamma", { { action = "go", description = "Go", run = function() end },
			{ action = "probe", description = "Probe", run = function() end, troubleshooting = true } })
		chat = {}
		SlashCmdList.BOLTGRIP_GAMMA("nonsense")
		for _, line in ipairs(chat) do
			if line:find("Troubleshooting", 1, true) then heading = line end
			if line:find("/gamma probe", 1, true) then probe = line end
		end
		assert(heading == SPACER .. "|cffffd100Troubleshooting|r", "a troubleshooting heading is gold and not a command row")
	end)
	it("troubleshooting commands sit one step in", function()
		assert(probe ~= nil and probe:sub(1, 2 * #SPACER) == SPACER .. SPACER, "troubleshooting commands sit one step in")
	end)

	-- Options built from data. Fails if a setting loses its derived name or saved key, a note leaves its
	-- row's tooltip, an indented checkbox loses its parent, or a change stops reaching onChange.
	local registered, made, changed, built, m, tk, optionsSaved
	it("sections follow the toolkit's order whatever order a module lists them in", function()
		registered, made, changed = {}, {}, nil
		Settings.VarType = { Boolean = "boolean", Number = "number", String = "string" }
		-- As Blizzard's add-on setting does: the value is read from and written to the module's table.
		Settings.RegisterAddOnSetting = function(_, variable, key, store, varType, _, default)
			local setting = { variable = variable, key = key, varType = varType }
			function setting:SetValueChangedCallback(fn) self.callback = fn end
			function setting:GetValue() if store[key] == nil then return default end return store[key] end
			function setting:SetValue(value) store[key] = value; if self.callback then self.callback(self, value) end end
			registered[key] = setting
			return setting
		end
		Settings.CreateCheckbox = function(_, setting, tooltip)
			local row = { checkbox = setting.key, tooltip = tooltip }
			function row:SetParentInitializer(parent) self.parent = parent end
			table.insert(buttons, row); made[setting.key] = row
			return row
		end
		Settings.CreateSliderOptions = function(minimum, maximum)
			local options = { minimum = minimum, maximum = maximum }
			function options:SetLabelFormatter(_, formatter) self.formatter = formatter end
			return options
		end
		Settings.CreateSlider = function(_, setting, options, tooltip)
			local row = { slider = setting.key, options = options, tooltip = tooltip }
			table.insert(buttons, row); made[setting.key] = row
			return row
		end
		tk = LibStub("JigBoltgripToolkit-1.0")
		m = tk:RegisterModule("Delta")
		buttons = {}
		optionsSaved = {}
		built = tk:BuildOptions(m, optionsSaved, {
			{ heading = "Audio", place = "blizzard", rows = {} },
			{ heading = "Keybindings", place = "blizzard", rows = {} },
			{ heading = "Combat", place = "blizzard", rows = {} },
			{ heading = "Things", place = "features", rows = {
				{ kind = "checkbox", key = "record", label = "Record Things", tooltip = "t", default = true, note = "Why." },
				{ kind = "checkbox", key = "announce", label = "Announce Things", tooltip = "t", default = true, under = "record" },
				{ kind = "choice", key = "mode", label = "Mode", tooltip = "t", default = 20,
					values = { { value = 10, label = "One", description = "The first." }, { value = 20, label = "Two" },
						{ value = 30, label = "Three" } }, onChange = function(value) changed = value end },
			} },
			{ heading = "Thing Sources", place = "sources", rows = {
				{ kind = "choice", key = "level", label = "Thing Sources", default = 1,
					values = tk:SourceChoices({ self = "Tracks only things you see for yourself.", public = "Also tracks things people link in chat.", openings = false }) },
			} },
		})
		-- Fails if a module's sections are not put in the toolkit's one order: sources, features, Blizzard's, key bindings.
		local headings = {}
		for _, row in ipairs(buttons) do if row.header then headings[#headings + 1] = row.header end end
		assert(table.concat(headings, ",") == "Thing Sources,Things,Combat,Audio,Keybindings",
			"sections follow the toolkit's order whatever order a module lists them in")
	end)
	-- Fails if a sources section may put another row above its source choice.
	it("a sources section starts with its source choice", function()
		local choiceSecond = pcall(tk.BuildOptions, tk, m, {}, { { heading = "Late Sources", place = "sources", rows = {
			{ kind = "checkbox", key = "early", label = "Early", default = true },
			{ kind = "choice", key = "late", label = "Late Sources", default = 1, values = tk:SourceChoices({ self = "Tracks only things you see for yourself." }) } } } })
		assert(not choiceSecond, "a sources section starts with its source choice")
	end)
	-- Fails if hand-built source choices pass, or a module's choice to drop the range openings is ignored.
	it("source choices come only from the kit, in one sentence shape, with or without the range openings", function()
		local handBuilt = pcall(tk.BuildOptions, tk, m, {}, { { heading = "Hand Sources", place = "sources", rows = {
			{ kind = "choice", key = "hand", label = "Hand Sources", default = 1, values = { { value = 1, label = "Self Found", description = "Mine." } } } } } })
		local choices = tk:SourceChoices({ self = "Tracks only fish you see for yourself.", openings = false })
		local withOpenings = tk:SourceChoices({ self = "Tracks only recipes you see for yourself.", friends = true,
			public = "Also tracks recipes people link in chat." })
		assert(not handBuilt
			and #choices == 1 and choices[1].description == "Tracks only fish you see for yourself."
			and #withOpenings == 3 and withOpenings[2].description == "Medium range. Also tracks what your party, guild and friends find."
			and withOpenings[3].description == "Long range. Also tracks recipes people link in chat.",
			"source choices come only from the kit, in one sentence shape, with or without the range openings")
	end)
	it("a setting is named after the addon and saved under its key", function()
		assert(registered.record.variable == "Delta_record" and registered.record.varType == "boolean" and registered.mode.varType == "number",
			"a setting is named after the addon and saved under its key")
	end)
	it("a note joins its row's tooltip", function()
		assert(made.record.tooltip == "t\nWhy.", "a note joins its row's tooltip")
	end)
	it("an indented checkbox sits under its parent", function()
		assert(made.announce.parent == made.record, "an indented checkbox sits under its parent")
	end)
	-- Fails if a choice row stops mapping the slider's position to the module's saved value and back, or an
	-- unknown saved value (a removed option) no longer reads as the default.
	it("a choice row maps position to saved value both ways, and an unknown saved value reads as the default", function()
		optionsSaved.mode = 30
		local reads = registered.mode:GetValue()
		registered.mode:SetValue(1)
		local writes = optionsSaved.mode
		optionsSaved.mode = 99
		local unknown = registered.mode:GetValue()
		assert(reads == 3 and writes == 10 and unknown == 2 and made.mode.options.maximum == 3,
			"a choice row maps position to saved value both ways, and an unknown saved value reads as the default")
		optionsSaved.mode = nil
	end)
	it("a change reaches the row's onChange", function()
		built.mode:SetValue(3)
		assert(changed == 30, "a change reaches the row's onChange")
	end)

	-- Fails if a command on the options page loses the note that explains it, or gets another row's note.
	local goRow
	it("a command's note joins its button's tooltip, and one without a note repeats nothing", function()
		buttons = {}
		local epsilon = LibStub("JigBoltgripToolkit-1.0"):RegisterModule("Epsilon")
		LibStub("JigBoltgripToolkit-1.0"):RegisterCommands(epsilon, "epsilon", {
			{ action = "go", description = "Go", note = "Goes somewhere.", run = function(text) epsilonText = text end },
			{ action = "stop", description = "Stop", run = function() end },
		})
		LibStub("JigBoltgripToolkit-1.0"):FinishModule(epsilon)
		local tips = {}
		for _, row in ipairs(buttons) do
			if row.button then tips[row.button] = row.tooltip end
			if row.button == "/epsilon go" then goRow = row end
		end
		assert(tips["/epsilon go"] == "Go\nGoes somewhere." and tips["/epsilon stop"] == "Stop",
			"a command's note joins its button's tooltip, and one without a note repeats nothing")
	end)
	-- Fails if Run hands the command the clicked button, where typed words would go.
	it("Run runs the command as if typed with nothing after it", function()
		goRow.click({ IsObjectType = function() return true end }, "LeftButton", false)
		assert(epsilonText == "", "Run runs the command as if typed with nothing after it")
	end)
	it("help rows sit under the header text", function()
		chat = {}
		LibStub("JigBoltgripToolkit-1.0"):Dispatch("alpha", "nonsense")
		assert(chat[2] ~= nil and chat[2]:sub(1, #"|TInterface\\Common\\spacer") == "|TInterface\\Common\\spacer",
			"help rows sit under the header text")
	end)

	-- Chat: one shape for the whole family. Fails if the mark or the shared word goes missing, the device
	-- color reaches beyond the name, or rows under a header carry their own mark.
	local MARK = "|TInterface\\WorldMap\\GEAR_64GREY:0|t"
	it("a voiced line is the mark, the shared word, the class-colored name, the noise and the report", function()
		local blue = toolkit:RegisterModule("Alpha", "MAGE")
		chat = {}
		toolkit:Say(blue, "whirs and rattles", "Intake complete!")
		-- The class color (0, 0, 1) with 25% of the line color (91, 217, 222): 23, 54, 247.
		assert(chat[1] == MARK .. " Boltgrip's |cff1736f7Alpha title|r whirs and rattles. Intake complete!",
			"a voiced line is the mark, the shared word, the class-colored name, the noise and the report")
	end)
	-- Fails if the line stops being the family's own teal.
	it("a line is printed in the family's color", function()
		assert(math.abs(chat.color[1] - 91 / 255) < 0.001 and math.abs(chat.color[2] - 217 / 255) < 0.001 and math.abs(chat.color[3] - 222 / 255) < 0.001,
			"a line is printed in the family's color")
	end)
	it("a block marks its header and aligns its rows under the header text", function()
		chat = {}
		toolkit:PrintBlock("Header", { "one", "two" })
		local ALIGN = "|TInterface\\Common\\spacer:0|t "
		assert(chat[1] == MARK .. " Header" and chat[2] == ALIGN .. "one" and chat[3] == ALIGN .. "two",
			"a block marks its header and aligns its rows under the header text")
	end)
	it("a module without a class keeps the line color", function()
		chat = {}
		toolkit:Say({ title = "Plain" }, "hums", "Ready!")
		assert(chat[1] == MARK .. " Boltgrip's Plain hums. Ready!", "a module without a class keeps the line color")
	end)

	-- Working builds. Fails if a second call makes a second listener, or timings mix between modules.
	it("a working build shows Lua errors and listens once", function()
		local cvars, frames = {}, 0
		C_CVar = { GetCVar = function(name) return cvars[name] end, SetTempCVar = function(name, value) cvars[name] = value end }
		local realCreateFrame = CreateFrame
		CreateFrame = function()
			frames = frames + 1
			return { RegisterEvent = function() end, SetScript = function() end }
		end
		EventUtil = EventUtil or { ContinueOnAddOnLoaded = function() end }
		toolkit:EnableWorkingBuild()
		toolkit:EnableWorkingBuild()
		CreateFrame = realCreateFrame
		assert(cvars.scriptErrors == "1" and cvars.taintLog == "2" and frames == 1, "a working build shows Lua errors and listens once")
	end)
	it("timings are kept per module", function()
		local one, two = { addon = "One" }, { addon = "Two" }
		toolkit:TimeMs(one, "build", 4); toolkit:TimeMs(one, "build", 2); toolkit:TimeMs(two, "scan", 1)
		local lines = toolkit:TimingLines(one)
		assert(#lines == 1 and lines[1]:find("runs=2", 1, true) ~= nil
			and lines[1]:find("max_ms=4.0", 1, true) ~= nil and #toolkit:TimingLines(two) == 1,
			"timings are kept per module")
	end)

	-- Working-build log. Fails if lines go to another module's log, lose their order, or the cap drops the newest.
	local saved, module, listener, freshSaved, fresh, count
	it("the log keeps the newest lines, in order, per module, never more than its cap", function()
		date = date or os.date
		GetBuildInfo = GetBuildInfo or function() return "1.60.1", "71091" end
		C_AddOns = C_AddOns or {}
		C_AddOns.GetAddOnMetadata = C_AddOns.GetAddOnMetadata or function() return "test" end
		UnitName = UnitName or function() return "Tester" end
		UnitLevel = UnitLevel or function() return 1 end
		C_Map = C_Map or { GetBestMapForUnit = function() return 1429 end, GetMapInfo = function() return { name = "Elwynn Forest" } end }
		GetSubZoneText = GetSubZoneText or function() return "" end
		GetPhysicalScreenSize = GetPhysicalScreenSize or function() return 1280, 800 end
		GetLocale = GetLocale or function() return "enUS" end
		C_Map.GetPlayerMapPosition = C_Map.GetPlayerMapPosition or function() return nil end
		C_MapExplorationInfo = C_MapExplorationInfo or { GetExploredAreaIDsAtPosition = function() return nil end }
		saved = {}
		module = { addon = "Logger", title = "Logger" }
		local realCreateFrame = CreateFrame
		CreateFrame = function()
			local frame = { RegisterEvent = function() end, UnregisterAllEvents = function() end }
			frame.SetScript = function(self, _, fn) self.script = fn end
			return frame
		end
		toolkit:StartLog(module, saved)
		CreateFrame = realCreateFrame
		local cap, trim = toolkit.LOG_LINES, toolkit.LOG_TRIM
		saved.devLog = {} -- without the session header, so the count is exact
		local most = 0
		for index = 1, cap + trim + 1 do
			toolkit:Log(module, "line " .. index, true)
			most = math.max(most, #saved.devLog)
		end
		assert(#saved.devLog == cap
			and most == cap
			and saved.devLog[1] == "line " .. (trim + 2) and saved.devLog[cap] == "line " .. (cap + trim + 1),
			"the log keeps the newest lines, in order, per module, never more than its cap")
	end)
	-- Fails if a module that started a log is not logging, or its events don't reach it.
	local otherSaved, seen
	it("every module that starts a log is logging, and gets its own events", function()
		otherSaved, seen = {}, {}
		local other = { addon = "Other", title = "Other" }
		toolkit:StartLog(other, otherSaved, { LOOT_READY = function(slot) seen[#seen + 1] = slot end })
		listener = toolkit.watchFrame
		listener.script(listener, "LOOT_READY", 7)
		assert(toolkit:IsLogging(other) and seen[1] == 7 and #saved.devLog <= toolkit.LOG_LINES + toolkit.LOG_TRIM,
			"every module that starts a log is logging, and gets its own events")
	end)
	-- Fails if a working build can be switched off, or a log an older build left off stays off.
	it("a working build always logs, even after an older build turned it off", function()
		freshSaved = { watch = false }
		fresh = { addon = "Fresh", title = "Fresh" }
		toolkit:StartLog(fresh, freshSaved)
		SlashCmdList.BOLTGRIP("watch off")
		toolkit:Trace(fresh, "offer sent")
		assert(toolkit:IsLogging(fresh) and freshSaved.devLog[#freshSaved.devLog]:find("offer sent", 1, true) ~= nil,
			"a working build always logs, even after an older build turned it off")
	end)

	-- Errors and blocks go once, to the module the stack names, not to every log, and not to whichever module's kit
	-- copy the game blamed (the Deck, 2026-11-27: AutoOmniadjustor blamed for kit code).
	local function Holds(t, text)
		for _, line in ipairs(t.devLog) do if line:find(text, 1, true) then return true end end
		return false
	end
	it("an error goes once, to the module whose own file is in its stack", function()
		toolkit:OnLuaError("boom one", "Interface/AddOns/Other/Libs/JigBoltgripToolkit/JigBoltgripToolkit.lua:10: in x\n"
			.. "Interface/AddOns/Fresh/Core.lua:42: in y")
		assert(Holds(freshSaved, "lua error message=\"boom one\" owner=Fresh") and not Holds(otherSaved, "boom one") and not Holds(saved, "boom one"),
			"an error goes once, to the module whose own file is in its stack")
	end)
	it("an error through kit code only goes to the module whose copy ran it, tagged as the kit's", function()
		toolkit:OnLuaError("boom two", "Interface/AddOns/Other/Libs/JigBoltgripToolkit/JigBoltgripToolkit.lua:10: in x")
		assert(Holds(otherSaved, "message=\"boom two\" owner=kit copy=Other") and not Holds(freshSaved, "boom two"),
			"an error through kit code only goes to the module whose copy ran it, tagged as the kit's")
	end)
	it("a block with no addon file in its stack goes to the module the game blamed", function()
		toolkit:LogBlamed("blocked event=ADDON_ACTION_FORBIDDEN addon=Fresh call=Thing()", "[C]: in function", "Fresh")
		assert(Holds(freshSaved, "call=Thing() owner=Fresh source=game") and not Holds(otherSaved, "Thing()"),
			"a block with no addon file in its stack goes to the module the game blamed")
	end)

	-- Fails if the library holds a packager token, even in a comment: the packager turns "--@debug@" into the
	-- start of a block comment, so everything after it would vanish from release builds.
	it("the library holds no packager tokens", function()
		local file = assert(io.open(LIBRARY))
		local text = file:read("*a")
		file:close()
		assert(not text:find("%-%-@[%a%-]+@"), "the library holds no packager tokens")
	end)

	-- Fails if a save from a newer build is rewritten: lowering its schema number makes the next upgrade run
	-- the migration steps again on migrated data (found in Tackletron and Buffulator).
	it("a save from a newer build is left unchanged, and the module runs on an empty copy", function()
		local newerSave = { schema = 9, kept = true }
		_G.NewerDB = newerSave
		local steps = {}
		local db = toolkit:LoadSaved({ title = "Newer" }, "NewerDB", { schema = 3, defaults = { shown = true },
			migrations = { [2] = function() steps[#steps + 1] = 2 end, [3] = function() steps[#steps + 1] = 3 end } })
		assert(_G.NewerDB == newerSave and newerSave.schema == 9 and newerSave.kept and #steps == 0
			and db ~= newerSave and db.shown and db.schema == 3,
			"a save from a newer build is left unchanged, and the module runs on an empty copy")
		_G.OlderDB = { schema = 1 }
		toolkit:LoadSaved({ title = "Older" }, "OlderDB", { schema = 3, migrations = {
			[2] = function() steps[#steps + 1] = 2 end, [3] = function() steps[#steps + 1] = 3 end } })
		assert(_G.OlderDB.schema == 3 and #steps == 2, "an older save runs each later step in order")
	end)

	-- Fails if a saved variable that is not a table errors the load (Lua error on "string".schema), or is overwritten.
	it("a saved variable that is not a table is left alone and the module runs on an empty copy", function()
		_G.OddDB = "corrupt"
		local db = toolkit:LoadSaved({ addon = "Odd", title = "Odd" }, "OddDB", { schema = 1, defaults = { shown = true } })
		assert(_G.OddDB == "corrupt" and db.shown and db.schema == 1, "a non-table save is kept and an empty copy runs")
	end)

	-- Fails if a per-character table is migrated only when the account's own schema moves: the first character to log
	-- in raised the account's number and every other character's table was read as current.
	it("a character table runs the steps above its own schema number", function()
		local steps = {}
		_G.CharRunDB, _G.CharRunChar = { schema = 2 }, { schema = 1, keep = true }
		local _, characterDb = toolkit:LoadSaved({ title = "Char" }, "CharRunDB", { schema = 2, character = "CharRunChar",
			migrations = {}, characterMigrations = { [2] = function(character) steps[#steps + 1] = character.keep end } })
		assert(#steps == 1 and steps[1] and characterDb.schema == 2, "the character table ran its own step 2")
	end)

	-- Fails if an unnumbered character table takes its number from the account's: a later character's table skipped its
	-- steps once the first login had raised the account, and an old account made the table run steps it was never owed.
	it("an unnumbered character table is current and runs no step, whatever the account's number is", function()
		local steps = {}
		local spec = { schema = 3, character = "CharFloorChar", migrations = {},
			characterMigrations = { [2] = function() steps[#steps + 1] = 2 end, [3] = function() steps[#steps + 1] = 3 end } }
		_G.CharFloorDB, _G.CharFloorChar = { schema = 1 }, {}
		local _, characterDb = toolkit:LoadSaved({ title = "Floor" }, "CharFloorDB", spec)
		assert(#steps == 0 and characterDb.schema == 3, "an old account does not give an unnumbered character table steps")
		_G.CharFloorDB, _G.CharFloorChar = { schema = 3 }, {}
		_, characterDb = toolkit:LoadSaved({ title = "Floor" }, "CharFloorDB", spec)
		assert(#steps == 0 and characterDb.schema == 3, "a current account does not change that")
	end)

	-- Fails if a newer character save is rewritten while the account save is older (stamp, defaults and an account step
	-- given a stand-in character table), or the reverse.
	it("when either save is newer, neither is written in that load", function()
		local steps = {}
		local spec = { schema = 3, character = "BothChar", defaults = { shown = true }, characterDefaults = { mine = true },
			migrations = { [3] = function(_, character) steps[#steps + 1] = character end } }
		local account, character = { schema = 2 }, { schema = 9, kept = true }
		_G.BothDB, _G.BothChar = account, character
		local db, characterDb = toolkit:LoadSaved({ title = "Both" }, "BothDB", spec)
		assert(_G.BothDB == account and account.schema == 2 and account.shown == nil and #steps == 0
			and _G.BothChar == character and character.schema == 9 and character.mine == nil
			and db ~= account and characterDb ~= character and db.shown and characterDb.mine, "a newer character save leaves both alone")
		account, character = { schema = 9 }, { schema = 2 }
		_G.BothDB, _G.BothChar = account, character
		toolkit:LoadSaved({ title = "Both" }, "BothDB", spec)
		assert(account.schema == 9 and character.schema == 2 and character.mine == nil, "a newer account save leaves both alone")
	end)

	-- Fails if a key added to a nested defaults table never reaches a save that already has the table, or if a
	-- player's shorter list is topped up from the defaults.
	it("nested defaults are filled key by key and lists are left as saved", function()
		_G.NestDB = { schema = 1, colors = { red = 1 }, list = { "a" } }
		local db = toolkit:LoadSaved({ title = "Nest" }, "NestDB", { schema = 1,
			defaults = { colors = { red = 0, blue = 2 }, list = { "a", "b" } } })
		assert(db.colors.red == 1 and db.colors.blue == 2 and #db.list == 1, "nested keys fill and a list stays")
	end)

	-- Fails if a frame's event count rides on a hook a module's own SetScript("OnEvent") can drop (found in
	-- Tackletron: WatchEvents before SetScript logged no EVENT lines).
	it("an event frame counts its events in its own dispatcher", function()
		local realCreateFrame, realTimer = CreateFrame, C_Timer
		local flush
		C_Timer = { After = function(_, fn) flush = fn end }
		CreateFrame = function()
			local frame = { RegisterEvent = function() end }
			frame.SetScript = function(self, _, fn) self.script = fn end
			return frame
		end
		local got
		local frame = toolkit:EventFrame(fresh, { PLAYER_LOGIN = function(arg) got = arg end })
		CreateFrame = realCreateFrame
		frame.script(frame, "PLAYER_LOGIN", 5)
		C_Timer = realTimer
		flush()
		assert(got == 5 and freshSaved.devLog[#freshSaved.devLog]:find("event name=PLAYER_LOGIN count=1", 1, true),
			"an event frame counts its events in its own dispatcher")
	end)

	-- Fails if a share made by an older copy keeps running that copy's code after a newer copy loads (a method
	-- bound at creation instead of looked up at call time).
	it("a share made by an older copy runs the newer copy's methods", function()
		NewClient()
		local realCreateFrame = CreateFrame
		CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end, HookScript = function() end } end
		Load(CURRENT)
		local older = LibStub("JigBoltgripToolkit-1.0")
		local nothing = function() end
		local share = older:NewShare({ addon = "Alpha" }, { protocol = 1, kinds = {}, wire = nothing, validate = nothing,
			merge = nothing, sending = nothing, receiving = nothing })
		local before = share.Merge
		Load(CURRENT + 1)
		CreateFrame = realCreateFrame
		assert(LibStub("JigBoltgripToolkit-1.0").shares.Alpha == share and share.Merge ~= before,
			"a share made by an older copy runs the newer copy's methods")
	end)
end)
