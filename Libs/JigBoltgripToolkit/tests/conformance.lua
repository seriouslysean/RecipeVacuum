-- Conformance: the rules every toolkit addon follows, checked against the addon's own files, so the addons
-- cannot drift apart (owner, 2026-11-25: "lets get some rules baked in to the kit so we don't make this
-- mistake or drift again"). It travels with the library; each addon's checks run it:
--   luajit Libs/JigBoltgripToolkit/tests/conformance.lua <addon folder>
-- Style is checked here, at commit time; the library itself refuses only what would break the page or
-- the line at runtime (docs/standards.md, "Enforced by").
-- Also: luajit conformance.lua --comments <file.lua>, the comment rule alone (the kit's own checks use it).

-- Comments give the reason only: no history, at most three lines a block (docs/standards.md, "Comments").
-- Debug-only blocks are exempt; a packager marker line is not a comment.
local HISTORY = { "20%d%d%-%d%d%-%d%d", "%f[%a][Oo]wner%f[%A]", "%f[%a][Rr]eview%f[%A]", "%f[%a]Astra%f[%A]" }
local COMMENT_LINES = 3
local function CommentProblems(text)
	local problems, open, block, number = {}, false, 0, 0
	for line in (text .. "\n"):gmatch("(.-)\n") do
		number = number + 1
		local marker = line:match("^%s*%-%-@([%a%-]+)@%s*$")
		if marker == "debug" then open = true elseif marker == "end-debug" then open = false end
		local comment = not marker and line:match("%-%-(.*)$")
		if comment and not open then
			for _, pattern in ipairs(HISTORY) do
				if comment:find(pattern) then
					problems[#problems + 1] = ("line %d: a comment carries history; it belongs in docs"):format(number)
					break
				end
			end
		end
		if not open and not marker and line:find("^%s*%-%-") then
			block = block + 1
			if block == COMMENT_LINES + 1 then
				problems[#problems + 1] = ("line %d: a comment block runs past %d lines"):format(number, COMMENT_LINES)
			end
		else
			block = 0
		end
	end
	return problems
end

if arg[1] == "--comments" then
	local problems = CommentProblems(assert(io.open(assert(arg[2])):read("*a")))
	for _, problem in ipairs(problems) do print("FAIL " .. arg[2] .. ": " .. problem) end
	print(#problems == 0 and "COMMENTS PASS" or (#problems .. " COMMENT PROBLEMS"))
	os.exit(#problems == 0 and 0 or 1)
end

local addonDir = assert(arg[1], "usage: luajit conformance.lua <addon folder>")
local kitDir = addonDir .. "/Libs/JigBoltgripToolkit"

local failures = 0
local function check(name, ok, detail)
	print((ok and "PASS " or "FAIL ") .. name .. (not ok and detail and (": " .. detail) or ""))
	if not ok then failures = failures + 1 end
end

local function Read(path)
	local file = io.open(path)
	if not file then return nil end
	local text = file:read("*a")
	file:close()
	return text
end

-- The addon's own files, in load order, from its TOC (the library and other embedded libraries excluded).
local tocPath = assert(io.popen('ls "' .. addonDir .. '"/*.toc')):read("*l")
local addonName = tocPath:match("([^/]+)%.toc$")
local files, libraries = {}, {}
for line in assert(Read(tocPath), "no TOC"):gmatch("[^\r\n]+") do
	local file = line:gsub("\\", "/"):match("^%s*([^#%s][^%s]*)%s*$")
	if file then
		table.insert(file:find("^Libs/") and libraries or files, file)
	end
end

-- 1. What the addon's own files may not do: the kit owns chat, options rows and the working-build setup,
-- and a packager marker stands alone on its line, in pairs (a marker in a comment cut most of the kit
-- out of release builds, MINOR 19 to 24).
local FORBIDDEN = {
	{ "DEFAULT_CHAT_FRAME", "chat goes through the kit (Say, Print)" },
	{ "%f[%w_]print%s*%(", "chat goes through the kit (Say, Print)" },
	{ "Settings%.Create", "options rows are built by the kit (BuildOptions)" },
	{ "CreateSettingsListSectionHeaderInitializer", "options headings are built by the kit (BuildOptions)" },
	{ "SetCVar%(%s*\"scriptErrors\"", "working builds start with the kit's EnableWorkingBuild" },
}
-- Addon code that adds to Blizzard's lists, menus or panels is tainted, and the Gamepad UI then refuses
-- to navigate them (docs/standards.md, "Gamepad UI"). Only the kit builds options, from Blizzard's own rows.
for _, name in ipairs({ "Settings%.CreateDropdown", "Settings%.CreateElementInitializer", "Menu%.ModifyMenu",
	"MenuUtil%.CreateContextMenu", "SetupMenu", "ShowUIPanel", "HideUIPanel",
	"Settings%.OpenToCategory" }) do
	table.insert(FORBIDDEN, { "%f[%w_]" .. name .. "%f[^%w_]", "taints the Gamepad UI (docs/standards.md, \"Gamepad UI\")",
		inDebug = nil })
end
-- No tutorial tips: a pad never shows them, so first-use guidance is a once-only chat line (lib:SayOnce) on every device
-- (decision 0074). HelpTip:Show also writes onto Blizzard's shared pool and taints the action bar in combat.
table.insert(FORBIDDEN, { "%f[%w_]HelpTip", "a tutorial tip; first-use guidance is a once-only chat line (docs/standards.md, \"Voice\")" })
-- A module logs through lib:Trace(module, "event", key, value, ...) only; Log and LogAll take finished lines and are the
-- kit's own (decision 0074).
table.insert(FORBIDDEN, { "toolkit:LogAll?%(", "a log line built by hand; call toolkit:Trace(module, \"event\", key, value, ...)" })
-- A popup shown from addon code activates the Gamepad UI's popup bindings tainted (StaticPopupGamepad.lua, through
-- InputBindingManager), the path that blocks the gamepad interact target. Tell the player in chat instead.
table.insert(FORBIDDEN, { "%f[%w_]StaticPopup_Show%f[^%w_]", "activates the Gamepad UI's popup bindings tainted (docs/standards.md, \"Gamepad UI\")" })
-- The rest of docs/options.md, "Banned controls": each is measured on the Steam Deck or has no module that needs it.
for _, name in ipairs({ "AddShownPredicate", "Settings%.RegisterInitializer", "Settings%.RegisterCanvasLayoutCategory",
	"Settings%.RegisterCanvasLayoutSubcategory", "CreateSettingsCheckboxSliderInitializer",
	"CreateSettingsCheckboxDropdownInitializer", "CreateSettingsExpandableSectionInitializer",
	"CreateSettingsButtonInitializer", "CreateKeybindingEntryInitializer", "SetParentInitializer" }) do
	table.insert(FORBIDDEN, { "%f[%w_]" .. name .. "%f[^%w_]", "a banned control (docs/options.md, \"Banned controls\")" })
end
-- A call to a function only Blizzard's deprecated addons define is nil on a player's client (tests/deprecated.lua).
for name in pairs(assert(dofile(kitDir .. "/tests/deprecated.lua"), "no deprecated list")) do
	table.insert(FORBIDDEN, { "%f[%w_.]" .. name:gsub("%.", "%%.") .. "%f[^%w_]%s*%(",
		"a call to a deprecated shim the client does not load by default (tests/deprecated.lua)" })
end
-- Library names and the addon's own name are written once: Core.lua looks the libraries up and keeps
-- them on the namespace, and the locale files take the addon's name from the TOC.
table.insert(FORBIDDEN, { "[GN][ew][tw]Locale%(%s*\"", "a locale table is named by the addon's name from the TOC, not a string" })

-- Player text outside working-build blocks goes through the addon's locale table, so it can be translated
-- (owner, 2026-11-25: "I want the strings pulled out for localization").
local LITERAL_TEXT = { "%f[%w_]label%s*=%s*\"%a", "%f[%w_]tooltip%s*=%s*\"%a", "%f[%w_]note%s*=%s*\"%a",
	"%f[%w_]description%s*=%s*\"%a", "%f[%w_]heading%s*=%s*\"%a", "%f[%w_]text%s*=%s*\"%a",
	"%f[%w_]noise%s*=%s*\"%a", "%f[%w_]report%s*=%s*\"%a" }
for _, file in ipairs(files) do
	if file:find("%.xml$") then
		check(file .. ": no XML of the addon's own", false, "build frames in Lua on Blizzard's templates")
	else
		local text = Read(addonDir .. "/" .. file) or ""
		local problems, open = {}, false
		local number = 0
		for line in (text .. "\n"):gmatch("(.-)\n") do
			number = number + 1
			local code = line:gsub("%-%-.*$", "")
			for _, rule in ipairs(FORBIDDEN) do
				if code:find(rule[1]) and not (open and rule.inDebug) then
					problems[#problems + 1] = ("line %d: %s"):format(number, rule[2])
				end
			end
			if not open then
				for _, pattern in ipairs(LITERAL_TEXT) do
					if code:find(pattern) then
						problems[#problems + 1] = ("line %d: player text is written in place, not looked up in the locale table"):format(number)
						break
					end
				end
			end
			if line:find("%-%-@[%a%-]+@") then
				local marker = line:match("^%s*%-%-@([%a%-]+)@%s*$")
				if marker == "debug" and not open then
					open = true
				elseif marker == "end-debug" and open then
					open = false
				else
					problems[#problems + 1] = ("line %d: a packager marker must stand alone, in pairs"):format(number)
				end
			end
		end
		if open then problems[#problems + 1] = "a debug block is never closed" end
		check(file .. ": uses the kit for chat, options and working builds", #problems == 0, table.concat(problems, "; "))
		local comments = CommentProblems(text)
		check(file .. ": comments give the reason only", #comments == 0, table.concat(comments, "; "))
	end
end

-- A file-level constant read above its own `local NAME =` line reads the global of that name instead: nil, and the
-- lint cannot see it because reading globals is allowed (113). Found in the kit, 2026-11-27 (MEMORY_SETTLE_SECONDS).
local function ConstantOrder(text)
	local declared, problems, number = {}, {}, 0
	for line in (text .. "\n"):gmatch("(.-)\n") do
		number = number + 1
		local name = line:match("^local%s+([%u][%u%d_]+)%s*=")
		if name and not declared[name] then declared[name] = number end
	end
	number = 0
	for line in (text .. "\n"):gmatch("(.-)\n") do
		number = number + 1
		local code = line:gsub("%-%-.*$", ""):gsub('"[^"]*"', '""')
		for name, at in pairs(declared) do
			if number < at and code:find("%f[%w_]" .. name .. "%f[^%w_]") then
				problems[#problems + 1] = ("line %d reads %s, declared at line %d"):format(number, name, at)
				declared[name] = nil
			end
		end
	end
	return problems
end
for _, file in ipairs(files) do
	if file:find("%.lua$") then
		local problems = ConstantOrder(Read(addonDir .. "/" .. file) or "")
		check(file .. ": constants are declared before they are read", #problems == 0, table.concat(problems, "; "))
	end
end
do
	local problems = ConstantOrder(Read(kitDir .. "/JigBoltgripToolkit.lua") or "")
	check("JigBoltgripToolkit.lua: constants are declared before they are read", #problems == 0, table.concat(problems, "; "))
end

-- Every log line is built by the kit (docs/standards.md, "Working build"): a Trace, Log or LogAll call names its event as a
-- literal of one to three lowercase words and passes its facts as key, value pairs, never a format string or a built line.
local function LogCallProblems(text)
	local problems, code = {}, text:gsub("%-%-[^\n]*", "")
	for position, method in code:gmatch("()[:.](%u%a+)%(") do
		if method == "Trace" or method == "Log" or method == "LogAll" then
			local open = code:find("(", position, true)
			local depth, index, args, current, quote = 0, open + 1, {}, "", nil
			while index <= #code do
				local char = code:sub(index, index)
				if quote then
					current = current .. char
					if char == "\\" then current = current .. code:sub(index + 1, index + 1); index = index + 1
					elseif char == quote then quote = nil end
				elseif char == '"' or char == "'" then
					quote = char; current = current .. char
				elseif char == "(" or char == "{" or char == "[" then
					depth = depth + 1; current = current .. char
				elseif char == ")" or char == "}" or char == "]" then
					if depth == 0 then args[#args + 1] = current break end
					depth = depth - 1; current = current .. char
				elseif char == "," and depth == 0 then
					args[#args + 1] = current; current = ""
				else
					current = current .. char
				end
				index = index + 1
			end
			local event = (args[method == "LogAll" and 1 or 2] or ""):match('^%s*"([^"]*)"%s*$')
			local words = 0
			for word in (event or ""):gmatch("%S+") do words = words + (word:match("^[a-z][a-z0-9]*$") and 1 or 99) end
			if not event or words < 1 or words > 3 then
				local line = select(2, code:sub(1, position):gsub("\n", ""))+ 1
				problems[#problems + 1] = ("line %d: %s needs a literal event of 1 to 3 lowercase words, then key, value pairs"):format(line, method)
			end
		end
	end
	return problems
end
for _, file in ipairs(files) do
	if file:find("%.lua$") then
		local problems = LogCallProblems(Read(addonDir .. "/" .. file) or "")
		check(file .. ": log lines go through the kit's event and pairs", #problems == 0, table.concat(problems, "; "))
	end
end

local kitLookups = 0
for _, file in ipairs(files) do
	kitLookups = kitLookups + select(2, (Read(addonDir .. "/" .. file) or ""):gsub('LibStub%("JigBoltgripToolkit%-1%.0"%)', ""))
end
check("the kit is looked up once and kept on the namespace", kitLookups <= 1, ("%d lookups"):format(kitLookups))

-- Frames that listen for events come from lib:EventFrame, which sets the one OnEvent and counts events for
-- the working-build log inside it (docs/standards.md, "Working build helpers"). A module's own
-- SetScript("OnEvent") on such a frame would drop the count, and WatchEvents is the hook that drop defeats.
local ownDispatch = {}
for _, file in ipairs(files) do
	local text = (Read(addonDir .. "/" .. file) or ""):gsub("%-%-[^\n]*", "")
	if file:find("%.lua$") and (text:find('SetScript%(%s*"OnEvent"') or text:find("WatchEvents%(")) then
		ownDispatch[#ownDispatch + 1] = file
	end
end
check("events are listened for through lib:EventFrame, never SetScript(\"OnEvent\") or WatchEvents", #ownDispatch == 0,
	table.concat(ownDispatch, ", "))

-- The addon's own name comes from the TOC (`local addonName = ...`), never a string, except in a named
-- constant that is a contract (a message prefix, an export format); its saved variables are read in the one
-- file that keeps them on the namespace.
local tocText = Read(tocPath)
local savedNames = {}
for name in (tocText:match("## SavedVariables[%w]*:%s*([^\r\n]+)") or ""):gmatch("[%w_]+") do savedNames[#savedNames + 1] = name end
local nameProblems, savedReaders = {}, {}
for _, file in ipairs(files) do
	if file:find("%.lua$") and not file:find("^Locales/") then
		local number = 0
		for line in ((Read(addonDir .. "/" .. file) or "") .. "\n"):gmatch("(.-)\n") do
			number = number + 1
			local code = line:gsub("%-%-.*$", "")
			if code:find('"' .. addonName, 1, true) and not code:find("^%s*local [%u_]+%s*=") then
				nameProblems[#nameProblems + 1] = ("%s:%d"):format(file, number)
			end
			for _, name in ipairs(savedNames) do
				if code:find("%f[%w_]" .. name .. "%f[^%w_]") then savedReaders[name .. " " .. file] = true end
			end
		end
	end
end
check("the addon's name is taken from the TOC, not written as a string", #nameProblems == 0, table.concat(nameProblems, ", "))
for _, name in ipairs(savedNames) do
	local readers = {}
	for key in pairs(savedReaders) do
		local saved, file = key:match("^(%S+) (.+)$")
		if saved == name then readers[#readers + 1] = file end
	end
	check(("%s is read in one file and kept on the namespace"):format(name), #readers <= 1, table.concat(readers, ", "))
end

-- Translations: every key a language file sets is one the English file has, with the same format
-- arguments, so a translated line can neither go unused nor break a :format call. A file not yet in the
-- TOC is checked the same way (docs/translations.md).
local function Specifiers(text)
	local found = {}
	for spec in text:gmatch("%%%d*%$?[%-%d%.]*([%a%%])") do
		if spec ~= "%" then found[#found + 1] = spec end
	end
	table.sort(found)
	return table.concat(found)
end
local localeDir = addonDir .. "/Locales"
local english = {}
for key in (Read(localeDir .. "/enUS.lua") or ""):gmatch('\nL%["(.-)"%]%s*=%s*true') do english[key] = true end
for path in assert(io.popen('ls "' .. localeDir .. '"/*.lua 2>/dev/null')):lines() do
	local locale = path:match("([^/]+)%.lua$")
	if locale ~= "enUS" then
		local unknown, mismatched = {}, {}
		for line in assert(Read(path)):gmatch("[^\n]+") do
			local key, value = line:match('^L%["(.-)"%]%s*=%s*"(.*)"%s*$')
			if key and not english[key] then
				unknown[#unknown + 1] = key
			elseif key and Specifiers(key) ~= Specifiers(value) then
				mismatched[#mismatched + 1] = key
			end
		end
		check(locale .. ": every key is an English key", #unknown == 0, table.concat(unknown, " | "))
		check(locale .. ": each line keeps its format arguments", #mismatched == 0, table.concat(mismatched, " | "))
	end
end

-- 2. The embedded library: no XML, and the same file as the toolkit's own checkout when one sits beside the addon.
local listing = assert(io.popen('find "' .. kitDir .. '" -name "*.xml"')):read("*a")
check("the embedded kit has no XML", listing == "")
local toolkitCheckout = addonDir .. "/../JigBoltgripToolkit"
for _, file in ipairs({ "JigBoltgripToolkit.lua", "tests/stubs.lua", "tests/conformance.lua", "tests/module-check.sh",
	"tests/deploy-deck.sh", "tests/agents-opening.md", "tests/deprecated.lua", "tests/globalstrings.lua" }) do
	local theirs = Read(toolkitCheckout .. "/" .. file)
	if theirs then
		check("the embedded " .. file .. " is the toolkit's", Read(kitDir .. "/" .. file) == theirs)
	else
		print("SKIP the embedded " .. file .. " against the toolkit: no checkout beside the addon")
	end
end
-- The Deck copy is the kit's for every module, so builds are copied and labeled one way: scripts/deploy-deck is the skeleton's.
local deploy = Read(toolkitCheckout .. "/skeleton/scripts/deploy-deck")
if deploy then
	check("scripts/deploy-deck is the toolkit skeleton's", Read(addonDir .. "/scripts/deploy-deck") == deploy)
end

-- The repository's agent notes open with the toolkit's section, word for word, so every module's
-- agents meet the same rules first: the first "##" section of AGENTS.md is tests/agents-opening.md.
local opening = assert(Read(kitDir .. "/tests/agents-opening.md"), "no tests/agents-opening.md in the kit")
local agents = Read(addonDir .. "/AGENTS.md") or ""
local firstSection = agents:match("\n(## .-)\n## ") or agents:match("\n(## .*)$") or ""
check("AGENTS.md opens with the toolkit's section", firstSection:gsub("%s+$", "") == opening:gsub("%s+$", ""),
	"its first ## section must be the kit's tests/agents-opening.md")

-- 3. Load the addon on the kit's stand-ins and read what it hands the kit.
local client = dofile(kitDir .. "/tests/stubs.lua")
for name in (Read(tocPath):match("## SavedVariables[%w]*:%s*([^\r\n]+)") or ""):gmatch("[%w_]+") do
	client.unset[name] = true
end
-- Globals the libraries and the addon set themselves stay nil until they do (a library checks for an
-- older copy of itself first).
for _, file in ipairs({ unpack(libraries) }) do
	for line in (Read(addonDir .. "/" .. file) or ""):gmatch("[^\n]+") do
		local name = line:match("^_G%.([%a_][%w_]*)%s*=") or line:match("^([%a_][%w_]*)%s*=[^=]")
		if name then client.unset[name] = true end
	end
end
-- The embedded libraries, in the TOC's order (LibStub, the kit, AceComm and so on).
for _, file in ipairs(libraries) do
	if file:find("%.lua$") then dofile(addonDir .. "/" .. file) end
end
local kit = LibStub("JigBoltgripToolkit-1.0")
-- One page and one command table per module: a second call replaces the first, so nothing is checked twice.
local pages, commandTables = {}, {}
local buildOptions, registerCommands = kit.BuildOptions, kit.RegisterCommands
function kit:BuildOptions(module, db, sections)
	pages[module.addon] = sections
	return buildOptions(self, module, db, sections)
end
function kit:RegisterCommands(module, name, entries)
	entries = type(name) == "table" and name or entries
	commandTables[module.addon] = entries
	return registerCommands(self, module, name, entries)
end
local ns = {}
local loaded, problem = pcall(function()
	for _, file in ipairs(files) do
		if file:find("%.lua$") then
			assert(loadfile(addonDir .. "/" .. file))(addonName, ns)
		end
	end
	client.Loaded(addonName)
end)
check("the addon loads on the kit's stand-ins", loaded, tostring(problem))
check("the addon's start-up events run without errors on the stand-ins", #client.errors == 0,
	table.concat(client.errors, "; "))
for _, limit in ipairs(client.standInLimits) do
	print("SKIP a start-up handler needs a number the stand-ins cannot give: " .. limit)
end

-- Style rules, as standards.md words them ("Plain text", "Options"). Owner, 2026-11-25: "wow style plain
-- language, simple sentences", no colons in settings text, and "Your subnotes are also insanely long".
local SMALL_WORDS = { a = true, an = true, ["and"] = true, as = true, at = true, by = true, ["for"] = true,
	["in"] = true, of = true, on = true, ["or"] = true, the = true, to = true }
local NOT_GAME_WORDS = { "addon", "addons", "data", "database", "community", "server", "upload", "sync",
	"author", "export", "record", "recorded", "records" }
local DESCRIPTION_LIMIT = 60 -- a help row fits one chat line beside its command
local NOTE_LIMIT = 120 -- a note is a line or two under its row
local SENTENCE_WORDS = 16 -- a simple sentence

local RULES = {}
function RULES.titleCase(text)
	-- A game slash command (an EMOTEnn_CMD1 string such as "/thank") is the game's own text, lowercase by design.
	if text:find("^/[%l%d_]+$") then return end
	local first = true
	-- A hyphenated name is one word, so a gnomish "-o-" name (Alarm-o-Bot, the game's own) passes on its first letter.
	for word in text:gmatch("[%a'%-]+") do
		if not (word:find("^%u") or (not first and SMALL_WORDS[word])) then return "is not in Title Case" end
		first = false
	end
end
function RULES.oneSentence(text)
	if text:find("[%.!?]%s+%u") then return "is more than one sentence" end
end
function RULES.gameTerms(text)
	local lower = text:lower()
	for _, word in ipairs(NOT_GAME_WORDS) do
		if lower:find("%f[%a]" .. word .. "%f[%A]") then return ("says %q, not a game term"):format(word) end
	end
end
function RULES.plain(text)
	if text:find("[:;]") then return "uses a colon or semicolon" end
	for sentence in text:gmatch("[^%.!?]+") do
		local words = select(2, sentence:gsub("%S+", ""))
		if words > SENTENCE_WORDS then return ("has a sentence of %d words"):format(words) end
	end
end
-- A choice's description in the shape every module's source choices share, so they read alike across modules. The Self
-- Found verb may be the one the module's finds really come from ("the chests you open yourself").
local CHOICE_SHAPES = { "^Tracks only .+ you see for yourself%.$", "^Tracks only .+ you %l+ yourself%.$",
	"^Also tracks what your party, guild and friends find%.$",
	"^Also tracks .+%.$" }
function RULES.choice(text)
	local body = text:gsub("^%a+ range%. ", "", 1)
	for _, shape in ipairs(CHOICE_SHAPES) do
		if body:find(shape) then return end
	end
	return "is not in the source choices' sentence shape"
end
function RULES.note(text)
	if #text > NOTE_LIMIT then return ("is %d characters, over %d"):format(#text, NOTE_LIMIT) end
end
function RULES.description(text)
	if #text > DESCRIPTION_LIMIT then return ("is %d characters, over %d"):format(#text, DESCRIPTION_LIMIT) end
	if text:find("[<%[]") then return "puts arguments in the description, not in usage" end
end

-- Text checked against the named rules. A Blizzard global string (an all-caps name the stand-ins do not
-- define) is Blizzard's own words and passes; anything else that is not a string fails, so no check can
-- loop on a stand-in.
local function Text(what, text, rules)
	if text == nil then return end
	if type(text) == "table" and type(text.stubName) == "string" and text.stubName:find("^[%u_]+$") then
		check(what .. " is Blizzard's own words (" .. text.stubName .. ")", true)
		return
	end
	if type(text) ~= "string" then
		check(what .. " is text", false, "got " .. type(text))
		return
	end
	local problems = {}
	for _, rule in ipairs(rules) do
		local found = RULES[rule](text)
		if found then problems[#problems + 1] = found end
	end
	check(("%s %q"):format(what, text), #problems == 0, table.concat(problems, "; "))
end

local ROW_KINDS = { checkbox = true, choice = true, keybinding = true }
local pageCount, commandCount = 0, 0
for _, sections in pairs(pages) do
	pageCount = pageCount + 1
	for _, section in ipairs(sections) do
		Text("heading", section.heading, { "titleCase", "gameTerms" })
		for _, row in ipairs(section.rows) do
			check(("row kind %q"):format(tostring(row.kind)), ROW_KINDS[row.kind] == true,
				"only checkbox, choice and keybinding rows: BuildOptions builds nothing else, and the kit adds the buttons (docs/options.md, \"Allowed controls\")")
			for _, choice in ipairs(row.kind == "choice" and row.values or {}) do
				if section.place == "sources" then
					Text("choice " .. tostring(choice.label), choice.description, { "gameTerms", "plain", "choice" })
				else
					Text("choice " .. tostring(choice.label), choice.description, { "gameTerms", "plain" })
				end
			end
			Text("label", row.label, { "titleCase", "gameTerms", "plain" })
			Text("tooltip", row.tooltip, { "oneSentence", "gameTerms", "plain" })
			Text("note", row.note, { "gameTerms", "plain", "note" })
		end
	end
end
for _, entries in pairs(commandTables) do
	commandCount = commandCount + 1
	for _, entry in ipairs(entries) do
		if entry.troubleshooting then
			Text("troubleshooting command " .. tostring(entry.action), entry.description, { "description" })
		else
			Text("command " .. tostring(entry.action), entry.description, { "description", "gameTerms", "plain" })
			Text("note under command " .. tostring(entry.action), entry.note, { "gameTerms", "plain", "note" })
		end
	end
end

-- docs/options.md, "Checks": one line per rule, naming the rule and each page row that breaks it.
local function Str(value) return type(value) == "string" and value or nil end
local function Words(text) return select(2, text:gsub("%S+", "")) end
local function Flag(list, row, why) list[#list + 1] = ("%q %s"):format(row, why) end
-- A section whose heading is not in the locale file is a working-build test page (its text is written in place inside
-- --@debug@ blocks, which releases drop), so the release rules skip it.
local function Released(section)
	local heading = Str(section.heading)
	return not heading or english[heading] == true
end
local OPENINGS = { "Check this", "If enabled", "When checked", "Enable this option" }
-- Each test gets (row, section, index of the row, list of problems, row name) and adds to the list.
local OPTION_RULES = {
	{ "Labels 2: a label has five words or fewer", function(row, _, _, found, name)
		local label = Str(row.label)
		if label and Words(label) > 5 then Flag(found, name, "has " .. Words(label) .. " words") end
	end },
	{ "Labels 4: a label has no colon and no end punctuation", function(row, _, _, found, name)
		local label = Str(row.label)
		if label and (label:find("[:;]") or label:find("[%.!?,]$")) then Flag(found, name, "has a colon or end punctuation") end
	end },
	{ "Labels 8: a label differs from its heading", function(row, section, _, found, name)
		if Str(row.label) and row.label == Str(section.heading) then Flag(found, name, "is its heading's name") end
	end },
	{ "Headings 1: a heading has three words or fewer", function(_, section, index, found)
		local heading = Str(section.heading)
		if index == 1 and heading and Words(heading) > 3 then Flag(found, heading, "has " .. Words(heading) .. " words") end
	end },
	{ "Labels 10: a stop name has four words or fewer, in Title Case", function(row, _, _, found, name)
		for _, stop in ipairs(row.kind == "choice" and row.values or {}) do
			local label = Str(stop.label)
			if label and (Words(label) > 4 or RULES.titleCase(label)) then Flag(found, name, ("stop %q is over 4 words or not Title Case"):format(label)) end
		end
	end },
	{ "Allowed controls: a choice has 2 to 5 stops", function(row, _, _, found, name)
		if row.kind == "choice" and (#row.values < 2 or #row.values > 5) then Flag(found, name, "has " .. #row.values .. " stops") end
	end },
	{ "Tooltips 10: on one choice every stop has a description or none does", function(row, _, _, found, name)
		local described = 0
		for _, stop in ipairs(row.kind == "choice" and row.values or {}) do
			if stop.description then described = described + 1 end
		end
		if described > 0 and described < #row.values then Flag(found, name, "describes only some stops") end
	end },
	{ "Tooltips 1: a checkbox has a tooltip; a choice has a tooltip or a description on every stop", function(row, _, _, found, name)
		if row.kind == "checkbox" and not row.tooltip then Flag(found, name, "has no tooltip") end
		if row.kind == "choice" and not row.tooltip then
			for _, stop in ipairs(row.values) do
				if not stop.description then Flag(found, name, "has no tooltip and a stop without a description") return end
			end
		end
	end },
	{ "Tooltips 3, 4: a tooltip is 120 characters or fewer, starts with a capital and ends with a period", function(row, _, _, found, name)
		local tooltip = Str(row.tooltip)
		if tooltip and (#tooltip > 120 or not tooltip:find("^%u") or not tooltip:find("%.$")) then
			Flag(found, name, "is over 120 characters, or does not start with a capital and end with a period")
		end
	end },
	{ "Tooltips 6: a choice tooltip starts with \"Choose\"", function(row, _, _, found, name)
		local tooltip = Str(row.tooltip)
		if row.kind == "choice" and tooltip and not tooltip:find("^Choose%f[%A]") then Flag(found, name, "does not start with \"Choose\"") end
	end },
	{ "Tooltips 7: a tooltip does not open with \"Check this\", \"If enabled\", \"When checked\" or \"Enable this option\"", function(row, _, _, found, name)
		for _, phrase in ipairs(OPENINGS) do
			if Str(row.tooltip) and row.tooltip:find("^" .. phrase) then Flag(found, name, "opens with " .. phrase) end
		end
	end },
	{ "Tooltips 9: a tooltip and a note never state the default", function(row, _, _, found, name)
		for _, text in ipairs({ Str(row.tooltip) or "", Str(row.note) or "" }) do
			if text:lower():find("%f[%a]default") then Flag(found, name, "says \"default\"") end
		end
	end },
	{ "Tooltips: a tooltip does not start with its own label", function(row, _, _, found, name)
		local label, tooltip = Str(row.label), Str(row.tooltip)
		if label and tooltip and tooltip:lower():find("^" .. label:lower():gsub("%p", "%%%0") .. "%f[%A]") then
			Flag(found, name, "starts with its label")
		end
	end },
	{ "Labels 6: no text says tick, ticked or untick", function(row, section, index, found, name)
		local texts = { row.label, row.tooltip, row.note, index == 1 and section.heading or nil }
		for _, stop in ipairs(row.kind == "choice" and row.values or {}) do
			texts[#texts + 1] = stop.label
			texts[#texts + 1] = stop.description
		end
		for _, text in pairs(texts) do
			if Str(text) and text:lower():find("%f[%a]un?tick") then Flag(found, name, "says \"tick\"; a box is checked") end
		end
	end },
	{ "Notes 3: a note is one sentence", function(row, _, _, found, name)
		if Str(row.note) and RULES.oneSentence(row.note) then Flag(found, name, "has a note of more than one sentence") end
	end },
	{ "Notes 5: a keybinding row has no note or tooltip", function(row, _, _, found, name)
		if row.kind == "keybinding" and (row.note or row.tooltip) then Flag(found, name, "has a note or tooltip the row never shows") end
	end },
	{ "Dependent settings 2: a row with under follows its parent or a sibling in the same section", function(row, section, _, found, name)
		if not row.under then return end
		local parent
		for position, other in ipairs(section.rows) do
			if other.key == row.under then parent = position end
			if other == row then
				if not parent then Flag(found, name, "has its parent in another section or below it") return end
				for between = parent + 1, position - 1 do
					if section.rows[between].under ~= row.under then Flag(found, name, "is separated from its parent") return end
				end
			end
		end
	end },
	{ "Defaults 1: a checkbox and a choice have a default", function(row, _, _, found, name)
		if (row.kind == "checkbox" or row.kind == "choice") and row.default == nil then Flag(found, name, "has no default") end
	end },
}
for _, rule in ipairs(OPTION_RULES) do
	local found = {}
	for addon, sections in pairs(pages) do
		for _, section in ipairs(sections) do
			for index, row in ipairs(Released(section) and section.rows or {}) do
				local before = #found
				rule[2](row, section, index, found, tostring(Str(row.label) or row.key or row.binding))
				for at = before + 1, #found do found[at] = addon .. " " .. found[at] end
			end
		end
	end
	check(rule[1], #found == 0, table.concat(found, "; "))
end
do
	local found = {}
	for addon, sections in pairs(pages) do
		local seen = {}
		for _, section in ipairs(sections) do
			for _, row in ipairs(Released(section) and section.rows or {}) do
				local label = Str(row.label)
				if label and seen[label] then Flag(found, addon .. " " .. label, "is used twice on a page") end
				if label then seen[label] = true end
			end
		end
	end
	check("Labels 8: a label is used once on a page", #found == 0, table.concat(found, "; "))
end

-- Nothing to check is a failure, not a pass: the page and commands must have been reached.
check("the addon's options page was built", pageCount > 0, "BuildOptions never ran on the stand-ins")
check("the addon's commands were registered", commandCount > 0, "RegisterCommands never ran on the stand-ins")

-- Voiced lines: every { noise = , report = } table the addon keeps.
local function VoicedLines(t, seen, found)
	if seen[t] then return end
	seen[t] = true
	if type(t.noise) == "string" and type(t.report) == "string" then found[#found + 1] = t end
	for _, value in pairs(t) do
		if type(value) == "table" and getmetatable(value) == nil then VoicedLines(value, seen, found) end
	end
end
local voiced = {}
VoicedLines(ns, {}, voiced)
local speaks = false
for _, file in ipairs(files) do
	speaks = speaks or (Read(addonDir .. "/" .. file) or ""):find(":Say%(") ~= nil
end
check("the addon's voiced lines were found", not speaks or #voiced > 0,
	"it calls Say, but keeps no { noise = , report = } table in its namespace")
for _, line in ipairs(voiced) do
	Text("voiced line", line.noise .. ". " .. line.report, { "gameTerms" })
	check(("voiced %q: noise without an end mark, report in beats ending \"!\""):format(line.noise),
		not line.noise:find("[%.!?]$") and line.report:find("!$") ~= nil)
end

print(failures == 0 and "ALL CONFORMANCE CHECKS PASSED" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
