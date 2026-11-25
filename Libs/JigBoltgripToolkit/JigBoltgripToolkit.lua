-- Shared home for Jig Boltgrip's Toolkit modules. Each module embeds this file; LibStub keeps the newest.
-- One Settings category for the toolkit, one subcategory per installed module.
local MAJOR, MINOR = "JigBoltgripToolkit-1.0", 15
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

-- A voiced line: the mark, "Boltgrip's", the device's name, then what it just did. action is the
-- rest of the sentence, e.g. "deploys a bobber!".
function lib:Say(module, action)
	AddLine(("%s %s %s %s"):format(MARK, PREFIX, DeviceName(module), action))
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

-- A note under an options row: gray, wrapped, in plain words, for what a hover tooltip alone would hide.
-- The template is in JigBoltgripToolkit.xml; the row's height is measured from the text.
local NOTE_WIDTH = 520    -- room for a note beside the options list's left margin
local NOTE_GAP = 8        -- space below a note, before the next row
local measure

function lib:AddNote(layout, text)
	local initializer = Settings.CreateElementInitializer("JigBoltgripToolkitNoteTemplate", { text = text })
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
		frame.Text:SetWidth(NOTE_WIDTH)
		frame.Text:SetText(text)
		frame.Text:SetTextColor(GRAY_FONT_COLOR:GetRGB())
	end
	layout:AddInitializer(initializer)
	return initializer
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
			note = "Prints this addon's commands in your chat window, with what each one does.", run = function()
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
