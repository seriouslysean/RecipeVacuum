-- Shared home for Jig Boltgrip's Toolkit modules. Each module embeds this file; LibStub keeps the newest.
-- One Settings category for the toolkit, one subcategory per installed module.
local MAJOR, MINOR = "JigBoltgripToolkit-1.0", 8
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

-- Registers a module by addon folder name; returns its settings category and layout. Call
-- lib:FinishModule(module) after adding the module's rows.
function lib:RegisterModule(addonName)
	for _, existing in ipairs(self.modules) do
		if existing.addon == addonName then return existing end
	end
	local title = C_AddOns.GetAddOnMetadata(addonName, "Title")
	local notes = C_AddOns.GetAddOnMetadata(addonName, "Notes")
	local parent, parentLayout = self:GetCategory()
	local category, layout = Settings.RegisterVerticalLayoutSubcategory(parent, title)
	local module = { addon = addonName, title = title, notes = notes, category = category, layout = layout }
	table.insert(self.modules, module)
	parentLayout:AddInitializer(CreateSettingsButtonInitializer(title, OPEN or "Open", function()
		Settings.OpenToCategory(category:GetID())
	end, notes, false))
	return module
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
function lib:ShowText(title, text)
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
	frame.Title:SetText(title)
	frame.ScrollingEditBox:SetText(text)
	frame:Show()
	local editBox = frame.ScrollingEditBox:GetEditBox()
	editBox:SetFocus()
	editBox:HighlightText()
end

function lib:IsTextShown()
	return self.textFrame and self.textFrame:IsShown()
end

-- Each module registers a table of entries that drives the chat help and the Commands rows. An entry:
-- { action = "" | word, description, run = function(arguments), troubleshooting = true for diagnostics }.
-- Troubleshooting entries ship in every build and show in the chat help under their own heading, not on
-- the settings page (as other addons). Each module answers to /boltgrip <module>
-- and /<module>; full names, not aliases, since slash clashes resolve unpredictably (ChatFrameUtil.lua
-- imports SlashCmdList).
lib.commands = lib.commands or {}

-- Help prints in the system message color, as /help does (ChatFrameUtil.DisplayHelpText).
local function Say(text)
	local info = ChatTypeInfo.SYSTEM
	DEFAULT_CHAT_FRAME:AddMessage(text, info.r, info.g, info.b, info.id)
end

local function PrintEntries(command, troubleshooting)
	for _, entry in ipairs(command.entries) do
		if (entry.troubleshooting or false) == troubleshooting then
			local slash = "/" .. command.name .. (entry.action ~= "" and " " .. entry.action or "")
			Say(("  %s - %s"):format(slash, entry.description))
		end
	end
end

function lib:PrintHelp(name)
	local command = self.commands[name]
	Say(("%s commands (/%s or /boltgrip %s):"):format(command.title, command.name, command.name))
	PrintEntries(command, false)
	for _, entry in ipairs(command.entries) do
		if entry.troubleshooting then
			Say("Troubleshooting:")
			PrintEntries(command, true)
			break
		end
	end
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
		table.insert(entries, { action = "help", description = "List these commands", run = function()
			lib:PrintHelp(name)
		end })
	end
	self.commands[name] = { name = name, title = module.title, entries = entries }
	SetSlashHandler(name)
end

-- On upgrade, commands an older copy registered get this copy's handlers.
for name in pairs(lib.commands) do
	SetSlashHandler(name)
end

SLASH_BOLTGRIP1 = "/boltgrip"
SlashCmdList.BOLTGRIP = function(message)
	local name, rest = strtrim(message or ""):match("^(%S*)%s*(.-)$")
	if lib.commands[name:lower()] then
		lib:Dispatch(name:lower(), rest)
		return
	end
	Say(lib.title .. ": /boltgrip <module> <command>")
	for _, module in ipairs(lib.modules) do
		if module.command then
			Say(("  /%s - %s"):format(module.command, module.title))
		end
	end
end
