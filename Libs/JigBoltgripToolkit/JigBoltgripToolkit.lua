-- Shared home for Jig Boltgrip's Toolkit modules. Each module embeds this file; LibStub keeps
-- one copy (the newest) when several modules are installed. The toolkit gets one category in
-- Blizzard's Settings panel, and each installed module adds its own subcategory under it.
local MAJOR, MINOR = "JigBoltgripToolkit-1.0", 4
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
	return
end

lib.title = "Jig Boltgrip's Toolkit"

-- The toolkit's own Settings page is the top-level entry, as Blizzard's Settings guide allows
-- (a canvas category with list subcategories) and as single addons such as another addon, Scrap
-- and another addon use their top-level entry for their own content. It lists the installed
-- modules; each module's settings are a subcategory under it.
lib.modules = lib.modules or {}

function lib:GetCategory()
	if not self.category then
		local panel = CreateFrame("Frame")
		local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
		title:SetPoint("TOPLEFT", 16, -16)
		title:SetPoint("TOPRIGHT", -16, -16)
		title:SetJustifyH("LEFT")
		title:SetText(self.title)
		local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		heading:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
		heading:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -16)
		heading:SetJustifyH("LEFT")
		heading:SetText(ADDONS or "AddOns")
		local list = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		list:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
		list:SetPoint("TOPRIGHT", heading, "BOTTOMRIGHT", 0, -8)
		list:SetJustifyH("LEFT")
		panel:SetScript("OnShow", function()
			local parts = {}
			for _, module in ipairs(self.modules) do
				table.insert(parts, NORMAL_FONT_COLOR:WrapTextInColorCode(module.title) .. "\n" .. (module.notes or ""))
			end
			list:SetText(table.concat(parts, "\n\n"))
		end)
		self.category = Settings.RegisterCanvasLayoutCategory(panel, self.title)
		Settings.RegisterAddOnCategory(self.category)
	end
	return self.category
end

-- Returns the module's own settings category and layout.
function lib:RegisterModule(title, notes)
	table.insert(self.modules, { title = title, notes = notes })
	return Settings.RegisterVerticalLayoutSubcategory(self:GetCategory(), title)
end

-- One slash command for the whole toolkit: /boltgrip <module> <action> [arguments].
lib.commands = lib.commands or {}

-- handler(action, arguments) runs for "/boltgrip <module> ..."; actions lists them for help.
function lib:RegisterCommand(module, handler, actions)
	self.commands[module:lower()] = { handler = handler, actions = actions }
end

local function PrintHelp()
	print(lib.title .. ": /boltgrip <module> <action>")
	local modules = {}
	for module in pairs(lib.commands) do
		table.insert(modules, module)
	end
	table.sort(modules)
	for _, module in ipairs(modules) do
		print("  " .. module .. ": " .. table.concat(lib.commands[module].actions, ", "))
	end
end

SLASH_BOLTGRIP1 = "/boltgrip"
SlashCmdList.BOLTGRIP = function(message)
	local module, action, arguments = strtrim(message or ""):match("^(%S*)%s*(%S*)%s*(.-)$")
	local command = lib.commands[module:lower()]
	if command and action ~= "" then
		command.handler(action:lower(), arguments)
	else
		PrintHelp()
	end
end
