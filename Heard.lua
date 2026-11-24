local _, ns = ...

-- Recipes the player has come across without learning where they come from (docs/data.md, "Come
-- across"): linked in chat, looted by someone nearby, or listed in a profession another player showed.
-- Only the recipe and how near to the player it arrived (ns.LEVEL) are kept: not who, not which channel.
local LEVEL = ns.LEVEL
local RECIPE_ITEM_CLASS = Enum.ItemClass.Recipe

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
		local itemID = tonumber(id)
		local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
		if classID == RECIPE_ITEM_CLASS then
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

-- A profession another player showed: every recipe they know. The guild's own view counts as
-- Friends; a linked one as Public unless its link was seen in a friends channel. Read once per
-- window, when its list is ready.
local shownPending

local function ReadShownProfession()
	if not shownPending or not C_TradeSkillUI.IsTradeSkillReady() then
		return
	end
	shownPending = nil
	local linked, name = C_TradeSkillUI.IsTradeSkillLinked()
	local level = C_TradeSkillUI.IsTradeSkillGuild() and LEVEL.FRIENDS
		or linked and (name and linkLevels[name] or LEVEL.PUBLIC)
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

-- Asked once, the first time a profession window opens: how far the vacuum listens. Escape keeps the
-- default, Friends. The same choice is on the options page.
local CHOOSER = "RECIPEVACUUM_SOURCE_LEVEL"
StaticPopupDialogs[CHOOSER] = {
	text = "How should Recipe Vacuum learn about recipes?|n|n"
		.. "Self Found: only what you see yourself.|n"
		.. "Friends: also what your party, raid, guild and friends see.|n"
		.. "Public: also recipes linked in public chat.|n|n"
		.. "You can change this in the options.",
	button1 = "Friends", button2 = "Self Found", button3 = "Public",
	OnAccept = function() ns.ChooseLevel(LEVEL.FRIENDS) end,
	OnCancel = function(_, _, reason)
		-- Escape and a timeout also arrive here; only a click on the button picks Self Found.
		ns.ChooseLevel(reason == "clicked" and LEVEL.SELF or LEVEL.FRIENDS)
	end,
	OnAlt = function() ns.ChooseLevel(LEVEL.PUBLIC) end,
	hideOnEscape = true, whileDead = true, timeout = 0,
}

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
		if event == "TRADE_SKILL_SHOW" and not ns.db.levelChosen then
			StaticPopup_Show(CHOOSER)
		end
	end
	ReadShownProfession()
end)
