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

-- Windows that show the player many items at once. Recipes first seen while one is open are said when that window closes
-- (docs/data.md, "Come across"). Events: Blizzard_APIDocumentationGenerated (AuctionHouse, Bank, MailInfo, TradeInfo);
-- bags have no one event, so they are asked of IsAnyBagOpen (Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua).
local WINDOW_OPENED = {
	AUCTION_HOUSE_SHOW = "auction", BANKFRAME_OPENED = "bank", TRADE_SHOW = "trade", MAIL_SHOW = "mail",
}
local WINDOW_CLOSED = {
	AUCTION_HOUSE_CLOSED = "auction", BANKFRAME_CLOSED = "bank", TRADE_CLOSED = "trade", MAIL_CLOSED = "mail",
}
-- Counts are per window (docs/data.md, "Come across"): a sighting credits the most recently opened window that is not the bags and is
-- still open, and the bags only when none is. Each window says its own count when it closes.
local BAGS = "bags"
local openWindows = {}  -- [window] = true while open, the bags included
local openOrder = {}    -- the windows other than the bags, oldest first
local counts = {}       -- [window] = recipes first met while it was the credited window
-- Recipe items sighted while a window was open whose data had not loaded: a search lists items the client has not met, and their recipes
-- are known only when the load answers (ITEM_DATA_LOAD_RESULT), often after the window closes. The line waits for them, at most this long.
-- Unmeasured: how long a search's items take to load.
local DEFERRED_WAIT = 3
local deferred = {}     -- [itemID] = the window it was sighted under
local closing = {}      -- [window] = token while its closed window waits for deferred items
local closeToken = 0

local function Unanswered(window)
	local unanswered = 0
	for _, owner in pairs(deferred) do
		if owner == window then unanswered = unanswered + 1 end
	end
	return unanswered
end

local function Say(window)
	local count = counts[window] or 0
	counts[window] = nil
	local announce = ns.db.announceNewFinds
	ns.Trace("SEEN %s closed: %d counted, %s", window, count, count == 0 and "silent, nothing new for the character's professions" or announce and "said" or "silent, Announce New Finds is off")
	if count > 0 and announce then
		local seen = ns.voice.seen
		ns.Say(seen.noise, (count == 1 and seen.reportOne or seen.report):format(count))
	end
end

-- Said once nothing waits any more, or the wait is up; a window opened meanwhile keeps the count for its own close.
local function EndClosing(window, token)
	if not closing[window] or (token and token ~= closing[window]) then
		return
	end
	closing[window] = nil
	local unanswered = Unanswered(window)
	if unanswered > 0 then
		ns.Trace("SEEN %s: %d items still unanswered, not counted", window, unanswered)
	end
	for itemID, owner in pairs(deferred) do
		if owner == window then deferred[itemID] = nil end
	end
	if openWindows[window] then
		ns.Trace("SEEN %s reopened while waiting, silent, its count stays for its next close", window)
		return
	end
	Say(window)
end

local function OpenWindow(window)
	if not openWindows[window] then
		openWindows[window] = true
		if window ~= BAGS then table.insert(openOrder, window) end
		ns.Trace("SEEN %s opened", window)
	else
		ns.Trace("SEEN %s opened again while open, ignored", window)
	end
end

-- A closing window says its own line, after the items it saw have answered, whatever else is still open.
local function CloseWindow(window)
	if not openWindows[window] then
		ns.Trace("SEEN %s closed, silent: it was not open", window)
		return
	end
	openWindows[window] = nil
	for index, open in ipairs(openOrder) do
		if open == window then table.remove(openOrder, index) break end
	end
	if Unanswered(window) > 0 then
		closeToken = closeToken + 1
		local token = closeToken
		closing[window] = token
		ns.Trace("SEEN %s closed, waiting for items that had not loaded", window)
		C_Timer.After(DEFERRED_WAIT, function() EndClosing(window, token) end)
		return
	end
	Say(window)
end

-- The bags have no one open or close event and the client does not always send BAG_CLOSED (measured on the Deck: the auction house opened
-- the bags and no BAG_CLOSED was logged), so their state is asked of IsAnyBagOpen whenever it can have changed.
local function SyncBags()
	local open = IsAnyBagOpen()
	if open then
		if not openWindows[BAGS] then OpenWindow(BAGS) end
	elseif openWindows[BAGS] then
		CloseWindow(BAGS)
	end
end

-- The window a sighting counts for, or nil when none is open.
local function Target()
	local latest = openOrder[#openOrder]
	if latest then
		return latest
	end
	SyncBags()
	return openWindows[BAGS] and BAGS or nil
end

local bagSyncQueued
local function QueueBagSync()
	if bagSyncQueued then return end
	bagSyncQueued = true
	-- The bag's frame is hidden as the event fires; ask again once the client has settled.
	C_Timer.After(0, function()
		bagSyncQueued = nil
		SyncBags()
	end)
end

-- The client's combined bag frame and each container frame (Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml:298-313); read-only hooks.
local hookedBagFrames = {}
local function HookBagFrames()
	local names = { "ContainerFrameCombinedBags" }
	for index = 1, tonumber(NUM_CONTAINER_FRAMES) or 0 do names[#names + 1] = "ContainerFrame" .. index end
	for _, name in ipairs(names) do
		local bagFrame = _G[name]
		if bagFrame and not hookedBagFrames[name] then
			hookedBagFrames[name] = true
			bagFrame:HookScript("OnShow", QueueBagSync)
			bagFrame:HookScript("OnHide", QueueBagSync)
		end
	end
end

-- One refresh after a burst of new recipes, and only when the chosen level shows them.
local REFRESH_DELAY = 1
local refreshQueued

-- Whether the character has the profession a recipe belongs to: its skill line against GetProfessions' lines.
local function HasProfession(recipeID)
	return ns.GetProfessionCaps()[ns.ProfessionLine(C_TradeSkillUI.GetTradeSkillLineForRecipe(recipeID))] ~= nil
end

-- A recipe met at Self Found for the first time while a window is open counts toward that window's closing line, once:
-- a repeat sighting changes nothing here, so it is not counted again.
local function Note(bucket, id, level, window)
	local met = ns.db.met[bucket]
	if met[id] and met[id] <= level then
		return
	end
	met[id] = level
	if level == LEVEL.SELF and bucket == "recipes" then
		window = window or Target()
		if not window then
			ns.Trace("SEEN recipe %d not counted, no window open", id)
		elseif HasProfession(id) then
			counts[window] = (counts[window] or 0) + 1
			ns.Trace("SEEN recipe %d counted for %s", id, window)
		else
			ns.Trace("SEEN recipe %d not counted, not the character's profession", id)
		end
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
local itemAttempts = {} -- [itemID] = reads that got no answer; some recipe items never answer (docs/client-notes.md, "Recipe items")

local function NoteSeenItem(itemID)
	if itemsDone[itemID] then
		return
	end
	if not ns.IsRecipeItem(itemID) then
		itemsDone[itemID] = true
		return
	end
	local recipeID = ns.GetSeededRecipe(itemID) or ns.db.itemRecipe[itemID]
	-- A load answer for a deferred item still gets through; a fresh sighting past the cap does not ask the client again.
	if recipeID == nil then
		if (itemAttempts[itemID] or 0) >= ns.MAX_ITEM_ATTEMPTS and not deferred[itemID] then
			return
		end
		recipeID = ns.GetTaughtRecipe(itemID)
	end
	local window = deferred[itemID] or Target()
	if recipeID ~= nil then
		itemsDone[itemID] = true
		deferred[itemID] = nil
		if recipeID then
			Note("recipes", recipeID, LEVEL.SELF, window)
		end
	else
		itemAttempts[itemID] = (itemAttempts[itemID] or 0) + 1
		if itemAttempts[itemID] >= ns.MAX_ITEM_ATTEMPTS then
			ns.Trace("SEEN item %d unanswered %d times, not asked again this session", itemID, itemAttempts[itemID])
		end
		if window then
			deferred[itemID] = window -- read again when its data loads, for the window that saw it
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
	local items, recipes = 0, 0
	for _, bag in ipairs(containers) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local itemID = C_Container.GetContainerItemID(bag, slot)
			if itemID then
				items = items + 1
				if ns.IsRecipeItem(itemID) then recipes = recipes + 1 end
				NoteSeenItem(itemID)
			end
		end
	end
	ns.Trace("SEEN bank read: %d containers, %d items, %d recipe items", #containers, items, recipes)
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
frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
frame:RegisterEvent("BAG_CLOSED")
frame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
frame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
frame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
frame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
frame:SetScript("OnEvent", function(_, event, message, loaded)
	if not ns.db then
		return
	end
	if event == "ITEM_DATA_LOAD_RESULT" then
		local window = deferred[message]
		if window then
			if loaded then
				NoteSeenItem(message)
			else
				deferred[message] = nil -- never answers
			end
			if closing[window] and Unanswered(window) == 0 then
				EndClosing(window)
			end
		end
		return
	end
	if event == "BAG_UPDATE_DELAYED" or event == "PLAYER_ENTERING_WORLD" then
		if event == "PLAYER_ENTERING_WORLD" then HookBagFrames() end
		ReadBags()
		return
	end
	if isChatEvent[event] then
		OnChat(message)
		return
	end
	if WINDOW_OPENED[event] then
		OpenWindow(WINDOW_OPENED[event])
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
		CloseWindow(WINDOW_CLOSED[event])
		QueueBagSync() -- closing the window may have closed the bags with it
		return
	end
	if event == "BAG_CLOSED" then
		QueueBagSync()
		return
	end
	if event ~= "TRADE_SKILL_LIST_UPDATE" then
		shownPending = true
	end
	ReadShownProfession()
end)

--@debug@
-- Every event these frames receive goes into the working-build log (docs/standards.md, "Working build helpers").
ns.toolkit:WatchEvents(ns.device, frame)
--@end-debug@
