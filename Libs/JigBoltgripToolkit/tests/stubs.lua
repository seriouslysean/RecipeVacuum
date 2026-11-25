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

-- Unknown globals become stubs; a name read and never set still reads the same stub each time. Names in
-- client.unset stay nil: LibStub before it loads, and an addon's saved variables before the client reads them.
client.unset = { LibStub = true }
setmetatable(_G, { __index = function(globals, name)
	if client.unset[name] then return nil end
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
SlashCmdList = {}
UISpecialFrames = {}
NORMAL_FONT_COLOR = { WrapTextInColorCode = function(_, text) return text end }
HIGHLIGHT_FONT_COLOR = NORMAL_FONT_COLOR
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) client.chat[#client.chat + 1] = text end }
C_AddOns = { GetAddOnMetadata = function(addon, field) return field == "Title" and addon or nil end }
C_Map = { GetBestMapForUnit = function() return nil end, GetMapInfo = function() return nil end,
	GetPlayerMapPosition = function() return nil end }
EventUtil = { ContinueOnAddOnLoaded = function(name, callback)
	client.loaded = client.loaded or {}
	table.insert(client.loaded, { name = name, callback = callback })
end }
hooksecurefunc = function() end

-- Settings: every row the kit adds is recorded in order.
client.rows = {}
local function Category()
	return { GetID = function() return 1 end }, { AddInitializer = function(_, row) table.insert(client.rows, row) end }
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
	CreateDropdown = function(_, setting, _, tooltip)
		local row = { dropdown = setting.label, tooltip = tooltip }
		table.insert(client.rows, row)
		return row
	end,
	VarType = { Boolean = "boolean", Number = "number", String = "string" },
}, { __index = function(settings, name) return client.Stub("Settings." .. name) end })
function CreateSettingsListSectionHeaderInitializer(title) return { header = title } end
function CreateSettingsButtonInitializer(title) return { button = title } end

-- Runs the ADDON_LOADED callbacks registered for addonName, as the client does once saved data is read.
function client.Loaded(addonName)
	for _, entry in ipairs(client.loaded or {}) do
		if entry.name == addonName then entry.callback() end
	end
end

return client
