local _, ns = ...

-- Recipes the player has come across without learning where they come from (docs/data.md, "Come
-- across"): linked in chat, looted by someone nearby, or listed in a profession another player showed.
-- Only the recipe and how near to the player it arrived (ns.LEVEL) are kept: not who, not which channel.
local LEVEL = ns.LEVEL

-- How near each chat event is. Loot lines cover the player's own loot too, which the recorder already
-- saves with its source.
local CHAT_LEVELS = {
	CHAT_MSG_LOOT = LEVEL.FRIENDS,
	CHAT_MSG_PARTY = LEVEL.FRIENDS, CHAT_MSG_PARTY_LEADER = LEVEL.FRIENDS,
	CHAT_MSG_RAID = LEVEL.FRIENDS, CHAT_MSG_RAID_LEADER = LEVEL.FRIENDS,
	CHAT_MSG_INSTANCE_CHAT = LEVEL.FRIENDS, CHAT_MSG_INSTANCE_CHAT_LEADER = LEVEL.FRIENDS,
	CHAT_MSG_GUILD = LEVEL.FRIENDS, CHAT_MSG_OFFICER = LEVEL.FRIENDS,
	CHAT_MSG_WHISPER = LEVEL.FRIENDS, CHAT_MSG_BN_WHISPER = LEVEL.FRIENDS,
	CHAT_MSG_SAY = LEVEL.PUBLIC, CHAT_MSG_YELL = LEVEL.PUBLIC, CHAT_MSG_CHANNEL = LEVEL.PUBLIC,
}

-- One list refresh after a burst of new recipes, and only when the chosen level shows them.
local REFRESH_DELAY = 1
local refreshQueued

local function Note(bucket, id, level)
	local met = ns.db.met[bucket]
	if met[id] and met[id] <= level then
		return
	end
	met[id] = level
	if level <= ns.db.sourceLevel and not refreshQueued then
		refreshQueued = true
		C_Timer.After(REFRESH_DELAY, function()
			refreshQueued = nil
			ns.SourcesChanged()
		end)
	end
end

local linkLevels = {} -- [character name] = nearest level their profession link was seen at

-- Chat lines are frequent, so a line without a link costs one plain search.
local function OnChat(event, message)
	if issecretvalue(message) or not message:find("|H", 1, true) then
		return
	end
	local level = CHAT_LEVELS[event]
	for id in message:gmatch("|Hitem:(%d+)") do
		local itemID = ns.IsRecipeItem(tonumber(id))
		if itemID then
			local recipeID = ns.GetSeededRecipe(itemID) or ns.db.itemRecipe[itemID]
			if recipeID then
				Note("recipes", recipeID, level)
			else
				Note("items", itemID, level)
				ns.db.pendingItems[itemID] = ns.db.pendingItems[itemID] or {} -- linked by ns.LinkPending
			end
		end
	end
	-- A recipe linked from a profession window.
	-- A profession link names its owner; where it was seen decides how near the profession counts
	-- when opened. Kept for the session only.
	for guid in message:gmatch("|Htrade:([^:|]+)") do
		local name = select(6, GetPlayerInfoByGUID(guid))
		if name and (not linkLevels[name] or level < linkLevels[name]) then
			linkLevels[name] = level
		end
	end
	for id in message:gmatch("|Henchant:(%d+)") do
		local spellID = tonumber(id)
		if C_TradeSkillUI.GetTradeSkillLineForRecipe(spellID) then
			Note("recipes", spellID, level)
		end
	end
end

-- A profession another player showed: every recipe they know. The guild's views count as
-- Friends; a linked one as Public unless its link was seen in a friends channel. Read once per
-- window, when its list is ready.
local shownPending

local function ReadShownProfession()
	if not shownPending or not C_TradeSkillUI.IsTradeSkillReady() then
		return
	end
	shownPending = nil
	local linked, name = C_TradeSkillUI.IsTradeSkillLinked()
	local guild = C_TradeSkillUI.IsTradeSkillGuild() or C_TradeSkillUI.IsTradeSkillGuildMember()
	local level = guild and LEVEL.FRIENDS or linked and (name and linkLevels[name] or LEVEL.PUBLIC)
	if not level then
		return
	end
	for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs()) do
		local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if recipeInfo and recipeInfo.learned then
			Note("recipes", recipeID, level)
		end
	end
end

-- Shown once, the first time the player's own profession window opens: Blizzard's help tip, saying
-- how far the vacuum listens and where that is set. Nothing is chosen for the player.
local function ShowLevelTip()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	if ns.db.levelTipSeen or not page or not Professions.InLocalCraftingMode() then
		return
	end
	HelpTip:Show(page, {
		text = ("Recipe Vacuum lists recipes you come across. It is listening at the %s level; change that in its options.")
			:format(ns.levelNames[ns.db.sourceLevel]),
		buttonStyle = HelpTip.ButtonStyle.Close,
		targetPoint = HelpTip.Point.TopEdgeCenter,
		onAcknowledgeCallback = function() ns.db.levelTipSeen = true end,
	}, page.RecipeList)
end

local frame = CreateFrame("Frame")
for event in pairs(CHAT_LEVELS) do
	frame:RegisterEvent(event)
end
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
frame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
frame:SetScript("OnEvent", function(_, event, message)
	if not ns.db then
		return
	end
	if CHAT_LEVELS[event] then
		OnChat(event, message)
		return
	end
	if event ~= "TRADE_SKILL_LIST_UPDATE" then
		shownPending = true
		if event == "TRADE_SKILL_SHOW" then
			ShowLevelTip()
		end
	end
	ReadShownProfession()
end)
