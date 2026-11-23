-- Developer commands, loaded only in development builds (see the #@debug@ block in the TOC).
-- /boltgrip recipevacuum dump prints what the client knows about one unlearned recipe of the open profession.
-- /boltgrip recipevacuum preview shows each source icon on unlearned rows, to check the layout.
local _, ns = ...

-- Every line a developer command prints is also kept in RecipeVacuumDB.devLog (readable from
-- the saved variables file after a /reload) and shown in a copyable popup.
local logFrame
local openStarted, openMs
local timing = CreateFrame("Frame")
timing:RegisterEvent("TRADE_SKILL_SHOW")
timing:RegisterEvent("TRADE_SKILL_CLOSE")
timing:SetScript("OnEvent", function(_, event)
	if event == "TRADE_SKILL_SHOW" then
		openStarted, openMs = debugprofilestop(), nil
	else
		openStarted = nil
	end
end)
EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
	hooksecurefunc(ProfessionsFrame.CraftingPage, "Init", function()
		if openStarted and C_TradeSkillUI.IsTradeSkillReady() then
			openMs, openStarted = debugprofilestop() - openStarted, nil
		end
	end)
end)

local function GetLogFrame()
	if logFrame then
		return logFrame
	end
	logFrame = CreateFrame("Frame", "RecipeVacuumDevLogFrame", UIParent, "BasicFrameTemplateWithInset")
	logFrame:SetSize(640, 420)
	logFrame:SetPoint("CENTER")
	logFrame:SetFrameStrata("DIALOG")
	logFrame:SetMovable(true)
	logFrame:EnableMouse(true)
	logFrame:RegisterForDrag("LeftButton")
	logFrame:SetScript("OnDragStart", logFrame.StartMoving)
	logFrame:SetScript("OnDragStop", logFrame.StopMovingOrSizing)
	local title = logFrame.TitleText or logFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", 0, -5)
	title:SetText("Recipe Vacuum: select all, then copy")
	table.insert(UISpecialFrames, logFrame:GetName()) -- Escape closes it, like Blizzard's panels

	logFrame.ScrollingEditBox = CreateFrame("Frame", nil, logFrame, "ScrollingEditBoxTemplate")
	logFrame.ScrollingEditBox:SetPoint("TOPLEFT", 14, -32)
	logFrame.ScrollingEditBox:SetPoint("BOTTOMRIGHT", -30, 12)
	logFrame.ScrollBar = CreateFrame("EventFrame", nil, logFrame, "MinimalScrollBar")
	logFrame.ScrollBar:SetPoint("TOPLEFT", logFrame.ScrollingEditBox, "TOPRIGHT", 6, 0)
	logFrame.ScrollBar:SetPoint("BOTTOMLEFT", logFrame.ScrollingEditBox, "BOTTOMRIGHT", 6, 0)
	ScrollUtil.RegisterScrollBoxWithScrollBar(logFrame.ScrollingEditBox:GetScrollBox(), logFrame.ScrollBar)
	-- The text opens selected, so the box has focus and takes Escape; close the popup then.
	logFrame.ScrollingEditBox:GetEditBox():HookScript("OnEscapePressed", function()
		logFrame:Hide()
	end)
	return logFrame
end

local function ShowLog()
	local frame = GetLogFrame()
	frame.ScrollingEditBox:SetText(table.concat(ns.db.devLog or {}, "\n"))
	frame:Show()
	local editBox = frame.ScrollingEditBox:GetEditBox()
	editBox:SetFocus()
	editBox:HighlightText()
end

local function print(...)
	local line = strjoin(" ", tostringall(...))
	ns.db.devLog = ns.db.devLog or {}
	table.insert(ns.db.devLog, line)
	_G.print(line)
	if logFrame and logFrame:IsShown() then
		ShowLog()
	end
end

local function Dump()
	if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then
		print("Recipe Vacuum: open a profession first.")
		return
	end

	local recipeID
	for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs()) do
		local info = C_TradeSkillUI.GetRecipeInfo(id)
		if info and not info.learned then
			recipeID = id
			break
		end
	end
	if not recipeID then
		print("Recipe Vacuum: no unlearned recipes in this profession.")
		return
	end

	local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
	print(("Recipe Vacuum: %d %s"):format(recipeID, info.name or "?"))
	local keys = {}
	for key in pairs(info) do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		if type(info[key]) ~= "table" then
			print("  " .. key .. " = " .. tostring(info[key]))
		end
	end
	-- Wrapped in parentheses: on Forever the call returns no value at all, which tostring rejects.
	print("  sourceText = " .. tostring((C_TradeSkillUI.GetRecipeSourceText(recipeID))))

	-- How many of this profession's unlearned recipes carry each sourceType.
	local professionID = Professions.GetProfessionInfo().professionID
	local counts, total = {}, 0
	for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs()) do
		local recipe = C_TradeSkillUI.GetRecipeInfo(id)
		if recipe and not recipe.learned and C_TradeSkillUI.IsRecipeInSkillLine(id, professionID) then
			local key = recipe.sourceType and ((_G["BATTLE_PET_SOURCE_" .. recipe.sourceType] or "?") .. " (" .. recipe.sourceType .. ")") or "none"
			counts[key] = (counts[key] or 0) + 1
			total = total + 1
		end
	end
	local parts = {}
	for key, count in pairs(counts) do
		table.insert(parts, key .. ": " .. count)
	end
	table.sort(parts)
	print(("  sourceType across %d unlearned: %s"):format(total, table.concat(parts, ", ")))

	local fromSources = {}
	for index = 1, C_PetJournal.GetNumPetSources() do
		if C_TradeSkillUI.IsAnyRecipeFromSource(index) then
			table.insert(fromSources, (_G["BATTLE_PET_SOURCE_" .. index] or "?") .. " (" .. index .. ")")
		end
	end
	print("  sources with recipes: " .. (#fromSources > 0 and table.concat(fromSources, ", ") or "none"))
end

-- Saves the full unlearned list to the saved variables, so it can be read outside the game.
local function SaveProbe(professionID, unlearned)
	ns.db.probe = ns.db.probe or {}
	local rows = {}
	for _, info in ipairs(unlearned) do
		local category = info.categoryID and C_TradeSkillUI.GetCategoryInfo(info.categoryID)
		table.insert(rows, ("%d|%s|%s|%s"):format(info.recipeID, info.name, category and category.name or "", tostring(info.disabled)))
	end
	ns.db.probe[professionID] = rows
	print("Recipe Vacuum: saved " .. #rows .. " rows; /reload to write them to disk.")
end

-- Counts what the filtered list holds, then turns Show Unlearned on and counts again.
local function Probe()
	if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then
		print("Recipe Vacuum: open a profession first.")
		return
	end
	local professionID = Professions.GetProfessionInfo().professionID
	local function Count(label)
		local total, unlearned, inLine = 0, 0, 0
		for _, id in ipairs(C_TradeSkillUI.GetFilteredRecipeIDs()) do
			total = total + 1
			local info = C_TradeSkillUI.GetRecipeInfo(id)
			if info and not info.learned then
				unlearned = unlearned + 1
				if C_TradeSkillUI.IsRecipeInSkillLine(id, professionID) then
					inLine = inLine + 1
				end
			end
		end
		print(("Recipe Vacuum %s: showUnlearned=%s filtered=%d unlearned=%d unlearnedInThisProfession=%d"):format(
			label, tostring(C_TradeSkillUI.GetShowUnlearned()), total, unlearned, inLine))
	end
	Count("now")

	-- What the full list holds for this profession, beyond the filter.
	local unlearned = {}
	for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs()) do
		local info = C_TradeSkillUI.GetRecipeInfo(id)
		if info and not info.learned and C_TradeSkillUI.IsRecipeInSkillLine(id, professionID) then
			table.insert(unlearned, info)
		end
	end
	print(("Recipe Vacuum all: unlearnedInThisProfession=%d"):format(#unlearned))
	table.sort(unlearned, function(a, b) return a.name < b.name end)
	for i, info in ipairs(unlearned) do
		if i > 12 then
			break
		end
		local category = info.categoryID and C_TradeSkillUI.GetCategoryInfo(info.categoryID)
		print(("  %d %s [%s]"):format(info.recipeID, info.name, category and category.name or "no category"))
	end
	SaveProbe(professionID, unlearned)
end

-- Checks whether Forever allows addon messages on a custom chat channel (Classic blocks them):
-- joins a temporary channel, sends one message to it, and reports the result and any echo.
local CHANNEL_TEST_NAME = "BoltgripChannelTest"
local CHANNEL_TEST_PREFIX = "BoltgripTest"

local function ChannelTest()
	C_ChatInfo.RegisterAddonMessagePrefix(CHANNEL_TEST_PREFIX)
	JoinTemporaryChannel(CHANNEL_TEST_NAME)

	local listener = CreateFrame("Frame")
	listener:RegisterEvent("CHAT_MSG_ADDON")
	listener:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
		if prefix == CHANNEL_TEST_PREFIX then
			print(("Recipe Vacuum: received %q on %s from %s"):format(message, channel, sender))
		end
	end)

	C_Timer.After(2, function()
		local channelID = GetChannelName(CHANNEL_TEST_NAME)
		if channelID == 0 then
			listener:UnregisterAllEvents()
			print("Recipe Vacuum: could not join the test channel.")
			return
		end
		local result = C_ChatInfo.SendAddonMessage(CHANNEL_TEST_PREFIX, "ping", "CHANNEL", tostring(channelID))
		local resultName = "?"
		for name, value in pairs(Enum.SendAddonMessageResult) do
			if value == result then
				resultName = name
			end
		end
		print(("Recipe Vacuum: sent on channel %d, result %s (%s)"):format(channelID, tostring(result), resultName))
		C_Timer.After(3, function()
			listener:UnregisterAllEvents()
			LeaveChannelByName(CHANNEL_TEST_NAME)
			print("Recipe Vacuum: channel test done; left the test channel.")
		end)
	end)
end

-- For each unlearned recipe that shares a name with a learned one in the open profession,
-- logs what the client says about both, to find an ID-based way to tell variants apart.
local function Dupes()
	if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then
		print("Recipe Vacuum: open a profession first.")
		return
	end
	local professionID = Professions.GetProfessionInfo().professionID
	local byName = {}
	for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs()) do
		local info = C_TradeSkillUI.GetRecipeInfo(id)
		if info and C_TradeSkillUI.IsRecipeInSkillLine(id, professionID) then
			byName[info.name] = byName[info.name] or {}
			table.insert(byName[info.name], info)
		end
	end
	print("Recipe Vacuum: player faction " .. tostring((UnitFactionGroup("player"))))
	local pairsFound = 0
	for name, infos in pairs(byName) do
		local hasLearned = false
		for _, info in ipairs(infos) do
			hasLearned = hasLearned or info.learned
		end
		if #infos > 1 and hasLearned then
			pairsFound = pairsFound + 1
			for _, info in ipairs(infos) do
				local schematic = C_TradeSkillUI.GetRecipeSchematic(info.recipeID, false)
				local requirements = C_TradeSkillUI.GetRecipeRequirements(info.recipeID)
				print(("  %s | id %d | learned %s | ability %d | output %s | factionOutput %s | trivial %d | category %d | requirements %d"):format(
					name, info.recipeID, tostring(info.learned), info.skillLineAbilityID,
					tostring(schematic and schematic.outputItemID),
					tostring((C_TradeSkillUI.GetFactionSpecificOutputItem(info.recipeID))),
					info.maxTrivialLevel, info.categoryID, requirements and #requirements or 0))
				-- Tooltip lines with their type: Enum.TooltipDataLineType.UsageRequirement (43) with
				-- requirementType Faction (1) would name the faction.
				local outputItemID = schematic and schematic.outputItemID
				local tooltips = {
					item = outputItemID and C_TooltipInfo.GetItemByID(outputItemID),
					spell = C_TooltipInfo.GetSpellByID(info.recipeID),
				}
				for kind, tooltip in pairs(tooltips) do
					for lineIndex, line in ipairs(tooltip and tooltip.lines or {}) do
						print(("    %s line %d: type %s requirement %s | %s"):format(kind, lineIndex,
							tostring(line.type), tostring(line.requirementType), tostring(line.leftText)))
					end
				end
				print(("    professionLearned %s | disabledReason %s"):format(
					tostring(C_TradeSkillUI.IsRecipeProfessionLearned(info.recipeID)), tostring(info.disabledReason)))
			end
		end
	end
	print(("Recipe Vacuum: %d same-name groups with a learned recipe."):format(pairsFound))
end

-- Lists the requirement lines on the open profession's unlearned recipes, grouped by
-- requirement type, to see how Forever marks recipes a character can never learn (another
-- faction, an engineering or other specialization) versus ones it can reach later.
local function Requirements()
	if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then
		print("Recipe Vacuum: open a profession first.")
		return
	end
	local professionID = Professions.GetProfessionInfo().professionID
	local seen, count = {}, 0
	for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs()) do
		local info = C_TradeSkillUI.GetRecipeInfo(id)
		if info and not info.learned and C_TradeSkillUI.IsRecipeInSkillLine(id, professionID) then
			local tooltip = C_TooltipInfo.GetSpellByID(id)
			for _, line in ipairs(tooltip and tooltip.lines or {}) do
				if line.type == Enum.TooltipDataLineType.UsageRequirement and line.leftText then
					local color = line.leftColor and line.leftColor:GenerateHexColor() or "?"
					local key = tostring(line.requirementType) .. "|" .. line.leftText:gsub("%d+", "#") .. "|" .. color
					if not seen[key] then
						seen[key] = true
						count = count + 1
						print(("  requirementType %s | color %s | %s | e.g. %d %s"):format(
							tostring(line.requirementType), color, line.leftText, id, info.name))
					end
				end
			end
		end
	end
	print(("Recipe Vacuum: %d distinct requirement lines."):format(count))
end

-- Sizes of the account's firsthand finds as one export, to decide whether sharing needs
-- paging or can send everything in one compressed message (the another addon pattern).
local function ExportSize()
	local rows = ns.FindsSince(0, math.huge)
	local json = C_EncodingUtil.SerializeJSON(rows)
	local cbor = C_EncodingUtil.SerializeCBOR(rows)
	local deflated = C_EncodingUtil.CompressString(cbor, Enum.CompressionMethod.Deflate)
	local encoded = C_EncodingUtil.EncodeBase64(deflated)
	print(("Recipe Vacuum: %d shareable finds | JSON %d bytes | CBOR %d | Deflate %d | Base64 %d | ~%d addon messages of 255 bytes"):format(
		#rows, #json, #cbor, #deflated, #encoded, math.ceil(#encoded / 250)))
end

-- One-shot checks for the next build steps (research report, "Consolidated in-game tests"):
-- saved data after the upgrade, Blizzard atlases we use, and which APIs Forever exposes.
local function Checks()
	local db = ns.db
	print(("schema %s | revision %s | pending trainer names %d | pending items %d"):format(
		tostring(db.schema), tostring(db.exchange and db.exchange.revision),
		CountTable(db.found.trainerNames), CountTable(db.pendingItems)))
	for _, atlas in ipairs({ "bags-junkcoin", "common-search-magnifyingglass", "common-icon-redx" }) do
		print(("atlas %s: %s"):format(atlas, C_Texture.GetAtlasInfo(atlas) and "present" or "MISSING"))
	end
	for _, name in ipairs({ "GetLootSourceInfo", "IsFishingLoot", "GetQuestItemInfo", "issecretvalue" }) do
		print(("%s: %s"):format(name, type(_G[name])))
	end
	print("C_Item.GetItemSpell:", type(C_Item.GetItemSpell), "| C_Map.OpenWorldMap:", type(C_Map.OpenWorldMap),
		"| C_SuperTrack.SetSuperTrackedUserWaypoint:", type(C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint))
	local mapID = C_Map.GetBestMapForUnit("player")
	print("map", tostring(mapID), "| CanSetUserWaypointOnMap:", tostring(mapID and C_Map.CanSetUserWaypointOnMap(mapID)),
		"| colorblindMode:", GetCVar("colorblindMode"))
	-- Locale-independent recipe item link: does the item expose its recipe?
	local itemID = next(db.itemRecipe) or next(db.pendingItems)
	if itemID then
		print(("recipe item %d (links to recipe %s):"):format(itemID, tostring(db.itemRecipe[itemID])))
		print("  C_Item.GetItemSpell:", C_Item.GetItemSpell and strjoin(" ", tostringall(C_Item.GetItemSpell(itemID))) or "n/a")
		local tooltip = C_TooltipInfo.GetItemByID(itemID)
		for _, line in ipairs(tooltip and tooltip.lines or {}) do
			print(("  line type %s | id %s | %s"):format(tostring(line.type), tostring(line.id), tostring(line.leftText)))
		end
	end
end

-- Toggles a logger for loot windows, quest dialogs and spell targets, to learn what Forever
-- reports for mob, object, container and fishing loot and for quest givers and rewards.
local watcher
local function Watch()
	if watcher then
		watcher:UnregisterAllEvents()
		watcher = nil
		print("Recipe Vacuum: watch off.")
		return
	end
	watcher = CreateFrame("Frame")
	for _, event in ipairs({ "LOOT_OPENED", "QUEST_DETAIL", "QUEST_COMPLETE", "UNIT_SPELLCAST_SENT" }) do
		watcher:RegisterEvent(event)
	end
	watcher:SetScript("OnEvent", function(_, event, ...)
		local mapID = C_Map.GetBestMapForUnit("player")
		local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
		local where = ("map %s pos %s | instance %s"):format(tostring(mapID),
			position and ("%.3f,%.3f"):format(position:GetXY()) or "nil", tostring((IsInInstance())))
		if event == "UNIT_SPELLCAST_SENT" then
			local unit, target = ...
			if unit == "player" and target and target ~= "" then
				print(("%s target %q | %s"):format(event, target, where))
			end
		elseif event == "LOOT_OPENED" then
			local _, isFromItem = ...
			print(("%s | fromItem %s | fishing %s | target %s | %s"):format(event, tostring(isFromItem),
				tostring(IsFishingLoot and IsFishingLoot()), tostring(UnitGUID("target")), where))
			for slot = 1, GetNumLootItems() do
				local sources = GetLootSourceInfo and { GetLootSourceInfo(slot) } or {}
				print(("  slot %d type %s %s | sources %s"):format(slot, tostring(GetLootSlotType(slot)),
					tostring(GetLootSlotLink(slot)), strjoin(" ", tostringall(unpack(sources)))))
			end
		else
			print(("%s quest %s | questnpc %s %s | %s"):format(event, tostring(GetQuestID()),
				tostring(UnitName("questnpc")), tostring(UnitGUID("questnpc")), where))
			for _, kind in ipairs({ "reward", "choice" }) do
				local count = kind == "reward" and GetNumQuestRewards() or GetNumQuestChoices()
				for index = 1, count do
					print(("  %s %d: %s"):format(kind, index, strjoin(" ", tostringall(GetQuestItemInfo(kind, index)))))
				end
			end
		end
	end)
	print("Recipe Vacuum: watch on. Loot a mob, a chest, a container and a fish; open a quest with a recipe reward.")
end

-- Sets a waypoint at the player's position, super-tracks it and opens the map, to see which
-- Show on Map calls work from addon code (OpenWorldMap is marked HasRestrictions).
local function Waypoint()
	local mapID = C_Map.GetBestMapForUnit("player")
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not (position and C_Map.CanSetUserWaypointOnMap(mapID)) then
		print("Recipe Vacuum: no waypoint possible here (map", tostring(mapID), ").")
		return
	end
	print("SetUserWaypoint:", pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, position:GetXY())))
	print("SetSuperTrackedUserWaypoint:", pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true))
	print("OpenWorldMap:", pcall(C_Map.OpenWorldMap, mapID))
	print("In combat:", tostring(InCombatLockdown()))
end

local actions = {
	checks = Checks,
	watch = Watch,
	waypoint = Waypoint,
	exportsize = ExportSize,
	requirements = Requirements,
	log = function() end, -- shows the last command's output again
	dupes = Dupes,
	channeltest = ChannelTest,
	dump = Dump,
	probe = Probe,
	preview = function()
		ns.preview = not ns.preview
		print("Recipe Vacuum: icon preview " .. (ns.preview and "on" or "off") .. ".")
		ns.RefreshRows()
	end,
	strings = function()
		for _, name in ipairs({ "PROFESSION_RECIPES_SHOW_LEARNED", "PROFESSION_RECIPES_SHOW_UNLEARNED", "TRADESKILL_FILTER_HAS_SKILL_UP", "CRAFT_IS_MAKEABLE" }) do
			print(name .. " = " .. tostring(_G[name]))
		end
	end,
	perf = function()
		print("Recipe Vacuum: trade skill show to first ready crafting Init:",
			openMs and ("%.1f ms"):format(openMs) or "no sample")
		print(("Last list with unlearned recipes: %s, %d such builds since reload."):format(
			ns.lastUnlearnedMs and ("%.1f ms"):format(ns.lastUnlearnedMs) or "no sample", ns.unlearnedBuilds or 0))
	end,
}

local actionNames = {}
for name in pairs(actions) do
	table.insert(actionNames, name)
end
table.sort(actionNames)

LibStub("JigBoltgripToolkit-1.0"):RegisterCommand("recipevacuum", function(action)
	local run = actions[action]
	if run then
		if action ~= "log" then
			-- Context for reading the log later: when, which build, who, and the open profession.
			local version, build = GetBuildInfo()
			local _, faction = UnitFactionGroup("player")
			local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
			local profession = page and page:IsVisible() and Professions.GetProfessionInfo()
			ns.db.devLog = {
				date("%Y-%m-%d %H:%M:%S") .. " /boltgrip recipevacuum " .. action,
				("client %s (%s) | addon %s | %s, %s, level %d"):format(version, build,
					tostring(C_AddOns.GetAddOnMetadata("RecipeVacuum", "Version")),
					UnitName("player"), tostring(faction), UnitLevel("player")),
				profession and ("profession %s (id %d) skill %d/%d"):format(profession.professionName or "?",
					profession.professionID or 0, profession.skillLevel or 0, profession.maxSkillLevel or 0)
					or "no open crafting page",
			}
			run()
		end
		ShowLog()
	else
		print("Recipe Vacuum: " .. table.concat(actionNames, ", "))
	end
end, actionNames)
