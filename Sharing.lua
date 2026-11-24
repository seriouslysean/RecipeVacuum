local _, ns = ...
local comm = {}
LibStub("AceComm-3.0"):Embed(comm)

-- Sharing is silent: hidden addon messages (CHAT_MSG_ADDON) only.
-- 1. Probe on PROBE_PREFIX (collection ID, revision) on joining a guild or group, reconnecting, or when a
--    friend comes online. Replies follow another addon' version check.
-- 2. A peer that is behind whispers on DATA_PREFIX: "G <collection> <after>".
-- 3. The owner replies with one AceComm BULK message "D <collection> <after> <through> <payload>": every
--    observation after <after> up to <through>, capped near 4 kB encoded. The receiver asks again from
--    <through> until it reaches the tip. Request plus bulk as in another addon Transmission.lua, with data on
--    its own prefix as another addon keeps progress on another addon. AceComm splits and reassembles;
--    ChatThrottleLib paces sends and requeues throttled ones, so no manual retry.
-- The version is in both prefixes; other versions are ignored.
local PROBE_PREFIX = "RecipeVacuum2"
local DATA_PREFIX = "RecipeVacuum2D"
local SEND_LIMIT = 4000     -- encoded bytes per reply (about 16 AceComm chunks)
local RECEIVE_LIMIT = 6000  -- larger replies are rejected before decoding
local EXPANDED_LIMIT = 65536 -- decompressed bytes accepted before CBOR decoding
local MAX_ROWS = 64
local REQUEST_TIMEOUT = 30
local REQUEST_RETRIES = 2  -- re-asks after a timeout before giving up on a peer

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

local function Send(text, channel, target)
	comm:SendCommMessage(PROBE_PREFIX, text, channel, target, "BULK")
end

local function SendData(text, target)
	comm:SendCommMessage(DATA_PREFIX, text, "WHISPER", target, "BULK")
end

local function Offer(kind)
	local exchange = ns.db.exchange
	return ("%s %s %d"):format(kind, exchange.id, exchange.revision)
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
		if Ready() then Broadcast("O") end
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

-- Builds the reply for one request, halving the row count until it fits SEND_LIMIT. Cached per starting
-- revision, so peers asking after one guild probe cost one encode; any new find clears it.
local function Reply(after)
	local cached = cachedReplies[after]
	if cached then return cached end
	local limit = MAX_ROWS
	while true do
		local rows, through = ns.FindsSince(after, limit)
		local encoded = Encode(rows)
		if not encoded then return nil end
		if #encoded <= SEND_LIMIT or limit <= 1 then
			local message = ("D %s %d %d %s"):format(ns.db.exchange.id, after, through, encoded)
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
	if peer.timer then peer.timer:Cancel() end
	SendData(("G %s %d"):format(peer.id, peer.after), peer.sender)
	peer.timer = C_Timer.NewTimer(REQUEST_TIMEOUT, function()
		if active ~= peer then return end
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

-- another addon Loader.lua VersionCheck pattern: a probe on a guild or group channel starts a 3 second timer,
-- restarted by further probes, then one reply goes to the channel. Players arriving together cost each
-- member one reply, not one whisper per arrival.
local REPLY_DELAY = 3
local replyTimers = {}

local function ScheduleChannelReply(channel)
	if replyTimers[channel] then
		replyTimers[channel]:Cancel()
	end
	replyTimers[channel] = C_Timer.NewTimer(REPLY_DELAY, function()
		replyTimers[channel] = nil
		if Ready() then
			Send(Offer("A"), channel)
		end
	end)
end

local function ParseHeader(message)
	local kind, id, number, rest = message:match("^(%u) (%d+%-%d+) (%d+)(.*)$")
	local revision = tonumber(number)
	if not revision or revision > 2^32 or #id > 32 then return nil end
	return kind, id, revision, rest
end

local function OnProbe(_, message, channel, sender)
	if not Ready() or issecretvalue(sender) or issecretvalue(message) then return end
	if channel == "WHISPER" then
		if not Trusted(sender) then return end
	elseif not discoveryChannels[channel] then return end
	local kind, id, revision, rest = ParseHeader(message)
	if not kind or rest ~= "" or id == ns.db.exchange.id then return end
	if kind == "H" then
		if channel == "WHISPER" then
			-- Friends outside guild and group: answer the prober directly.
			local now = GetTime()
			if not replied[sender] or now - replied[sender] >= REPLY_DELAY then
				replied[sender] = now
				Send(Offer("A"), "WHISPER", sender)
			end
		else
			ScheduleChannelReply(channel)
		end
	elseif kind == "A" then
		replied[sender] = GetTime()
	elseif kind ~= "O" then
		return
	end
	QueuePeer(sender, id, revision)
end

local function OnData(_, message, channel, sender)
	if not Ready() or channel ~= "WHISPER" or issecretvalue(sender) or issecretvalue(message) then return end
	if not Trusted(sender) then return end
	local kind, id, after, rest = ParseHeader(message)
	local exchange = ns.db.exchange
	if kind == "G" then
		if rest ~= "" or id ~= exchange.id or after >= exchange.revision then return end
		local reply = Reply(after)
		if reply then SendData(reply, sender) end
	elseif kind == "D" then
		-- Accept only the reply to our own request.
		local peer = active
		if not peer or peer.sender ~= sender or peer.id ~= id or peer.after ~= after then return end
		local through, encoded = rest:match("^ (%d+) (%S+)$")
		through = tonumber(through)
		if not through or through <= after or through >= 2^32 then return end
		local ok, rows = pcall(Decode, encoded)
		local changed = ok and rows and ns.MergeFinds(rows, MAX_ROWS)
		if changed == nil or not (ok and rows) then
			FinishRequest() -- invalid batch: nothing was written
			return
		end
		-- The owner may have found more since its probe.
		peer.tip = math.max(peer.tip, through)
		sourcesDirty = sourcesDirty or changed
		-- Move the cursor only after the whole batch validated and merged.
		exchange.received[id] = through
		if through < peer.tip then
			peer.after, peer.retries = through, REQUEST_RETRIES
			Ask(peer)
		else
			FinishRequest()
		end
	end
end

-- Event driven: broadcast once on joining each channel, whisper only newly online friends who won't get
-- the group or guild probe.
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
	local probe = Offer("H")
	if guildReady and (not guild or force) then Send(probe, "GUILD") end
	if group and (group ~= home or force) then Send(probe, group) end
	if instanced and (not instance or force) then Send(probe, "INSTANCE_CHAT") end
	home, instance, guild = group, instanced, guildReady
end

local bnetPresence, changedFriends = {}, {}
local function BattleNetCharacters(index, online)
	-- BN_FRIEND_INFO_CHANGED also fires for zone or status changes; compare this friend's reachable
	-- character names before rebuilding the roster.
	local names = ""
	for j = 1, C_BattleNet.GetFriendNumGameAccounts(index) do
		local game = C_BattleNet.GetFriendGameAccountInfo(index, j)
		if game and game.isOnline and game.isInCurrentRegion and game.clientProgram == BNET_CLIENT_WOW
			and game.wowProjectID == WOW_PROJECT_ID and game.characterName and game.characterName ~= "" then
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
	local probe = Offer("H")
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
		sourcesDirty = nil -- the mode change refreshes the visible source list
		wipe(friends)
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
		if ns.db.shareWithFriends then ns.SetSharing(true) end
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
