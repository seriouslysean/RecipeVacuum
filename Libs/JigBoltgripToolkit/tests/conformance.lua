-- Conformance: the rules every toolkit addon follows, checked against the addon's own files, so the addons
-- cannot drift apart (owner, 2026-11-25: "lets get some rules baked in to the kit so we don't make this
-- mistake or drift again"). It travels with the library; each addon's checks run it:
--   luajit Libs/JigBoltgripToolkit/tests/conformance.lua <addon folder>
-- Style is checked here, at commit time; the library itself refuses only what would break the page or
-- the line at runtime (docs/standards.md, "Enforced by").
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
				if code:find(rule[1]) then problems[#problems + 1] = ("line %d: %s"):format(number, rule[2]) end
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
	end
end

-- 2. The embedded library: no XML, and the same file as the toolkit's own checkout when one sits beside the addon.
local listing = assert(io.popen('find "' .. kitDir .. '" -name "*.xml"')):read("*a")
check("the embedded kit has no XML", listing == "")
local toolkitCheckout = addonDir .. "/../JigBoltgripToolkit"
for _, file in ipairs({ "JigBoltgripToolkit.lua", "tests/stubs.lua", "tests/conformance.lua" }) do
	local theirs = Read(toolkitCheckout .. "/" .. file)
	if theirs then
		check("the embedded " .. file .. " is the toolkit's", Read(kitDir .. "/" .. file) == theirs)
	else
		print("SKIP the embedded " .. file .. " against the toolkit: no checkout beside the addon")
	end
end

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
local pages, commandTables = {}, {}
local buildOptions, registerCommands = kit.BuildOptions, kit.RegisterCommands
function kit:BuildOptions(module, db, sections)
	pages[#pages + 1] = sections
	return buildOptions(self, module, db, sections)
end
function kit:RegisterCommands(module, name, entries)
	commandTables[#commandTables + 1] = entries
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

-- Style rules, as standards.md words them.
local SMALL_WORDS = { a = true, an = true, ["and"] = true, as = true, at = true, by = true, ["for"] = true,
	["in"] = true, of = true, on = true, ["or"] = true, the = true, to = true }
local function TitleCase(text)
	local first = true
	for word in text:gmatch("[%a']+") do
		if not (word:find("^%u") or (not first and SMALL_WORDS[word])) then return false end
		first = false
	end
	return true
end
local function OneSentence(text)
	return not text:find("[%.!?]%s+%u")
end
local NOT_GAME_WORDS = { "addon", "addons", "data", "database", "community", "server", "upload", "sync",
	"author", "export", "record", "recorded", "records" }
-- Player text speaks in game terms: the exact game thing, never the addon's machinery (owner, 2026-11-25:
-- "please be specific, and stick to game terms, just like our bot/device language").
local function GameTerms(what, text)
	if not text then return end
	local lower, word = text:lower(), nil
	for _, candidate in ipairs(NOT_GAME_WORDS) do
		if lower:find("%f[%a]" .. candidate .. "%f[%A]") then word = candidate end
	end
	check(what .. " speaks in game terms", word == nil, word and ("says \"" .. word .. "\""))
end
local DESCRIPTION_LIMIT = 60 -- a help row fits one chat line beside its command

for _, sections in ipairs(pages) do
	for _, section in ipairs(sections) do
		check(("heading %q is in Title Case"):format(section.heading), TitleCase(section.heading))
		for _, row in ipairs(section.rows) do
			for _, card in ipairs(row.kind == "cards" and row.values or {}) do
				GameTerms("card " .. tostring(card[2]), card[4])
			end
			GameTerms("label " .. tostring(row.label), row.label)
			GameTerms("tooltip of " .. tostring(row.label), row.tooltip)
			GameTerms("note under " .. tostring(row.label), row.note)
			if row.label then check(("label %q is in Title Case"):format(row.label), TitleCase(row.label)) end
			if row.tooltip then check(("tooltip of %q is one sentence"):format(row.label or "?"), OneSentence(row.tooltip)) end
		end
	end
end
for _, entries in ipairs(commandTables) do
	for _, entry in ipairs(entries) do
		local description = entry.description or ""
		if not entry.troubleshooting then
			GameTerms(("command %q"):format(entry.action), description)
			GameTerms(("note under command %q"):format(entry.action), entry.note)
		end
		check(("command %q: description is short, arguments in usage"):format(entry.action),
			#description <= DESCRIPTION_LIMIT and not description:find("[<%[]"))
	end
end

-- Voiced lines: every { noise, report } table the addon keeps.
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
for _, line in ipairs(voiced) do
	GameTerms(("voiced %q"):format(line.noise), line.noise .. " " .. line.report)
	check(("voiced %q: noise without an end mark, report in beats ending \"!\""):format(line.noise),
		not line.noise:find("[%.!?]$") and line.report:find("!$") ~= nil)
end

print(failures == 0 and "ALL CONFORMANCE CHECKS PASSED" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
