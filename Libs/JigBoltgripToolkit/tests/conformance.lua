-- Conformance: the rules every toolkit addon follows, checked against the addon's own files, so the addons
-- cannot drift apart. It travels with the library; each addon's checks run it:
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

-- The part of a line people read: all of a doc line, a Lua comment, or a shell comment ("#" opening the line or
-- after a space, so "$#" and "${#x}" never count).
local function Prose(path, line)
	if path:find("%.md$") then return line end
	if path:find("%.lua$") or path:find("%.luacheckrc$") then return line:match("%-%-(.*)$") end
	return line:match("^%s*#(.*)$") or line:match("%s#%s(.*)$")
end

-- Docs and comments are written in one imperative voice, with no attribution of who decided (docs/standards.md,
-- Ethos 7). The patterns match a person named as a source, never an API or log key.
local ATTRIBUTION = { "%f[%a][Oo]wner,%s*%d%d%d%d%-", "%f[%a][Oo]wner:%s*\"", "%(owner[,;%s%)]",
	"%f[%a][Tt]he assistant%f[%A]", "^## Owner's words" }
local function VoiceProblems(path, text)
	local problems, number = {}, 0
	for line in (text .. "\n"):gmatch("(.-)\n") do
		number = number + 1
		local prose = Prose(path, line)
		prose = prose and prose:gsub("`[^`]*`", "") -- a code span names an API, never who decided
		for _, pattern in ipairs(ATTRIBUTION) do
			if prose and prose:find(pattern) then
				problems[#problems + 1] = ("%s line %d: an attribution; write the rule and its reason instead"):format(path, number)
				break
			end
		end
	end
	return problems
end

-- No other addon is cited as a source, model or comparison: an unreleased suite's sources read as copying
-- (docs/decisions/0086). The list holds citing phrases only, since a list of names would itself name them.
-- Docs and comments only; a library's own files, licenses and game strings are exempt.
local SOURCE_PHRASES = { "as another addon", "as other addons", "like another addon", "like other addons",
	"another addon's pattern", "other addons' pattern", "another addon shape", "another addon-style", "another addon style",
	"wording of another addon", "another addon `", "(another addon", "established addon",
	"pattern addons use" }
local SOURCE_EXEMPT = { "^Libs/", "/Libs/", "LICENSE", "THIRD%-PARTY%-NOTICES%.md$", "tests/globalstrings%.lua$" }

-- SHA-256 on plain Lua 5.1 numbers (FIPS 180-4), for the name list below; the client's Lua has no bit library.
local AND = {}
local function Band(a, b)
	if not AND[0] then
		for x = 0, 255 do
			AND[x] = {}
			for y = 0, 255 do
				local value, bit = 0, 1
				for _ = 1, 8 do
					if x % (bit * 2) >= bit and y % (bit * 2) >= bit then value = value + bit end
					bit = bit * 2
				end
				AND[x][y] = value
			end
		end
	end
	local value, scale = 0, 1
	for _ = 1, 4 do
		value = value + AND[a % 256][b % 256] * scale
		a, b, scale = math.floor(a / 256), math.floor(b / 256), scale * 256
	end
	return value
end
local function Bxor(a, b) return a + b - 2 * Band(a, b) end
local function Rotate(x, n) return math.floor(x / 2 ^ n) + (x % 2 ^ n) * 2 ^ (32 - n) end
local ROUND = {}
do
	-- The round constants are the cube roots of the first 64 primes; the start values, the square roots of the first 8.
	local primes, candidate = {}, 2
	while #primes < 64 do
		local prime = true
		for _, p in ipairs(primes) do
			if candidate % p == 0 then prime = false break end
		end
		if prime then primes[#primes + 1] = candidate end
		candidate = candidate + 1
	end
	for index, prime in ipairs(primes) do
		local root = prime ^ (1 / 3)
		ROUND[index] = math.floor((root - math.floor(root)) * 2 ^ 32)
		if index <= 8 then
			root = prime ^ (1 / 2)
			ROUND[-index] = math.floor((root - math.floor(root)) * 2 ^ 32)
		end
	end
end
local function SHA256(text)
	local length = #text
	text = text .. "\128" .. ("\0"):rep((55 - length) % 64) .. ("\0"):rep(4)
		.. string.char(math.floor(length * 8 / 2 ^ 24) % 256, math.floor(length * 8 / 2 ^ 16) % 256, math.floor(length * 8 / 256) % 256, length * 8 % 256)
	local h = { ROUND[-1], ROUND[-2], ROUND[-3], ROUND[-4], ROUND[-5], ROUND[-6], ROUND[-7], ROUND[-8] }
	for block = 1, #text, 64 do
		local w = {}
		for index = 1, 16 do
			local a, b, c, d = text:byte(block + index * 4 - 4, block + index * 4 - 1)
			w[index] = ((a * 256 + b) * 256 + c) * 256 + d
		end
		for index = 17, 64 do
			local x, y = w[index - 15], w[index - 2]
			local s0 = Bxor(Bxor(Rotate(x, 7), Rotate(x, 18)), math.floor(x / 8))
			local s1 = Bxor(Bxor(Rotate(y, 17), Rotate(y, 19)), math.floor(y / 1024))
			w[index] = (w[index - 16] + s0 + w[index - 7] + s1) % 2 ^ 32
		end
		local a, b, c, d, e, f, g, hh = unpack(h)
		for index = 1, 64 do
			local s1 = Bxor(Bxor(Rotate(e, 6), Rotate(e, 11)), Rotate(e, 25))
			local choose = Bxor(Band(e, f), Band(2 ^ 32 - 1 - e, g))
			local first = (hh + s1 + choose + ROUND[index] + w[index]) % 2 ^ 32
			local s0 = Bxor(Bxor(Rotate(a, 2), Rotate(a, 13)), Rotate(a, 22))
			local majority = Bxor(Bxor(Band(a, b), Band(a, c)), Band(b, c))
			hh, g, f, e, d, c, b, a = g, f, e, (d + first) % 2 ^ 32, c, b, a, (first + s0 + majority) % 2 ^ 32
		end
		for index, value in ipairs({ a, b, c, d, e, f, g, hh }) do h[index] = (h[index] + value) % 2 ^ 32 end
	end
	return ("%08x%08x%08x%08x%08x%08x%08x%08x"):format(unpack(h))
end

-- Other addons' names, each as the SHA-256 of the lowercase name with its words joined by one space, so this file
-- names none (docs/decisions/0086). The hashes keep the names out of reading and search; they are not secret.
local NAME_HASHES = {}
for hash in ([[
	049d97909268f7e2791242a35234e8ac978c789ffbc7dcf4505557e6a6e68ac5 06f31ec2dd41c2dfbbf22cd72d19883a288f222c9970e47e4b2a73b057af1e34
	09ee19809ff5b78cc300bbf71c98ca36e48b50750aa25e72b925b6f51ee257eb 1115d079a6dde13be951092ccca1b0cd6cd17bd9435312dbfe44e317154cff49
	204cfa3e56b8a4eb85ef47cbc25cd1a08be320f42d32f496f2c7a616b17ece46 233d9819a36132394a53cbf7341d202e9031eaadc86f33555b74f1fafbe057d2
	27d5b0f312c6bd61d1f4c0da64e27e93e8c9c88856d1796063d188a45563f0aa 2985f231cb9628e11537923f478f945702fd87c8dab6b08bf944a764040ef683
	2a2a3143b07d2833b4c83724ef3d9bfcd6b28269b5ceeb7e84291ce4fbeacf46 2ef56b7bda45db9bfdbb1b12b5316ec584bc6bd1852be7bcfe11344a08c75760
	361e66486b092363bd7e938605a03ad4c78b4942a1754fdfeb27463826e51feb 3cd5681435850a486636e990b1ee055cab044e9ec44efad933e6748882270a8f
	5134273daa5917e79d0b83b85c08419adf83ef549d0dde74b7229ef7d0674b3b 5711b87131f6d33b17d09e56a87ee01455347e5663986e2f806880945e5e7bef
	57b1a687a006f1ebc7596f9209216fde970904952bed289547c2eaef91ec47b6 63dd78e5fe326e058bd03fceb8a8c32f4cfdc44a274a78a2bf543157d921709a
	71b11255f77aa2252ed4c082e63835408db471c65f76767edfb45a1ee36a13da 7831b655a06632832168f81c3106864d203abd6bb358a6dfd7a3491c0ff4b252
	7b820097d038d763d73baaaee657075378ee77d6e04514f113a877d811888084 7f76ae074cd7048d5b09be15cb67b289099924469b69a2419f6baecc19741f75
	815ab6b955cb8e2a6d3be682aa381fe41854390f7d964908e384187dce22dd26 852fd12a233f1cfb7e4dfa4d0e97eb182d1da3f19ec9fb8e96538444c0596e3e
	87f0367f59299d08b54be800a702cd5f7c04af735d084a207561e530c7d48b02 87fc761c97b883d787e1eb9b58983b26c3e23992f3fd130e9d6ac492842f95fa
	883f4e60b533b8f78ee746de6c52a8a2b97bbc6a3896554c8633ddf0db2354c6 91b9524da43ebb23a31f82c2da0874827594544b1394a399419ae86f9a80b0f7
	9f59a2fda44c86d95b540cbf700da5097fa652a98cddcbb20ea2df09f5c82be5 a16ff270fe6c62b3d77f297649c504821a422ecdb8579a812d1f3bb954941f03
	a39ce47df9cd732004d09d9bec2c64b40bb545979aa9751770bbfae873bdce24 a75c0838e8467bc03dcdc6f75c12de9c1f825ffc14c859404e1b13fcf5f27b98
	a81da606ebdac8b2a8dafbf3ebba5938e84841a42285204ecef879f1effa1790 ad2ae59ee4bc7a7a5fcbf88c9b271f75d173298595ad3e386d9318aee85ac4b9
	ade81d9f26fbbdcdae48d8ffa5910f262c89249de272109054641f4ab2cb5547 b021433442a145e1208652e6cb5ddd5a97dd8007b6bf885796a787d9418f4798
	b31bce4721f8db6cac88922f6a339b83e90bfc82f89e0e7503bf70ff7ba6b26c b45abfc4e72ad2e71db0acafba9e67d8a8565dcac2c39471d14cff1950b87a7f
	b758a31c17f7aef3ae9a92a51b53337f796ea11d1b7897e729390d39ff8a2111 c2cb46f8b213d3a1ec17b82b0cecf7f20981b64b1d20400092d5c53754d2cd8a
	c753ef152b5485215d504a7958da9a23cf2f45b6e0c3a2fb8fc77cddc38b1e65 d17486c31fed1b6f07318a671cc4e1f7054e22e8cce0a58e8b576e2ca0c8de83
	d4e519d4a15f96be63cafecc25220c4cd46325ce49be42c85bfa1f3ddbf4bc11 d8bb80e1864cc166c6a7dd2306eda3d71cad874d55d0c82b19c4ce4a252db6d4
	db954643ef2cb8a12c8f5ef1dedcc0a15974be533deda2256f8f567a3e5fdd1d ddb926370d2abc09faa9446108d591008cd0faabba81038c550b89f49396813e
	e6d4b03eed903b1dc2330527606783f463f06fd581dcc02df2fa4e84b5c04e90 e942cbbcdfc6aa5333838c54a0b786553016498c469aabef406c288460f48fdb
	eb291818bbbed4240ebd1f340a2144fcc05b5eea75df123bdb3982a1600faffe eb752349c9f1bd0beccff462ea21a5a0db86a25046994afff026fd10ec45cd55
	ee46c2202b0052a1464e4f8afa104f8ecb52baebb05a86f3379748aad3386d53 f02b372d7499fe41a706a2dda0b5e6bdac04e8f575628d26dff7d8827615dfdd
	fbca8ddfbb47024e4a7638aa5ba0945798787e8314c6ae5c6c048797dd21ccc0 ff92c77e1960727fabc99371621b70a923706d83f002ade254a256e0cb861466
]]):gmatch("%x+") do NAME_HASHES[hash] = true end
-- Each name's length and byte sum: only a word or phrase that matches one is hashed, which keeps a run fast.
local NAME_KEYS = {}
for _, key in ipairs({
	3056, 4188, 5021, 5025, 5047, 6118, 6127, 6140, 6170, 7006, 7008, 7015, 7224, 7234, 7246, 8099,
	8106, 9190, 9202, 9211, 9212, 9214, 9217, 9233, 10010, 10032, 10039, 10047, 10054, 10055, 10070, 10092,
	11067, 11104, 11189, 12024, 13057, 13112, 13123, 13133, 14005, 14096, 14167, 14171, 14172, 14193, 15031, 15116,
	16059, 17157, 18072, 19068,
}) do NAME_KEYS[key] = true end
local NAME_WORDS = 3 -- the longest name, in words
local tried = {}
local function IsName(phrase)
	if tried[phrase] == nil then
		local sum = 0
		for index = 1, #phrase do sum = sum + phrase:byte(index) end
		tried[phrase] = NAME_KEYS[#phrase * 1000 + sum % 251] == true and NAME_HASHES[SHA256(phrase)] == true
	end
	return tried[phrase]
end
-- Whole lines, code included: a name is banned everywhere. Words are runs of letters and digits; a phrase joins up to
-- three that only spaces or hyphens part.
local function NameProblems(path, text)
	local problems, number = {}, 0
	for _, pattern in ipairs(SOURCE_EXEMPT) do
		if path:find(pattern) then return problems end
	end
	for line in (text .. "\n"):gmatch("(.-)\n") do
		number = number + 1
		local words = {}
		for start, word, stop in line:gsub("BigWigs packager", ""):gmatch("()(%w+)()") do
			words[#words + 1] = { word:lower(), start, stop }
		end
		local found
		for first = 1, #words do
			local phrase = words[first][1]
			for last = first, math.min(first + NAME_WORDS - 1, #words) do
				if last > first then
					if not line:gsub("BigWigs packager", ""):sub(words[last - 1][3], words[last][2] - 1):find("^[ %-]+$") then break end
					phrase = phrase .. " " .. words[last][1]
				end
				if IsName(phrase) then found = phrase end
			end
		end
		if found then
			problems[#problems + 1] = ("%s line %d: %q is another addon's name; cite Blizzard's file, game data or our own test")
				:format(path, number, found)
		end
	end
	return problems
end
local function SourceProblems(path, text)
	local problems, number = {}, 0
	for _, pattern in ipairs(SOURCE_EXEMPT) do
		if path:find(pattern) then return problems end
	end
	for line in (text .. "\n"):gmatch("(.-)\n") do
		number = number + 1
		local prose = Prose(path, line)
		prose = prose and prose:gsub("BigWigs packager", "") -- the build tool, named in the release docs
		local found
		for _, phrase in ipairs(prose and SOURCE_PHRASES or {}) do
			if prose:lower():find(phrase, 1, true) then found = phrase break end
		end
		if found then
			problems[#problems + 1] = ("%s line %d: %q cites another addon as a source; cite Blizzard's file, game data or our own test")
				:format(path, number, found)
		end
	end
	return problems
end

if arg[1] == "--voice" then
	local problems = {}
	for i = 2, #arg do
		local text = assert(io.open(arg[i])):read("*a")
		for _, list in ipairs({ VoiceProblems(arg[i], text), SourceProblems(arg[i], text), NameProblems(arg[i], text) }) do
			for _, problem in ipairs(list) do problems[#problems + 1] = problem end
		end
	end
	for _, problem in ipairs(problems) do print("FAIL " .. problem) end
	print(#problems == 0 and "VOICE PASS" or (#problems .. " VOICE PROBLEMS"))
	os.exit(#problems == 0 and 0 or 1)
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
	"MenuUtil%.CreateContextMenu", "SetupMenu", "ShowUIPanel", "HideUIPanel", "OpenWorldMap", "ToggleWorldMap",
	"Settings%.OpenToCategory" }) do
	table.insert(FORBIDDEN, { "%f[%w_]" .. name .. "%f[^%w_]", "taints the Gamepad UI (docs/standards.md, \"Gamepad UI\")",
		inDebug = nil })
end
-- Script text in a macro runs tainted even from a secure button (decision 0068): a macro names a Blizzard slash command.
table.insert(FORBIDDEN, { "[\"']/run%f[%A]", "a script line in a macro runs tainted; name a Blizzard slash command (docs/clean-paths.md)" })
table.insert(FORBIDDEN, { "[\"']/script%f[%A]", "a script line in a macro runs tainted; name a Blizzard slash command (docs/clean-paths.md)" })
table.insert(FORBIDDEN, { "[\"']/dump%f[%A]", "a script line in a macro runs tainted; name a Blizzard slash command (docs/clean-paths.md)" })
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

-- Player text outside working-build blocks goes through the addon's locale table, so it can be translated.
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
	"tests/deploy-deck.sh", "tests/agents-opening.md", "tests/readme-license.md", "tests/deprecated.lua", "tests/globalstrings.lua" }) do
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

local voice = {}
for path in assert(io.popen('git -C "' .. addonDir .. '" ls-files -- "*.md" "*.lua" "*.sh" "scripts/*" ".githooks/*" ":!Libs" 2>/dev/null')):lines() do
	for _, problem in ipairs(VoiceProblems(path, Read(addonDir .. "/" .. path) or "")) do voice[#voice + 1] = problem end
end
check("docs and comments carry no attributions", #voice == 0, table.concat(voice, "; "))

local sources = {}
for path in assert(io.popen('git -C "' .. addonDir .. '" ls-files -- "*.md" "*.lua" ".luacheckrc" "*.sh" "scripts/*" ".githooks/*" ":!Libs" 2>/dev/null')):lines() do
	for _, problem in ipairs(SourceProblems(path, Read(addonDir .. "/" .. path) or "")) do sources[#sources + 1] = problem end
end
check("docs and comments name no other addon as a source", #sources == 0, table.concat(sources, "; "))

local names = {}
for path in assert(io.popen('git -C "' .. addonDir .. '" ls-files -- "*.md" "*.lua" "*.toc" "*.xml" "*.yml" "*.sh" "*.py" ".luacheckrc" ".pkgmeta" "scripts/*" ".githooks/*" ":!Libs" 2>/dev/null')):lines() do
	for _, problem in ipairs(NameProblems(path, Read(addonDir .. "/" .. path) or "")) do names[#names + 1] = problem end
end
check("no tracked file holds another addon's name", #names == 0, table.concat(names, "; "))

-- The repository: the same root files, license text and TOC fields in every module, so none drifts
-- (docs/standards.md, "Repository"). A module with no license file, icon or CI passed every other check.
local missing = {}
for _, file in ipairs({ "LICENSE", "README.md", "AGENTS.md", "CLAUDE.md", ".gitignore", ".editorconfig", ".pkgmeta", ".luacheckrc",
	".busted", ".github/workflows/ci.yml", ".githooks/pre-push", "scripts/check", "scripts/deploy-deck" }) do
	if not Read(addonDir .. "/" .. file) then missing[#missing + 1] = file end
end
check("the repository has every root file", #missing == 0, table.concat(missing, ", "))
local license = Read(addonDir .. "/LICENSE") or ""
check("LICENSE is the GNU General Public License, version 3",
	license:find("GNU GENERAL PUBLIC LICENSE", 1, true) ~= nil and license:find("Version 3, 29 June 2007", 1, true) ~= nil)
local embedsAce = false
for _, file in ipairs(libraries) do embedsAce = embedsAce or file:find("^Libs/Ace") ~= nil or file:find("^Libs/CallbackHandler") ~= nil end
check("an embedded Ace3 library comes with Libs/Ace3-LICENSE.txt", not embedsAce or Read(addonDir .. "/Libs/Ace3-LICENSE.txt") ~= nil)
local fields = {}
for _, field in ipairs({ { "Title", "." }, { "Notes", "." }, { "Author", "." }, { "Category", "^Jig Boltgrip's Toolkit$" },
	{ "Version", "^@project%-version@$" }, { "X-License", "^GPL%-3%.0$" }, { "IconTexture", "." } }) do
	local value = tocText:match("## " .. field[1]:gsub("%-", "%%-") .. ":%s*([^\r\n]*)")
	if not (value and value:find(field[2])) then fields[#fields + 1] = field[1] end
end
check("the TOC has the fields every module sets", #fields == 0, table.concat(fields, ", "))
local workflow = Read(addonDir .. "/.github/workflows/ci.yml") or ""
check("CI calls the toolkit's workflow at one pinned commit",
	workflow:find("uses: seriouslysean/JigBoltgripToolkit/%.github/workflows/module%-ci%.yml@" .. ("%x"):rep(40) .. "%s") ~= nil)
local unpackaged, pkgmeta = {}, Read(addonDir .. "/.pkgmeta") or ""
for _, entry in ipairs({ "AGENTS.md", "CLAUDE.md", "docs", "scripts", "tests", "tools", "Libs/JigBoltgripToolkit/tests" }) do
	if not pkgmeta:find("\n%s*%- " .. entry:gsub("%p", "%%%0") .. "%s*\n") then unpackaged[#unpackaged + 1] = entry end
end
check(".pkgmeta leaves out everything that is not the addon", #unpackaged == 0, table.concat(unpackaged, ", "))
-- One short README shape: what it is, how to install it, the toolkit's license section word for word, and the line
-- that links the toolkit as the main repository.
local readme = Read(addonDir .. "/README.md") or ""
local licenseSection = assert(Read(kitDir .. "/tests/readme-license.md"), "no tests/readme-license.md in the kit")
check("README.md has an Install section", readme:find("\n## Install\n", 1, true) ~= nil)
check("README.md ends with the toolkit's License section", readme:sub(-#licenseSection) == licenseSection,
	"its last section must be the kit's tests/readme-license.md")
check("README.md links the toolkit as the main repository",
	readme:find("Part of [Jig Boltgrip's Toolkit](https://github.com/seriouslysean/JigBoltgripToolkit)", 1, true) ~= nil)
-- The embedded tests folder holds the shared files only: a stray copy is checked by nothing and goes stale.
local shared = { ["stubs.lua"] = true, ["conformance.lua"] = true, ["module-check.sh"] = true, ["deploy-deck.sh"] = true,
	["agents-opening.md"] = true, ["readme-license.md"] = true, ["deprecated.lua"] = true, ["globalstrings.lua"] = true }
local strays = {}
for name in assert(io.popen('ls "' .. kitDir .. '/tests"')):lines() do
	if not shared[name] then strays[#strays + 1] = name end
end
check("the embedded tests folder holds only the toolkit's shared files", #strays == 0, table.concat(strays, ", "))

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

-- Style rules, as standards.md words them ("Plain text", "Options"): WoW-style plain language, simple
-- sentences, no colons in settings text, and short notes.
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
