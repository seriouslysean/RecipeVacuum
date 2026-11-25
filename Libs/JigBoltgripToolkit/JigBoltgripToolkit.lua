-- Shared home for Jig Boltgrip's Toolkit modules. Each module embeds this file; LibStub keeps the newest.
-- One Settings category for the toolkit, one subcategory per installed module.
local MAJOR, MINOR = "JigBoltgripToolkit-1.0", 9
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
-- family reads as one (docs/standards.md, "Voice"). The line color is the one the game gives an NPC's speech.
local MARK = "|TInterface\\WorldMap\\GEAR_64GREY:0|t" -- the world map's gear, at the line's height
local PREFIX = "Boltgrip's"
local DEVICE_COLOR_MIX = 0.6 -- share of a module's own color in its name; the rest is the line color
local BLOCK_INDENT = "    "

local function AddLine(text)
	local color = ChatTypeInfo.MONSTER_SAY
	DEFAULT_CHAT_FRAME:AddMessage(text, color.r, color.g, color.b)
end

-- A module's title in its device color, mixed into the line color so the family stays one tone.
local function DeviceName(module)
	local device, line = module.color, ChatTypeInfo.MONSTER_SAY
	if not device then
		return module.title
	end
	local function Mix(channel)
		return math.floor((line[channel] * (1 - DEVICE_COLOR_MIX) + device[channel] * DEVICE_COLOR_MIX) * 255 + 0.5)
	end
	return ("|cff%02x%02x%02x%s|r"):format(Mix("r"), Mix("g"), Mix("b"), module.title)
end

-- A voiced line: the mark, "Boltgrip's", the device's name, then what it just did. action is the
-- rest of the sentence, e.g. "deploys a bobber!".
function lib:Say(module, action)
	AddLine(("%s %s %s %s"):format(MARK, PREFIX, DeviceName(module), action))
end

-- A plain line with the mark: an error's text, a development command's answer.
function lib:Print(text)
	AddLine(MARK .. " " .. text)
end

-- Several lines that belong together: the header carries the mark, the rows sit under it without one.
function lib:PrintBlock(header, rows)
	self:Print(header)
	for _, row in ipairs(rows) do
		AddLine(BLOCK_INDENT .. row)
	end
end

-- Registers a module by addon folder name; returns its settings category and layout. Call
-- lib:FinishModule(module) after adding the module's rows. color is the device's own color for its
-- name in chat (r, g, b from 0 to 1, as CreateColor gives); without one the name is the line color.
function lib:RegisterModule(addonName, color)
	for _, existing in ipairs(self.modules) do
		if existing.addon == addonName then
			existing.color = color or existing.color
			return existing
		end
	end
	local title = C_AddOns.GetAddOnMetadata(addonName, "Title")
	local notes = C_AddOns.GetAddOnMetadata(addonName, "Notes")
	local parent, parentLayout = self:GetCategory()
	local category, layout = Settings.RegisterVerticalLayoutSubcategory(parent, title)
	local module = { addon = addonName, title = title, notes = notes, category = category, layout = layout, color = color }
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

local function AddEntries(rows, command, troubleshooting)
	local any = false
	for _, entry in ipairs(command.entries) do
		if (entry.troubleshooting or false) == troubleshooting then
			if troubleshooting and not any then
				table.insert(rows, "Troubleshooting:")
			end
			any = true
			local slash = "/" .. command.name .. (entry.action ~= "" and " " .. entry.action or "")
			table.insert(rows, ("%s%s - %s"):format(troubleshooting and "  " or "", slash, entry.description))
		end
	end
end

function lib:PrintHelp(name)
	local command = self.commands[name]
	local rows = {}
	AddEntries(rows, command, false)
	AddEntries(rows, command, true)
	self:PrintBlock(("%s commands (/%s or /boltgrip %s):"):format(command.title, command.name, command.name), rows)
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
	local rows = {}
	for _, module in ipairs(lib.modules) do
		if module.command then
			table.insert(rows, ("/%s - %s"):format(module.command, module.title))
		end
	end
	lib:PrintBlock(lib.title .. ": /boltgrip <module> <command>", rows)
end
