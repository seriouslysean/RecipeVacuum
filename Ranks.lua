local _, ns = ...
local L = ns.L

-- Ranks come only from what the client shows, so no rank list ships (docs/data.md, "Ranks").
-- The mark beside the window's link button names a recorded source with a place and pins it on the map.
-- It is our frame in our panel, only anchored to the window's, so it writes nothing into Blizzard's frames.
local MARK_SIZE = 20
local MARK_GAP = 4 -- space after the link button
local LINK_X, LINK_Y = -2, -4 -- the link button's anchor offsets on the rank bar (Blizzard_ProfessionsCrafting.xml)

-- A cap that rises this soon after a book use or quest turn-in is taken as caused by it; the client sends
-- SKILL_LINES_CHANGED right after the rank is learned. Unmeasured: kept short so play in between is not blamed.
local CAUSE_SECONDS = 5

local function RankSources(skillLine, fromCap)
	local byLine = ns.db.ranks[skillLine]
	if not byLine then
		byLine = {}
		ns.db.ranks[skillLine] = byLine
	end
	local sources = byLine[fromCap]
	if not sources then
		sources = { npcs = {}, items = {}, quests = {} }
		byLine[fromCap] = sources
	end
	return sources
end

-- Called by the trainer scan (Record.lua); true when the trainer offers a rank this character lacks.
-- The skill step is Blizzard's next-rank row (Blizzard_TrainerUI.lua); a "used" step is one already known,
-- which a trainer the character has outgrown still shows.
function ns.NoteTrainerRank(npcID)
	local step = GetTrainerServiceStepIndex()
	if not step then
		return false
	end
	local _, serviceType = GetTrainerServiceInfo(step)
	if serviceType == "used" or serviceType == "header" then
		return false
	end
	local tooltip = C_TooltipInfo.GetTrainerService(step)
	local spellID = tooltip and tooltip.type == Enum.TooltipDataType.Spell and tooltip.id
	local skillLine = spellID and ns.ProfessionLine(C_TradeSkillUI.GetTradeSkillLineForRecipe(spellID))
	if not skillLine then
		return false
	end
	-- A profession the character lacks has no cap: its next rank is the first, from 0.
	local sources = RankSources(skillLine, ns.GetProfessionCaps()[skillLine] or 0)
	sources.npcs[npcID] = GetServerTime()
	sources.spell = spellID -- the trainer's rank spell, for its name in the tooltip
	return true
end

-- A cap rise is credited to a book or a quest only when it is unambiguous: one profession's cap rose,
-- exactly one cause is recent, and no trainer window is open (a rank bought there is the trainer's).
-- Anything else is left unrecorded rather than guessed.
local recentBook, recentQuest, knownCaps, atTrainer
hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
	-- Read straight after the call; the server removes a used book later, with BAG_UPDATE.
	local itemID = C_Container.GetContainerItemID(bag, slot)
	-- A recipe item that teaches a recipe never raises a cap; only one known to teach none can. An item
	-- whose data has not loaded has given no answer yet, and is not taken for a book.
	if itemID and ns.IsRecipeItem(itemID) and not ns.GetSeededRecipe(itemID) and ns.GetTaughtRecipe(itemID) == false then
		recentBook = { item = itemID, at = GetTime() }
	end
end)

local completing -- the quest and NPC at the open completion window
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "QUEST_COMPLETE", "QUEST_TURNED_IN", "SKILL_LINES_CHANGED",
	"TRAINER_SHOW", "TRAINER_CLOSED" }) do
	watcher:RegisterEvent(event)
end

local function Recent(cause)
	return cause and GetTime() - cause.at <= CAUSE_SECONDS and cause or nil
end

local function CreditRise(skillLine, before)
	local book, quest = Recent(recentBook), Recent(recentQuest)
	recentBook, recentQuest = nil, nil
	if atTrainer or (book and quest) or not (book or quest) or not ns.db.selfFound then
		return
	end
	local sources = RankSources(skillLine, before)
	if book then
		sources.items[book.item] = GetServerTime()
	elseif quest.giver then
		local giver = quest.giver
		ns.NoteNPC(ns.db.npcs, giver[1], giver[2], giver[3], giver[4], giver[5], GetServerTime())
		ns.NoteNPCFaction(giver[1], giver.faction)
		sources.quests[quest.quest] = giver[1]
	end
end

watcher:SetScript("OnEvent", function(_, event, questID)
	if event == "PLAYER_LOGIN" then
		knownCaps = ns.GetProfessionCaps()
	elseif event == "TRAINER_SHOW" or event == "TRAINER_CLOSED" then
		atTrainer = event == "TRAINER_SHOW"
	elseif event == "QUEST_COMPLETE" then
		local guid = UnitGUID("questnpc")
		local unitType, _, _, _, _, npcID = strsplit("-", guid and not issecretvalue(guid) and guid or "")
		local mapID, x, y = ns.GetPlayerLocation()
		completing = unitType == "Creature" and { quest = GetQuestID(), giver = { tonumber(npcID),
			UnitName("questnpc"), mapID, x, y, faction = (UnitFactionGroup("questnpc")) } } or nil
	elseif event == "QUEST_TURNED_IN" then
		-- The giver counts only for the quest whose completion window it was.
		local giver = completing and completing.quest == questID and completing.giver or nil
		recentQuest, completing = { quest = questID, giver = giver, at = GetTime() }, nil
	elseif event == "SKILL_LINES_CHANGED" and knownCaps and ns.db then
		-- Every rise first, then credit: two at once are ambiguous.
		local caps, rises, line, from = ns.GetProfessionCaps(), 0, nil, nil
		for skillLine, cap in pairs(caps) do
			local before = knownCaps[skillLine] or 0 -- a profession just learned rose from 0
			if cap > before then
				rises, line, from = rises + 1, skillLine, before
			end
		end
		if rises == 1 then
			CreditRise(line, from)
		elseif rises > 1 then
			recentBook, recentQuest = nil, nil
		end
		knownCaps = caps
	end
end)

-- The open profession's next rank: its usable recorded sources and their pins, or nil when none has a place.
local function NextRank()
	local info = ProfessionsFrame.CraftingPage.professionInfo
	local skillLine = info and ns.ProfessionLine(info.professionID, nil, info.parentProfessionID)
	-- ns.rankOverlay: the working build's session-only test sources, never saved (Troubleshooting.lua).
	local byLine = skillLine and (ns.rankOverlay and ns.rankOverlay[skillLine] or ns.db.ranks[skillLine])
	local sources = byLine and byLine[ns.GetProfessionCaps()[skillLine] or 0]
	if not sources then
		return nil
	end
	local candidates = {}
	for npcID in pairs(sources.npcs) do
		candidates[#candidates + 1] = { kind = "trainer", npc = npcID }
	end
	for itemID in pairs(sources.items) do
		for _, observation in ipairs(ns.GetItemSources(itemID)) do
			candidates[#candidates + 1] = observation
		end
	end
	for questID, giver in pairs(sources.quests) do
		candidates[#candidates + 1] = { kind = "quest", quest = questID, npc = giver }
	end
	local entries, targets = {}, {}
	for _, observation in ipairs(candidates) do
		if not ns.IsOtherFactionNPC(observation) then
			entries[#entries + 1] = observation
			local target = ns.SourceTarget(observation)
			if target then targets[#targets + 1] = target end
		end
	end
	return #targets > 0 and { sources = sources, profession = info.professionName, entries = entries, targets = targets } or nil
end

-- Titled with the game's own name for what is learned. Read at hover, since item and quest names can
-- arrive after the window opens.
local function RankName(rank)
	local sources = rank.sources
	local name = sources.spell and C_Spell.GetSpellName(sources.spell)
	for itemID in pairs(sources.items) do
		name = C_Item.GetItemNameByID(itemID) or name
	end
	for questID in pairs(sources.quests) do
		name = name or C_QuestLog.GetTitleForQuestID(questID)
	end
	return name or rank.profession or UNKNOWN
end

local mark

local function OnEnter(button)
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT") -- over the window, not at the panel edge
	GameTooltip_SetTitle(GameTooltip, RankName(button.rank))
	ns.AddEntryLines(GameTooltip, button.rank.entries)
	local count = #button.rank.targets
	if count > 1 then
		GameTooltip_AddColoredLine(GameTooltip, L["Click to pin the first of %d places."]:format(count), GRAY_FONT_COLOR)
	end
	GameTooltip:Show()
end

-- Pins the first place, this zone's first; a menu would taint (docs/client-notes.md, "Gamepad").
local function OnClick(button)
	local targets = button.rank.targets
	ns.SortTargets(targets)
	ns.ShowOnMap(targets[1])
end

-- Run after Blizzard's page rebuilds, and by the panel once it exists (its hook runs after this one on the first Init).
function ns.UpdateRankMark()
	local page = ProfessionsFrame.CraftingPage
	if not mark then
		-- Ours, never a child of Blizzard's page (Gamepad UI rule); it follows the page's showing and hiding instead, since our panel
		-- hides when it has nothing to list and the mark belongs beside Blizzard's bar either way.
		mark = CreateFrame("Button", nil, UIParent)
		page:HookScript("OnHide", function() mark:Hide() end)
		page:HookScript("OnShow", ns.UpdateRankMark)
		mark:SetSize(MARK_SIZE, MARK_SIZE)
		mark:SetFrameStrata("HIGH") -- drawn over the window it is positioned on, though it is ours
		local icon = mark:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		icon:SetAtlas(ns.sourceTypes.trainer.atlas) -- the same book as the trainer mark
		-- Brightens on hover, as Blizzard's buttons do, so it reads as clickable without a hint line.
		mark:SetHighlightAtlas(ns.sourceTypes.trainer.atlas, "ADD")
		mark:SetScript("OnEnter", OnEnter)
		mark:SetScript("OnLeave", GameTooltip_Hide)
		mark:SetScript("OnClick", OnClick)
	end
	-- Placed by reading the window's position only: after the link button, or where it would sit when it is hidden.
	mark:ClearAllPoints()
	if page.LinkButton:IsShown() then
		mark:SetPoint("LEFT", page.LinkButton, "RIGHT", MARK_GAP, 0)
	else
		mark:SetPoint("LEFT", page.RankBar, "RIGHT", LINK_X, LINK_Y)
	end
	mark.rank = Professions.InLocalCraftingMode() and NextRank() or nil
	mark:SetShown(mark.rank ~= nil and page:IsVisible())
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
	hooksecurefunc(ProfessionsFrame.CraftingPage, "Init", ns.UpdateRankMark)
end)
