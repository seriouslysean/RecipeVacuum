local _, ns = ...

-- Recipes come across without a known source: chat links, nearby loot, shown professions (docs/data.md, "Come across").
-- Only the recipe and its level are kept, never who or which channel.
local LEVEL = ns.LEVEL
local Readable = ns.toolkit.Readable

-- A link in any chat is something the player saw, so every channel counts at Self Found (docs/data.md, "Come across"). Loot lines include the player's own loot, which the recorder already saves with its source.
local CHAT_EVENTS = {
	"CHAT_MSG_LOOT",
	"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
	"CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL",
}

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
	ns.toolkit:Trace(ns.module, "window closed", "name", window, "counted", count, "said", count == 0 and "no_new" or announce and "yes" or "alerts_off")
	if count > 0 and announce then
		ns.toolkit:Say(ns.module, ns.voice.seen, count)
	end
end

-- Said once nothing waits any more, or the wait is up; a window opened meanwhile keeps the count for its own close.
local function EndClosing(window, token)
	if not closing[window] or (token and token ~= closing[window]) then
		return
	end
	closing[window] = nil
	if openWindows[window] then
		-- Its ids stay, for the load results to credit to the open window.
		ns.toolkit:Trace(ns.module, "window reopened", "name", window, "unanswered", Unanswered(window))
		return
	end
	local unanswered = Unanswered(window)
	if unanswered > 0 then
		ns.toolkit:Trace(ns.module, "window waits", "name", window, "unanswered", unanswered)
	end
	for itemID, owner in pairs(deferred) do
		if owner == window then deferred[itemID] = nil end
	end
	Say(window)
end

local function OpenWindow(window)
	if not openWindows[window] then
		openWindows[window] = true
		if window ~= BAGS then table.insert(openOrder, window) end
		ns.toolkit:Trace(ns.module, "window opened", "name", window)
	else
		ns.toolkit:Trace(ns.module, "window opened", "name", window, "again", "true")
	end
end

-- A closing window says its own line, after the items it saw have answered, whatever else is still open.
local function CloseWindow(window)
	if not openWindows[window] then
		ns.toolkit:Trace(ns.module, "window closed", "name", window, "was_open", "false")
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
		ns.toolkit:Trace(ns.module, "window closed", "name", window, "waits", "items_loading")
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
local function HasProfession(recipeID, caps)
	return (caps or ns.GetProfessionCaps())[ns.ProfessionLine(C_TradeSkillUI.GetTradeSkillLineForRecipe(recipeID))] ~= nil
end

-- A recipe met at Self Found for the first time while a window is open counts toward that window's closing line, once:
-- a repeat sighting changes nothing here, so it is not counted again.
local function Note(bucket, id, level, window, caps)
	local met = ns.db.met[bucket]
	if met[id] and met[id] <= level then
		return
	end
	met[id] = level
	if level == LEVEL.SELF and bucket == "recipes" then
		window = window or Target()
		if not window then
			ns.toolkit:Trace(ns.module, "recipe seen", "id", id, "counted", "false", "reason", "no_window")
		elseif HasProfession(id, caps) then
			counts[window] = (counts[window] or 0) + 1
			ns.toolkit:Trace(ns.module, "recipe seen", "id", id, "window", window)
		else
			ns.toolkit:Trace(ns.module, "recipe seen", "id", id, "counted", "false", "reason", "other_profession")
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

-- A recipe any character on the account knows is met at Self Found: knowing it is seeing it, the details stay the player's own
-- (docs/data.md, "Come across"). One table write, no window count and no refresh; true when it is new.
function ns.NoteKnown(recipeID)
	local met = ns.db.met.recipes
	if met[recipeID] == LEVEL.SELF then return false end
	met[recipeID] = LEVEL.SELF
	return true
end

-- A line without a link costs one plain search.
local function OnChat(message)
	if not Readable(message) or not message:find("|H", 1, true) then
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

-- A shown profession lists every recipe its player knows: another player's, linked or a guild member's, is something the player saw
-- for themselves. The walk is sliced like the unlearned read, one recipe at least a frame (docs/client-notes.md, "Panel").
local shownPending
local shownRun = 0 -- a newer profession shown ends the walk of an older one
local SHOWN_STEP_MS = 2
-- Full passes of one shown profession whose missing count did not shrink; at ns.MAX_ITEM_ATTEMPTS the walk ends, as an item that
-- never answers does, since TRADE_SKILL_LIST_UPDATE repeats every few seconds (docs/client-notes.md, "Panel").
local shownStalls, shownLastMissing = 0, nil

-- The walk is over a snapshot of the list, so it is only done once a pass found info for every id: a recipe whose info has not
-- loaded stays pending, and the next list update walks the list again. Notes are idempotent, so a repeat pass costs only reads.
local function ReadShownStep(run, ids, at, started, learned, missing)
	if run ~= shownRun then return end
	ns.shownStepAt = GetTime() -- the frame pool waits while a walk runs (Panel.lua, pool.settling)
	local stepStart = debugprofilestop()
	local count = #ids
	while at <= count do
		-- The window closed or switched, or its data is reloading: shownPending is still set, so the next list update walks again.
		if not C_TradeSkillUI.IsTradeSkillReady() then return end
		local recipeInfo = C_TradeSkillUI.GetRecipeInfo(ids[at])
		-- A table without its name is the not-loaded case, as in Unlearned.lua: not an answer.
		if not (recipeInfo and recipeInfo.name) then
			missing = missing + 1
		elseif recipeInfo.learned then
			learned = learned + 1
			-- No caps given: they are read where the recipe is counted, as an early read can come back empty.
			Note("recipes", ids[at], LEVEL.SELF)
		end
		at = at + 1
		if debugprofilestop() - stepStart >= SHOWN_STEP_MS then break end
	end
	--@debug@
	ns.PerfMs("heard shown profession step", debugprofilestop() - stepStart)
	--@end-debug@
	if at <= count then
		RunNextFrame(function() ReadShownStep(run, ids, at, started, learned, missing) end)
	else
		-- Ids the list gained after the snapshot are not read yet either.
		missing = missing + math.max(0, #C_TradeSkillUI.GetAllRecipeIDs() - count)
		local gaveUp = false
		if missing == 0 then
			shownPending = nil
		else
			shownStalls = (shownLastMissing and missing >= shownLastMissing) and shownStalls + 1 or 0
			shownLastMissing = missing
			if shownStalls >= ns.MAX_ITEM_ATTEMPTS then
				shownPending, gaveUp = nil, true
			end
		end
		ns.toolkit:Trace(ns.module, "shown profession", "recipes", count, "learned", learned, "missing", missing, "next", gaveUp and "given_up" or missing > 0 and "reread" or "done", "ms", debugprofilestop() - started)
	end
end

local function ReadShownProfession()
	if not shownPending or not C_TradeSkillUI.IsTradeSkillReady() then
		return
	end
	local linked = C_TradeSkillUI.IsTradeSkillLinked()
	local guild = C_TradeSkillUI.IsTradeSkillGuild() or C_TradeSkillUI.IsTradeSkillGuildMember()
	if not (linked or guild) then
		shownPending = nil
		return
	end
	shownRun = shownRun + 1
	ReadShownStep(shownRun, C_TradeSkillUI.GetAllRecipeIDs(), 1, debugprofilestop(), 0, 0)
end

-- A recipe item the player sees, in the bags or on any item tooltip, is met at Self Found: not where it came from
-- (docs/data.md, "Come across"). An item whose data is still loading is not an answer: it is read again on the next sighting.
local itemsDone = {} -- [itemID] = true once read this session, a recipe or not
local itemAttempts = {} -- [itemID] = reads that got no answer; some recipe items never answer (docs/client-notes.md, "Recipe items")

local function NoteSeenItem(itemID, loadAnswered)
	if itemsDone[itemID] then
		return
	end
	if not ns.IsRecipeItem(itemID) then
		itemsDone[itemID] = true
		return
	end
	local recipeID = ns.GetSeededRecipe(itemID) or ns.db.itemRecipe[itemID]
	-- A load answer still gets through; a fresh sighting past the cap does not ask the client again, deferred or not.
	if recipeID == nil then
		if (itemAttempts[itemID] or 0) >= ns.MAX_ITEM_ATTEMPTS and not loadAnswered then
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
			ns.toolkit:Trace(ns.module, "item skipped", "id", itemID, "attempts", itemAttempts[itemID], "reason", "no_answer")
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
	ns.toolkit:Trace(ns.module, "bank read", "containers", #containers, "items", items, "recipe_items", recipes)
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
	if itemID and Readable(itemID) then
		NoteSeenItem(itemID)
	end
end)

local handlers = {
	ITEM_DATA_LOAD_RESULT = function(itemID, loaded)
		local window = deferred[itemID]
		-- An item the scan gave up on (no window open, nothing deferred) can still answer its last request.
		local gaveUp = not window and (itemAttempts[itemID] or 0) >= ns.MAX_ITEM_ATTEMPTS and not itemsDone[itemID]
		if loaded and (window or gaveUp) then
			if gaveUp then ns.toolkit:Trace(ns.module, "item late", "id", itemID, "reread", "true") end
			NoteSeenItem(itemID, true)
		elseif window then
			deferred[itemID] = nil -- never answers
		end
		if window and closing[window] and Unanswered(window) == 0 then
			EndClosing(window)
		end
	end,
	NEW_RECIPE_LEARNED = function(recipeID)
		if type(recipeID) == "number" and ns.NoteKnown(recipeID) then
			ns.toolkit:Trace(ns.module, "recipe learned", "id", recipeID)
		end
	end,
	BAG_UPDATE_DELAYED = function() ReadBags() end,
	PLAYER_ENTERING_WORLD = function()
		HookBagFrames()
		ReadBags()
	end,
	AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = function() ReadBrowseResults(C_AuctionHouse.GetBrowseResults()) end,
	AUCTION_HOUSE_BROWSE_RESULTS_ADDED = function(results) ReadBrowseResults(results) end, -- the newly added results
	PLAYERBANKSLOTS_CHANGED = function()
		if openWindows.bank then ReadBank() end
	end,
	BAG_CLOSED = function() QueueBagSync() end,
	TRADE_SKILL_SHOW = function()
		shownPending, shownStalls, shownLastMissing = true, 0, nil
		shownRun = shownRun + 1
		ReadShownProfession()
	end,
	TRADE_SKILL_DATA_SOURCE_CHANGED = function()
		shownPending, shownStalls, shownLastMissing = true, 0, nil
		shownRun = shownRun + 1
		ReadShownProfession()
	end,
	TRADE_SKILL_LIST_UPDATE = function() ReadShownProfession() end,
}
for _, event in ipairs(CHAT_EVENTS) do
	handlers[event] = OnChat
end
for event, window in pairs(WINDOW_OPENED) do
	handlers[event] = function()
		OpenWindow(window)
		-- The bank's contents count as seen, as the bags do.
		if event == "BANKFRAME_OPENED" then ReadBank() end
	end
end
for event, window in pairs(WINDOW_CLOSED) do
	handlers[event] = function()
		CloseWindow(window)
		QueueBagSync() -- closing the window may have closed the bags with it
	end
end
-- Nothing is read before the saved data has loaded.
for event, handler in pairs(handlers) do
	handlers[event] = function(...)
		if ns.db then handler(...) end
	end
end
--@debug@
-- Each event's own cost in the timing table, by name, so a slow frame is traced to the event that ran in it.
for event, handler in pairs(handlers) do
	handlers[event] = function(...)
		local started = debugprofilestop()
		handler(...)
		ns.Perf("heard " .. event, started)
	end
end
--@end-debug@
ns.toolkit:EventFrame(ns.module, handlers)
