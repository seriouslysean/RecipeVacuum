local _, ns = ...
local comm = {}
LibStub("AceComm-3.0"):Embed(comm)

-- Each exchange step, to the working build's log.
local function Trace(text, ...)
	ns.Trace("SHARE " .. text, ...)
end

-- Sharing uses hidden addon messages only: probe, request, batched reply (docs/data.md, "Sharing").
-- The version is in both prefixes; other versions are ignored.
local PROBE_PREFIX = "RecipeVacuum2"
local DATA_PREFIX = "RecipeVacuum2D"
local SEND_LIMIT = 4000 -- encoded bytes per reply, about 16 AceComm chunks
local RECEIVE_LIMIT = 6000 -- larger replies are rejected before decoding
local EXPANDED_LIMIT = 65536 -- decompressed bytes accepted before CBOR decoding
local MAX_ROWS = 64
local REQUEST_TIMEOUT = 30
local REQUEST_RETRIES = 2 -- re-asks after a timeout
local MAX_COLLECTION_ID_LENGTH = 32
-- Message kinds, the first letter of every message. The letters are the wire format; do not change them.
local KIND = { HELLO = "H", ANSWER = "A", OFFER = "O", GET = "G", DATA = "D" }

local enabled, inWorld, deferred
local friends, waiting, replied = {}, {}, {}
local active, sourcesDirty
local home, instance, guild, rosterRequested
local cachedReplies, offerQueued = {}, nil

local function Ready()
	if not enabled then return false end
	if C_ChatInfo.InChatMessagingLockdown() then
		deferred = true
		return false
	end
	return true
end

-- A whisper to someone the game cannot reach is answered with the system line ERR_CHAT_PLAYER_NOT_FOUND_S; it is only read, so a failed name is not whispered again until it has been offline.
local WHISPER_ERROR_WINDOW = 10 -- seconds after a send in which the line counts
local NOT_FOUND_PATTERN = "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%s", "(.+)") .. "$"
local whispered, unreachable = {}, {}

-- AceComm calls this as each piece leaves, which can be later than the request (ChatThrottleLib).
local function WhisperSent(target)
	whispered[target] = GetTime()
end

local function Send(text, channel, target)
	Trace("sent %s to %s%s", text, channel, target and (" " .. target) or "")
	if channel == "WHISPER" then
		if unreachable[target] then return end
		comm:SendCommMessage(PROBE_PREFIX, text, channel, target, "BULK", WhisperSent, target)
	else
		comm:SendCommMessage(PROBE_PREFIX, text, channel, target, "BULK")
	end
end

local function SendData(text, target)
	if unreachable[target] then return end
	comm:SendCommMessage(DATA_PREFIX, text, "WHISPER", target, "BULK", WhisperSent, target)
end

local failures = CreateFrame("Frame")
failures:RegisterEvent("CHAT_MSG_SYSTEM")
failures:SetScript("OnEvent", function(_, _, message)
	if not next(whispered) or issecretvalue(message) then return end
	local now = GetTime()
	for target, sent in pairs(whispered) do
		if now - sent > WHISPER_ERROR_WINDOW then whispered[target] = nil end
	end
	local name = message:match(NOT_FOUND_PATTERN)
	local sent = name and whispered[name]
	if sent then
		whispered[name] = nil
		if GetTime() - sent <= WHISPER_ERROR_WINDOW then
			unreachable[name] = true
		end
	end
end)

-- Sending and receiving are separate choices: Share My Finds sends, the level decides whether friends'
-- finds are taken in. The connection is up while either is on.
function ns.SharingWanted()
	return ns.db.shareFinds or ns.db.sourceLevel >= ns.LEVEL.FRIENDS
end

local function Receiving()
	return ns.db.sourceLevel >= ns.LEVEL.FRIENDS
end

-- A player who does not share offers revision 0, so no one asks for their finds.
local function Offer(kind)
	local exchange = ns.db.exchange
	return ("%s %s %d"):format(kind, exchange.id, ns.db.shareFinds and exchange.revision or 0)
end

local function IsGroupMember(name)
	if UnitInParty(name) then return true end
	local index = UnitInRaid(name)
	return not issecretvalue(index) and index ~= nil
end

local function IsGuildMemberByName(name)
	return IsInGuild() and C_GuildInfo.MemberExistsByName(name)
end

local function Trusted(name)
	return friends[name] or IsGuildMemberByName(name) or IsGroupMember(name)
end
-- Party, guild or friend: what the Friends level means, also for a chat line's sender.
function ns.IsTrusted(name)
	return Trusted(Ambiguate(name, "none"))
end

local function Broadcast(kind)
	local message = Offer(kind)
	if guild then Send(message, "GUILD") end
	if home then Send(message, home) end
	if instance then Send(message, "INSTANCE_CHAT") end
	for name in pairs(friends) do
		if replied[name] and not IsGuildMemberByName(name) and not IsGroupMember(name) then
			Send(message, "WHISPER", name)
		end
	end
end

function ns.ScheduleFindOffer()
	wipe(cachedReplies)
	if not enabled or offerQueued then return end
	-- A trainer or merchant visit can find dozens of recipes.
	offerQueued = true
	C_Timer.After(0, function()
		offerQueued = nil
		if Ready() then Broadcast(KIND.OFFER) end
	end)
end

local function Encode(rows)
	local bytes = C_EncodingUtil.SerializeCBOR(rows)
	local compressed = bytes and C_EncodingUtil.CompressString(bytes, Enum.CompressionMethod.Deflate)
	return compressed and C_EncodingUtil.EncodeBase64(compressed)
end

local function Decode(text)
	if #text > RECEIVE_LIMIT then return nil end
	local compressed = C_EncodingUtil.DecodeBase64(text)
	local bytes = compressed and C_EncodingUtil.DecompressString(compressed, Enum.CompressionMethod.Deflate)
	if not bytes or #bytes > EXPANDED_LIMIT then return nil end
	return C_EncodingUtil.DeserializeCBOR(bytes)
end

-- Builds the reply for one request, halving the row count until it fits SEND_LIMIT; cached per starting revision, so a new find clears it.
local function Reply(after)
	local cached = cachedReplies[after]
	if cached then return cached end
	local limit = MAX_ROWS
	while true do
		local rows, through = ns.FindsSince(after, limit)
		local encoded = Encode(rows)
		if not encoded then return nil end
		if #encoded <= SEND_LIMIT or limit <= 1 then
			local message = ("%s %s %d %d %s"):format(KIND.DATA, ns.db.exchange.id, after, through, encoded)
			cachedReplies[after] = message
			return message
		end
		limit = math.floor(limit / 2)
	end
end

local function FlushChanges()
	if sourcesDirty then
		sourcesDirty = nil
		ns.SourcesChanged()
	end
end

local NextPeer
local function FinishRequest()
	if active and active.timer then active.timer:Cancel() end
	active = nil
	FlushChanges()
	NextPeer()
end

local function Ask(peer)
	Trace("asked %s for finds %d to %d (%d tries left)", peer.sender, peer.after, peer.tip, peer.retries)
	if peer.timer then peer.timer:Cancel() end
	SendData(("%s %s %d"):format(KIND.GET, peer.id, peer.after), peer.sender)
	peer.timer = C_Timer.NewTimer(REQUEST_TIMEOUT, function()
		if active ~= peer then return end
		Trace("no answer from %s", peer.sender)
		if peer.retries > 0 and Ready() and Trusted(peer.sender) then
			peer.retries = peer.retries - 1
			Ask(peer)
		else
			FinishRequest()
		end
	end)
end

-- One request at a time; the rest wait.
NextPeer = function()
	if active or not Ready() then return end
	for sender, peer in pairs(waiting) do
		waiting[sender] = nil
		peer.after = ns.db.exchange.received[peer.id] or 0
		if peer.after < peer.tip and Trusted(sender) then
			active = peer
			Ask(peer)
			return
		end
	end
end

local function QueuePeer(sender, id, tip)
	-- Revision 0 is a peer that does not share (Offer); it says nothing about our cursor for it.
	if tip == 0 then return end
	local received = ns.db.exchange.received
	-- Tip below what we saved: that collection was reset, restart from zero.
	if received[id] and tip < received[id] then
		received[id] = 0
	end
	if (received[id] or 0) >= tip then return end
	local peer = active and active.sender == sender and active or waiting[sender]
	if peer and peer.id == id then
		peer.tip = math.max(peer.tip, tip)
	else
		waiting[sender] = { sender = sender, id = id, tip = tip, retries = REQUEST_RETRIES }
	end
	NextPeer()
end

local discoveryChannels = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }

-- another addon Loader.lua VersionCheck pattern: a probe starts a 3 second timer, restarted by further probes, then one reply goes to the channel.
local REPLY_DELAY = 3
local replyTimers = {}

local function ScheduleChannelReply(channel)
	if replyTimers[channel] then
		replyTimers[channel]:Cancel()
	end
	replyTimers[channel] = C_Timer.NewTimer(REPLY_DELAY, function()
		replyTimers[channel] = nil
		if Ready() then
			Send(Offer(KIND.ANSWER), channel)
		end
	end)
end

local function ParseHeader(message)
	local kind, id, number, rest = message:match("^(%u) (%d+%-%d+) (%d+)(.*)$")
	local revision = tonumber(number)
	if not revision or revision >= ns.MAX_WIRE_NUMBER or #id > MAX_COLLECTION_ID_LENGTH then return nil end
	return kind, id, revision, rest
end

local function OnProbe(_, message, channel, sender)
	if not Ready() or issecretvalue(sender) or issecretvalue(message) then return end
	if channel == "WHISPER" then
		if not Trusted(sender) then return end
	elseif not discoveryChannels[channel] then return end
	local kind, id, revision, rest = ParseHeader(message)
	if not kind or rest ~= "" or id == ns.db.exchange.id then return end
	Trace("heard %s from %s on %s: collection %s at %d", kind, sender, channel, id, revision)
	if kind == KIND.HELLO then
		if channel == "WHISPER" then
			-- Friends outside guild and group: answer the prober directly.
			local now = GetTime()
			if not replied[sender] or now - replied[sender] >= REPLY_DELAY then
				replied[sender] = now
				Send(Offer(KIND.ANSWER), "WHISPER", sender)
			end
		else
			ScheduleChannelReply(channel)
		end
	elseif kind == KIND.ANSWER then
		replied[sender] = GetTime()
	elseif kind ~= KIND.OFFER then
		return
	end
	if Receiving() then
		QueuePeer(sender, id, revision)
	end
end

local function OnData(_, message, channel, sender)
	if not Ready() or channel ~= "WHISPER" or issecretvalue(sender) or issecretvalue(message) then return end
	if not Trusted(sender) then return end
	local kind, id, after, rest = ParseHeader(message)
	local exchange = ns.db.exchange
	if kind == KIND.GET then
		if not ns.db.shareFinds or rest ~= "" or id ~= exchange.id or after >= exchange.revision then return end
		local reply = Reply(after)
		Trace("%s asked for finds after %d: %s", sender, after, reply and ("sent " .. #reply .. " bytes") or "nothing to send")
		if reply then SendData(reply, sender) end
	elseif kind == KIND.DATA and Receiving() then
		-- Accept only the reply to our own request.
		local peer = active
		if not peer or peer.sender ~= sender or peer.id ~= id or peer.after ~= after then return end
		local through, encoded = rest:match("^ (%d+) (%S+)$")
		through = tonumber(through)
		if not through or through <= after or through >= ns.MAX_WIRE_NUMBER then return end
		local ok, rows = pcall(Decode, encoded)
		local changed, skipped
		if ok and rows then changed, skipped = ns.MergeFinds(rows, MAX_ROWS) end
		Trace("received %d bytes from %s, finds %d to %d: %s", #encoded, sender, after, through,
			not (ok and rows) and "could not be read" or changed == nil and "rejected, nothing written"
			or ("%d rows, %d skipped, %s"):format(#rows, skipped, changed and "merged" or "nothing new"))
		if changed == nil then
			-- Asked for again it would fail the same way, so the cursor moves past it.
			exchange.received[id] = through
			FinishRequest()
			return
		end
		-- The sender may have found more since its probe.
		peer.tip = math.max(peer.tip, through)
		sourcesDirty = sourcesDirty or changed
		exchange.received[id] = through
		if through < peer.tip then
			peer.after, peer.retries = through, REQUEST_RETRIES
			Ask(peer)
		else
			FinishRequest()
		end
	end
end

-- Event driven: broadcast once on joining each channel, whisper only newly online friends who won't get the group or guild probe.
local function RefreshChannels(force)
	local group = IsInGroup(LE_PARTY_CATEGORY_HOME) and
		(IsInRaid(LE_PARTY_CATEGORY_HOME) and "RAID" or "PARTY")
	local instanced = IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
	local inGuild = IsInGuild()
	local guildReady = inGuild and GetNumGuildMembers() > 0
	if inGuild and not guildReady then
		if not rosterRequested then
			rosterRequested = true
			C_GuildInfo.GuildRoster()
		end
	else
		rosterRequested = nil
	end
	local probe = Offer(KIND.HELLO)
	if guildReady and (not guild or force) then Send(probe, "GUILD") end
	if group and (group ~= home or force) then Send(probe, group) end
	if instanced and (not instance or force) then Send(probe, "INSTANCE_CHAT") end
	home, instance, guild = group, instanced, guildReady
end

local bnetPresence, changedFriends = {}, {}
local function BattleNetCharacters(index, online)
	-- BN_FRIEND_INFO_CHANGED also fires for zone or status changes; compare reachable character names before rebuilding the roster.
	local names = ""
	for j = 1, C_BattleNet.GetFriendNumGameAccounts(index) do
		local game = C_BattleNet.GetFriendGameAccountInfo(index, j)
		-- A whisper only goes to a character it can reach: online in this game, on this realm, same faction.
		if game and game.isOnline and game.isInCurrentRegion and game.clientProgram == BNET_CLIENT_WOW
			and game.wowProjectID == WOW_PROJECT_ID and game.characterName and game.characterName ~= ""
			and game.realmID == GetRealmID() and game.factionName == UnitFactionGroup("player") then
			local name = Ambiguate(game.characterName, "none")
			names = names .. "\n" .. name
			if online then online[name] = true end
		end
	end
	return names
end

local function RefreshFriends(force)
	local online = {}
	for i = 1, C_FriendList.GetNumFriends() do
		local info = C_FriendList.GetFriendInfoByIndex(i)
		if info and info.connected then online[Ambiguate(info.name, "none")] = true end
	end
	wipe(bnetPresence)
	for i = 1, BNGetNumFriends() do bnetPresence[i] = BattleNetCharacters(i, online) end
	-- A name the game could not reach is tried again once it has been offline.
	for name in pairs(unreachable) do
		if not online[name] then unreachable[name], whispered[name] = nil, nil end
	end
	local probe = Offer(KIND.HELLO)
	local previous = friends
	friends = online
	for name in pairs(online) do
		if (force or not previous[name]) and not IsGuildMemberByName(name) and not IsGroupMember(name) then
			Send(probe, "WHISPER", name)
		end
	end
end

local frame = CreateFrame("Frame")
local events = {
	"GROUP_ROSTER_UPDATE", "GROUP_JOINED", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE",
	"FRIENDLIST_UPDATE", "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_INFO_CHANGED",
	"BN_CONNECTED", "BN_DISCONNECTED", "CHAT_SERVER_RECONNECTED", "PLAYER_REGEN_ENABLED",
}
local channelDirty, friendDirty, forceChannels, forceFriends, scheduled
local function Refresh()
	scheduled = nil
	if not Ready() then return end
	if channelDirty then RefreshChannels(forceChannels) end
	if not friendDirty then
		for index in pairs(changedFriends) do
			if bnetPresence[index] ~= BattleNetCharacters(index) then
				friendDirty = true
				break
			end
		end
	end
	wipe(changedFriends)
	if friendDirty then RefreshFriends(forceFriends) end
	channelDirty, friendDirty, forceChannels, forceFriends = nil, nil, nil, nil
end

local function ScheduleRefresh()
	if not scheduled then
		scheduled = true
		C_Timer.After(0, Refresh)
	end
end

-- After either sharing setting changes: the connection follows whether either is wanted, a player who
-- starts sharing advertises at once, and one who stops taking friends' finds in drops pending requests.
function ns.SharingSettingsChanged()
	ns.SetSharing(ns.SharingWanted())
	if not enabled then return end
	if not Receiving() then
		if active and active.timer then active.timer:Cancel() end
		active = nil
		wipe(waiting)
	end
	ns.ScheduleFindOffer()
end

function ns.SetSharing(value)
	if not inWorld or enabled == value then return end
	enabled = value
	if enabled then
		comm:RegisterComm(PROBE_PREFIX, OnProbe)
		comm:RegisterComm(DATA_PREFIX, OnData)
		for _, event in ipairs(events) do frame:RegisterEvent(event) end
		channelDirty, friendDirty, forceChannels, forceFriends = true, true, true, true
		C_FriendList.ShowFriends()
		ScheduleRefresh()
	else
		comm:UnregisterComm(PROBE_PREFIX)
		comm:UnregisterComm(DATA_PREFIX)
		for _, event in ipairs(events) do frame:UnregisterEvent(event) end
		if active and active.timer then active.timer:Cancel() end
		active = nil
		wipe(waiting)
		for channel, timer in pairs(replyTimers) do
			timer:Cancel()
			replyTimers[channel] = nil
		end
		sourcesDirty = nil -- the mode change refreshes the source list
		wipe(friends)
		wipe(whispered)
		wipe(replied)
		wipe(bnetPresence)
		wipe(changedFriends)
		home, instance, guild, deferred = nil, nil, nil, nil
		wipe(cachedReplies)
		rosterRequested = nil
	end
end

frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, index)
	if event == "PLAYER_ENTERING_WORLD" and not inWorld then
		inWorld = true
		if ns.SharingWanted() then ns.SetSharing(true) end
		return
	end
	if not enabled then return end
	if event == "CHAT_SERVER_RECONNECTED" or (deferred and not C_ChatInfo.InChatMessagingLockdown()) then
		deferred = nil
		channelDirty, friendDirty, forceChannels, forceFriends = true, true, true, true
	elseif event == "GROUP_JOINED" then
		home, instance = nil, nil
		channelDirty = true
	elseif event == "GROUP_ROSTER_UPDATE" or event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
		channelDirty = true
	elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
		return
	elseif event == "BN_FRIEND_INFO_CHANGED" and index then
		changedFriends[index] = true
	else
		friendDirty = true
	end
	ScheduleRefresh()
end)

--@debug@
-- /recipevacuum sharetest: one-account check. Every reply is built by the real code, checked against the limits, decoded, merged into a scratch copy and whispered to this character over a test prefix.
-- Not covered: choosing who to share with, and the probe exchange between two players.
local TEST_PREFIX = "RecipeVacuum2T"
local TEST_TIMEOUT = 60

local function Count(layer)
	local count = 0
	for _, bucket in pairs({ layer.recipes, layer.items }) do
		for _, observations in pairs(bucket) do
			count = count + #observations
		end
	end
	return count
end

function ns.ShareSelfTest(report)
	local exchange, real = ns.db.exchange, ns.db
	local scratch = { npcs = {}, objects = {}, shared = ns.NewLayer(), itemRecipe = {}, pendingItems = {} }
	local messages, after, rowsSent, largest = {}, 0, 0, 0
	wipe(cachedReplies)
	while after < exchange.revision do
		local message = Reply(after)
		if not message then return report("FAIL: the reply after revision " .. after .. " could not be encoded") end
		local kind, id, replyAfter, rest = ParseHeader(message)
		local through, encoded = (rest or ""):match("^ (%d+) (%S+)$")
		through = tonumber(through)
		if kind ~= KIND.DATA or id ~= exchange.id or replyAfter ~= after or not through or through <= after then
			return report("FAIL: the reply after revision " .. after .. " has a header the receiver would reject")
		end
		if #encoded > SEND_LIMIT then
			report(("WARN: a reply is %d bytes, over the %d send limit (one row too large to split)"):format(#encoded, SEND_LIMIT))
		end
		local ok, rows = pcall(Decode, encoded)
		if not (ok and rows) then return report("FAIL: the reply after revision " .. after .. " does not decode") end
		ns.db = scratch
		local merged, changed, skipped = pcall(ns.MergeFinds, rows, MAX_ROWS)
		ns.db = real
		if not merged or changed == nil or skipped > 0 then
			return report("FAIL: the receiver's validation rejects the reply after revision " .. after)
		end
		messages[#messages + 1], rowsSent, largest = message, rowsSent + #rows, math.max(largest, #message)
		after = through
	end
	wipe(cachedReplies)
	local own, arrived = Count(real.found), Count(scratch.shared)
	report(("Encode and decode: %d replies, %d rows, largest %d bytes; %d of this character's %d finds arrive%s"):format(
		#messages, rowsSent, largest, arrived, own, arrived == own and "" or " (MISMATCH)"))
	if #messages == 0 then return report("Nothing to send: no finds recorded yet") end

	local received, started = 0, GetTime()
	local timeout = C_Timer.NewTimer(TEST_TIMEOUT, function()
		comm:UnregisterComm(TEST_PREFIX)
		report(("FAIL: %d of %d replies came back within %d s (the game may not deliver a whisper to yourself)"):format(
			received, #messages, TEST_TIMEOUT))
	end)
	comm:RegisterComm(TEST_PREFIX, function(_, message, channel)
		received = received + 1
		if channel ~= "WHISPER" or message ~= messages[received] then
			timeout:Cancel()
			comm:UnregisterComm(TEST_PREFIX)
			return report("FAIL: reply " .. received .. " arrived changed")
		end
		if received == #messages then
			timeout:Cancel()
			comm:UnregisterComm(TEST_PREFIX)
			report(("Through the game and back: %d of %d replies arrived unchanged in %.1f s"):format(
				received, #messages, GetTime() - started))
		end
	end)
	local me = UnitName("player")
	for _, message in ipairs(messages) do
		comm:SendCommMessage(TEST_PREFIX, message, "WHISPER", me, "BULK")
	end
	report(("Whispering %d replies to %s; the result follows"):format(#messages, me))
end
--@end-debug@
