local _, ns = ...

-- Recipes come across without a known source: chat links, nearby loot, shown professions (docs/data.md, "Come across").
-- Only the recipe and its level are kept, never who or which channel.
local LEVEL = ns.LEVEL

-- Loot lines include the player's own loot, which the recorder already saves with its source.
local CHAT_LEVELS = {
	CHAT_MSG_LOOT = LEVEL.FRIENDS,
	CHAT_MSG_PARTY = LEVEL.FRIENDS, CHAT_MSG_PARTY_LEADER = LEVEL.FRIENDS,
	CHAT_MSG_RAID = LEVEL.FRIENDS, CHAT_MSG_RAID_LEADER = LEVEL.FRIENDS,
	CHAT_MSG_INSTANCE_CHAT = LEVEL.FRIENDS, CHAT_MSG_INSTANCE_CHAT_LEADER = LEVEL.FRIENDS,
	CHAT_MSG_GUILD = LEVEL.FRIENDS, CHAT_MSG_OFFICER = LEVEL.FRIENDS,
	CHAT_MSG_WHISPER = LEVEL.FRIENDS, CHAT_MSG_BN_WHISPER = LEVEL.FRIENDS,
	CHAT_MSG_SAY = LEVEL.PUBLIC, CHAT_MSG_YELL = LEVEL.PUBLIC, CHAT_MSG_CHANNEL = LEVEL.PUBLIC,
}

-- One refresh after a burst of new recipes, and only when the chosen level shows them.
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

local linkLevels = {} -- [character name] = nearest level seen

-- A line without a link costs one plain search.
local function OnChat(event, message, sender)
	if issecretvalue(message) or not message:find("|H", 1, true) then
		return
	end
	local level = CHAT_LEVELS[event]
	-- A whisper is as near as its sender: a stranger's counts as public chat.
	if event == "CHAT_MSG_WHISPER" and not (sender and not issecretvalue(sender) and ns.IsTrusted(sender)) then
		level = LEVEL.PUBLIC
	end
	for id in message:gmatch("|Hitem:(%d+)") do
		local linkedID = tonumber(id)
		local itemID = ns.IsRecipeItem(linkedID)
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
	-- Where a profession link was seen decides how near the linked player counts; session only.
	for guid in message:gmatch("|Htrade:([^:|]+)") do
		local name = select(6, GetPlayerInfoByGUID(guid))
		if name and (not linkLevels[name] or level < linkLevels[name]) then
			linkLevels[name] = level
		end
	end
	-- A recipe linked from a profession window.
	for id in message:gmatch("|Henchant:(%d+)") do
		local spellID = tonumber(id)
		if C_TradeSkillUI.GetTradeSkillLineForRecipe(spellID) then
			Note("recipes", spellID, level)
		end
	end
end

-- A shown profession lists every recipe its player knows: guild views count as Friends, links as Public
-- unless seen in a friends channel.
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

-- A recipe item the player sees, in the bags or on any item tooltip, is met at Self Found: not where it came from
-- (docs/data.md, "Come across"). An item whose data is still loading is not an answer: it is read again on the next sighting.
local itemsDone = {} -- [itemID] = true once read this session, a recipe or not

local function NoteSeenItem(itemID)
	if itemsDone[itemID] then
		return
	end
	if not ns.IsRecipeItem(itemID) then
		itemsDone[itemID] = true
		return
	end
	local recipeID = ns.GetSeededRecipe(itemID) or ns.db.itemRecipe[itemID] or ns.GetTaughtRecipe(itemID)
	if recipeID ~= nil then
		itemsDone[itemID] = true
		if recipeID then
			Note("recipes", recipeID, LEVEL.SELF)
		end
	end
end

-- Bag reads are allowed in combat.
local function ReadBags()
	local lastBag = NUM_BAG_SLOTS + (Enum.BagIndex and Enum.BagIndex.ReagentBag and 1 or 0)
	for bag = 0, lastBag do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local itemID = C_Container.GetContainerItemID(bag, slot)
			if itemID then
				NoteSeenItem(itemID)
			end
		end
	end
end

-- Blizzard's tooltip data hook (Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:199) runs after the tooltip is built;
-- this only reads the item ID and never touches the tooltip.
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(_, data)
	local itemID = ns.db and data and data.id
	if itemID and not issecretvalue(itemID) then
		NoteSeenItem(itemID)
	end
end)

local frame = CreateFrame("Frame")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
for event in pairs(CHAT_LEVELS) do
	frame:RegisterEvent(event)
end
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
frame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
frame:SetScript("OnEvent", function(_, event, message, sender)
	if not ns.db then
		return
	end
	if event == "BAG_UPDATE_DELAYED" or event == "PLAYER_ENTERING_WORLD" then
		ReadBags()
		return
	end
	if CHAT_LEVELS[event] then
		OnChat(event, message, sender)
		return
	end
	if event ~= "TRADE_SKILL_LIST_UPDATE" then
		shownPending = true
	end
	ReadShownProfession()
end)
