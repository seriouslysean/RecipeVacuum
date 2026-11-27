-- The kit's stand-ins for the client, for offline tests of any addon that embeds the kit. They travel
-- with the library (Libs/JigBoltgripToolkit/tests), so when the kit starts calling something new, every
-- addon's tests get the stand-in with the same copy.
--   local client = dofile("Libs/JigBoltgripToolkit/tests/stubs.lua")
-- Installs globals on _G and returns { chat = { lines printed }, Stub = function(name) }.
-- Any global the client has and the tests do not name resolves to a stub: callable, indexable, and
-- itself the result of both, so load-time code (frames, events, hooks) runs without the client.
local client = { chat = {} }

local stubMeta = {}
stubMeta.__index = function(stub) return stub end
stubMeta.__call = function(stub) return stub end
stubMeta.__concat = function(left, right)
	return (type(left) == "string" and left or "") .. (type(right) == "string" and right or "")
end
function client.Stub(name)
	return setmetatable({ stubName = name }, stubMeta)
end

-- Blizzard's enUS global strings (tests/globalstrings.lua, from tools/global-strings.lua), read once: an upper-case name the
-- client defines as text reads as that text, so text built from it is the real one.
function client.GlobalStrings()
	if not client.strings then
		local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
		client.strings = dofile(here .. "/globalstrings.lua")
	end
	return client.strings
end

-- Unknown globals become stubs; a name read and never set still reads the same stub each time. Names in
-- client.unset stay nil: LibStub before it loads, and an addon's saved variables before the client reads them.
client.unset = { LibStub = true }
setmetatable(_G, { __index = function(globals, name)
	if client.unset[name] then return nil end
	-- The game's emote slash commands are plain strings (EMOTE98_CMD1 is "/thank"); modules label rows with them.
	local emote, command = name:match("^EMOTE(%d+)_CMD(%d+)$")
	if emote then
		local text = ("/emote%s%s"):format(emote, command == "1" and "" or "_" .. command)
		rawset(globals, name, text)
		return text
	end
	local text = client.GlobalStrings()[name]
	if text then
		rawset(globals, name, text)
		return text
	end
	local stub = client.Stub(name)
	rawset(globals, name, stub)
	return stub
end })

-- Plain Lua the client adds.
date = os.date
strtrim = function(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end
strsplit = function(separator, text)
	local parts = {}
	for part in (text .. separator):gmatch("(.-)" .. separator:gsub("%p", "%%%0")) do parts[#parts + 1] = part end
	return unpack(parts)
end
strjoin = function(separator, ...) return table.concat({ ... }, separator) end
wipe = function(t) for key in pairs(t) do t[key] = nil end return t end
tContains = function(t, value) for _, item in ipairs(t) do if item == value then return true end end return false end
CopyTable = function(t) local copy = {} for key, value in pairs(t) do copy[key] = type(value) == "table" and CopyTable(value) or value end return copy end
issecretvalue = function() return false end
debugstack = function() return "" end
debugprofilestop = os.clock

-- What the kit reads and calls (JigBoltgripToolkit.lua).
GetBuildInfo = function() return "1.60.1", "71091", "", 16001 end
GetTime = os.clock
GetServerTime = os.time
UnitName = function() return "Tester" end
UnitLevel = function() return 1 end
UnitFactionGroup = function() return "Alliance", "Alliance" end
GetSubZoneText = function() return "" end
GetPhysicalScreenSize = function() return 1280, 800 end
GetLocale = function() return "enUS" end
-- A client with no gamepad and no add-on profiler: both answer numbers the stand-ins cannot.
InputUtil = { IsGamepadUIEnabled = function() return false end }
-- No key is bound, and a key's text is the key itself: a module's fallback wording is what gets checked.
GetBindingKey = function() return nil end
GetBindingText = function(key) return key end
C_GamePad = { IsEnabled = function() return false end }
C_AddOnProfiler = { IsEnabled = function() return false end }
SlashCmdList = {}
UISpecialFrames = {}
NORMAL_FONT_COLOR = { WrapTextInColorCode = function(_, text) return text end }
HIGHLIGHT_FONT_COLOR = NORMAL_FONT_COLOR
-- Class colors are color objects in the client, so addon code may call their methods.
-- Enum fields whose values code computes with (bit.band fails on a stub); every other field stays a stub. Values:
-- Blizzard_APIDocumentationGenerated/SoftTargetConstantsDocumentation.lua.
Enum = setmetatable({ SoftTargetEnableFlags = { None = 0, Gamepad = 1, Kbm = 2, Any = 3 } }, {
	__index = function(enum, name)
		local stub = client.Stub("Enum." .. name)
		rawset(enum, name, stub)
		return stub
	end })

RAID_CLASS_COLORS = setmetatable({}, { __index = function()
	return { r = 1, g = 1, b = 1, colorStr = "ffffffff", WrapTextInColorCode = function(_, text) return text end,
		GenerateHexColor = function() return "ffffffff" end, GetRGB = function() return 1, 1, 1 end }
end })
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) client.chat[#client.chat + 1] = text end }
C_AddOns = { GetAddOnMetadata = function(addon, field) return field == "Title" and addon or nil end,
	IsAddOnLoaded = function() return false end } -- no other addon is installed beside the one checked
C_Map = { GetBestMapForUnit = function() return nil end, GetMapInfo = function() return nil end,
	GetPlayerMapPosition = function() return nil end }
EventUtil = { ContinueOnAddOnLoaded = function(name, callback)
	client.loaded = client.loaded or {}
	table.insert(client.loaded, { name = name, callback = callback })
end, ContinueOnPlayerLogin = function(callback) callback() end }
hooksecurefunc = function() end

-- Frames record their event handlers, so a test can fire the client's events (client.Fire). Any other
-- frame method is a stub.
client.frames = {}
-- Forgets every frame made so far, for a spec that loads the addon again per case.
function client.ClearFrames() client.frames = {} end
-- A model scene's actors have no scripts in Forever 1.60.1: actor:SetScript is nil there (measured on the Steam Deck,
-- 2026-11-27); Blizzard sets actor scripts in XML. Every other actor method is a stub.
local NO_ACTOR_METHODS = { SetScript = true, HookScript = true, GetScript = true }
local actorMeta = { __index = function(_, name)
	if NO_ACTOR_METHODS[name] then return nil end
	return client.Stub("actor." .. name)
end }
local frameMeta = { __index = function(_, name)
	if name == "CreateActor" then return function() return setmetatable({}, actorMeta) end end
	return client.Stub("frame." .. name)
end }
function CreateFrame()
	local frame = setmetatable({ events = {}, scripts = {} }, frameMeta)
	function frame:RegisterEvent(event) self.events[event] = true end
	-- The unit filter is not modeled: a unit event reaches the frame for any unit, so a spec fires it with the unit it means.
	function frame:RegisterUnitEvent(event) self.events[event] = true end
	function frame:UnregisterEvent(event) self.events[event] = nil end
	function frame:UnregisterAllEvents() wipe(self.events) end
	function frame:SetScript(name, handler) self.scripts[name] = handler end
	function frame:HookScript(name, handler) self.scripts[name] = self.scripts[name] or handler end
	function frame:GetScript(name) return self.scripts[name] end
	client.frames[#client.frames + 1] = frame
	return frame
end

-- Fires an event at every frame registered for it. Each handler error is kept with the event's name
-- (client.errors), so a test can fail on it rather than pass with the error hidden.
client.errors, client.standInLimits = {}, {}
function client.Fire(event, ...)
	for _, frame in ipairs(client.frames) do
		local handler = frame.events[event] and frame.scripts.OnEvent
		if handler then
			local ok, problem = pcall(handler, frame, event, ...)
			if not ok then
				problem = event .. ": " .. tostring(problem)
				-- A stand-in is a table where the client answers a number; arithmetic or a comparison on it
				-- fails here and never in the game. Those are listed apart, not counted as errors, so no
				-- addon changes its code for the stand-ins.
				local limit = problem:find("compare %a+ with table") or problem:find("compare table with")
					or problem:find("arithmetic on .-table value") -- with or without a field name (LuaJIT)
				table.insert(limit and client.standInLimits or client.errors, problem)
			end
		end
	end
end

-- Settings: every row the kit adds is recorded in order.
client.rows = {}
local function Category()
	return { GetID = function() return 1 end, SetExpanded = function() end }, { AddInitializer = function(_, row) table.insert(client.rows, row) end,
		GetInitializers = function() return client.rows end }
end
Settings = setmetatable({
	RegisterVerticalLayoutCategory = Category,
	RegisterVerticalLayoutSubcategory = Category,
	RegisterAddOnSetting = function(_, variable, key, db, _, label, default)
		local setting = { variable = variable, key = key, label = label, value = default }
		function setting:GetValue() return self.value end
		function setting:SetValue(value) self.value = value end
		function setting:SetValueChangedCallback() end
		return setting
	end,
	CreateCheckbox = function(_, setting, tooltip)
		local row = { checkbox = setting.label, tooltip = tooltip }
		function row:SetParentInitializer() end
		table.insert(client.rows, row)
		return row
	end,
	CreateSliderOptions = function(minimum, maximum, step)
		local options = { minimum = minimum, maximum = maximum, step = step }
		function options:SetLabelFormatter(side, formatter) self.side, self.formatter = side, formatter end
		return options
	end,
	CreateSlider = function(_, setting, options, tooltip)
		local row = { slider = setting.label, options = options, tooltip = tooltip }
		table.insert(client.rows, row)
		return row
	end,
	VarType = { Boolean = "boolean", Number = "number", String = "string" },
}, { __index = function(settings, name) return client.Stub("Settings." .. name) end })
function CreateSettingsListSectionHeaderInitializer(title) return { header = title } end
function CreateSettingsButtonInitializer(title, _, _, tooltip) return { button = title, tooltip = tooltip } end
MinimalSliderWithSteppersMixin = { Label = { Left = 0, Right = 1, Top = 2, Min = 3, Max = 4 } }

-- Runs the ADDON_LOADED callbacks registered for addonName, as the client does once saved data is read.
-- Then the start-up events, in the client's order, for code that waits for login (key bindings are read then).
-- Newest registration first: the client promises no order, and an addon that depends on its files'
-- registration order breaks in the game.
function client.Loaded(addonName)
	local loaded = client.loaded or {}
	for index = #loaded, 1, -1 do
		if loaded[index].name == addonName then loaded[index].callback() end
	end
	client.Fire("ADDON_LOADED", addonName)
	client.Fire("PLAYER_LOGIN")
	client.Fire("PLAYER_ENTERING_WORLD", true, false)
end

return client
