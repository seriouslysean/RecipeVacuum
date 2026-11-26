local _, ns = ...

-- Recipes come across without a known source: chat links, nearby loot, shown professions (docs/data.md, "Come across").
-- Only the recipe and its level are kept, never who or which channel.
local LEVEL = ns.LEVEL

-- A link in any chat is something the player saw, so every channel counts at Self Found (docs/data.md, "Come across"). Loot lines include the player's own loot, which the recorder already saves with its source.
local CHAT_EVENTS = {
	"CHAT_MSG_LOOT",
	"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
	"CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL",
}
local isChatEvent = {}
for _, event in ipairs(CHAT_EVENTS) do
	isChatEvent[event] = true
end

-- Windows that show the player many items at once. Recipes first seen while one is open are said once when the last closes
-- (docs/data.md, "Come across"). Events: Blizzard_APIDocumentationGenerated (AuctionHouse, Bank, MailInfo, TradeInfo);
-- bags have no one event, so BAG_CLOSED re-asks IsAnyBagOpen (Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua).
local WINDOW_OPENED = {
	AUCTION_HOUSE_SHOW = "auction", BANKFRAME_OPENED = "bank", TRADE_SHOW = "trade", MAIL_SHOW = "mail",
}
local WINDOW_CLOSED = {
	AUCTION_HOUSE_CLOSED = "auction", BANKFRAME_CLOSED = "bank", TRADE_CLOSED = "trade", MAIL_CLOSED = "mail",
}
local openWindows = {}
local seenCount = 0

local function WindowOpen()
	return next(openWindows) ~= nil or IsAnyBagOpen()
end

local function SaySeen()
	local count = seenCount
	seenCount = 0
	if count > 0 and ns.db.announceNewFinds then
		local seen = ns.voice.seen
		ns.Say(seen.noise, (count == 1 and seen.reportOne or seen.report):format(count))
	end
end

-- Closing the last window says the line; anything still open keeps the count.
local function OnWindowClosed()
	if not WindowOpen() then
		SaySeen()
	end
end

-- One refresh after a burst of new recipes, and only when the chosen level shows them.
local REFRESH_DELAY = 1
local refreshQueued

-- Whether the character has the profession a recipe belongs to: its skill line against GetProfessions' lines.
local function HasProfession(recipeID)
	return ns.GetProfessionCaps()[ns.ProfessionLine(C_TradeSkillUI.GetTradeSkillLineForRecipe(recipeID))] ~= nil
end

-- A recipe met at Self Found for the first time while a window is open counts toward its closing line, once:
-- a repeat sighting changes nothing here, so it is not counted again.
local function Note(bucket, id, level)
	local met = ns.db.met[bucket]
	if met[id] and met[id] <= level then
		return
	end
	met[id] = level
	if level == LEVEL.SELF and bucket == "recipes" and WindowOpen() and HasProfession(id) then
		seenCount = seenCount + 1
	end
	if level <= ns.db.sourceLevel and not refreshQueued then
		refreshQueued = true
		C_Timer.After(REFRESH_DELAY, function()
			refreshQueued = nil
			ns.SourcesChanged()
		end)
	end
end

-- A line without a link costs one plain search.
local function OnChat(message)
	if issecretvalue(message) or not message:find("|H", 1, true) then
		return
	end
	local level = LEVEL.SELF
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
	-- A recipe linked from a profession window.
	for id in message:gmatch("|Henchant:(%d+)") do
		local spellID = tonumber(id)
		if C_TradeSkillUI.GetTradeSkillLineForRecipe(spellID) then
			Note("recipes", spellID, level)
		end
	end
end

-- A shown profession lists every recipe its player knows: guild views count as Friends, links as Public.
local shownPending

local function ReadShownProfession()
	if not shownPending or not C_TradeSkillUI.IsTradeSkillReady() then
		return
	end
	shownPending = nil
	local linked = C_TradeSkillUI.IsTradeSkillLinked()
	local guild = C_TradeSkillUI.IsTradeSkillGuild() or C_TradeSkillUI.IsTradeSkillGuildMember()
	-- Another player's profession, linked or a guild member's, is something the player saw for themselves.
	if not (linked or guild) then
		return
	end
	local level = LEVEL.SELF
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

-- The bank's contents, read while it is open: its tabs as the window lists them (Camelot/BankFrame.lua, GetNumPagesForBankType), or its
-- single container on a client without tabs.
local function ReadBank()
	local containers = {}
	if C_Bank and C_Bank.FetchPurchasedBankTabData and Enum.BankType then
		for _, bankType in ipairs({ Enum.BankType.Character, Enum.BankType.Account }) do
			for _, tab in ipairs(bankType and C_Bank.FetchPurchasedBankTabData(bankType) or {}) do containers[#containers + 1] = tab.ID end
		end
	end
	if #containers == 0 and Enum.BagIndex and Enum.BagIndex.Characterbanktab then containers[1] = Enum.BagIndex.Characterbanktab end
	for _, bag in ipairs(containers) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local itemID = C_Container.GetContainerItemID(bag, slot)
			if itemID then NoteSeenItem(itemID) end
		end
	end
end

-- Auction house search results: every item a search lists is seen, as the window shows it
-- (Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseBrowseResultsFrame.lua, UpdateBrowseResults: each result's itemKey).
local function ReadBrowseResults(results)
	for _, result in ipairs(results or {}) do
		local itemID = result.itemKey and result.itemKey.itemID
		if itemID then NoteSeenItem(itemID) end
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
for _, event in ipairs(CHAT_EVENTS) do
	frame:RegisterEvent(event)
end
for event in pairs(WINDOW_OPENED) do
	frame:RegisterEvent(event)
end
for event in pairs(WINDOW_CLOSED) do
	frame:RegisterEvent(event)
end
frame:RegisterEvent("BAG_CLOSED")
frame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
frame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
frame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
frame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
frame:SetScript("OnEvent", function(_, event, message)
	if not ns.db then
		return
	end
	if event == "BAG_UPDATE_DELAYED" or event == "PLAYER_ENTERING_WORLD" then
		ReadBags()
		return
	end
	if isChatEvent[event] then
		OnChat(message)
		return
	end
	if WINDOW_OPENED[event] then
		openWindows[WINDOW_OPENED[event]] = true
		-- The bank's contents count as seen, as the bags do.
		if event == "BANKFRAME_OPENED" then ReadBank() end
		return
	end
	if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
		ReadBrowseResults(C_AuctionHouse.GetBrowseResults())
		return
	end
	if event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
		ReadBrowseResults(message) -- the newly added results
		return
	end
	if event == "PLAYERBANKSLOTS_CHANGED" then
		if openWindows.bank then ReadBank() end
		return
	end
	if WINDOW_CLOSED[event] then
		openWindows[WINDOW_CLOSED[event]] = nil
		OnWindowClosed()
		return
	end
	if event == "BAG_CLOSED" then
		-- The bag's frame is hidden as the event fires; ask again once the client has settled.
		C_Timer.After(0, OnWindowClosed)
		return
	end
	if event ~= "TRADE_SKILL_LIST_UPDATE" then
		shownPending = true
	end
	ReadShownProfession()
end)
