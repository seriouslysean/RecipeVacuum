local _, ns = ...
local comm = {}
LibStub("AceComm-3.0"):Embed(comm)
local prefix = "RecipeVacuum1"
local enabled, inWorld, deferred
local friends, waiting, replied = {}, {}, {}
local active, sourcesDirty
local home, instance, guild, rosterRequested
local cachedPages, offerQueued

local function Ready()
	if not enabled then return false end
	if C_ChatInfo.InChatMessagingLockdown() then
		deferred = true
		return false
	end
	return true
end

local function Send(text, channel, target)
	comm:SendCommMessage(prefix, text, channel, target, "BULK")
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
	cachedPages = nil
	if not enabled or offerQueued then return end
	-- Trainer and merchant scans may discover dozens of recipes in one visit.
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
	local compressed = C_EncodingUtil.DecodeBase64(text)
	local bytes = compressed and C_EncodingUtil.DecompressString(compressed, Enum.CompressionMethod.Deflate)
	return bytes and C_EncodingUtil.DeserializeCBOR(bytes)
end

local function SendPage(sender, after, selection)
	-- Keep only eight recent pages. An identical request reuses the encoded reply.
	cachedPages = cachedPages or {}
	local slot = math.floor(after / ns.findPageSize) % 8
	local page = cachedPages[slot]
	if not page or page.after ~= after then
		page = { after = after }
		cachedPages[slot] = page
	end
	local message = selection and page.selection == selection and page.details or (not selection and page.index)
	if not message then
		local last, rows = ns.FindPage(after, selection)
		local encoded = Encode(rows)
		if not encoded then return end
		message = ("%s %s %d %d %s"):format(selection and "D" or "I", ns.db.exchange.id, after, last, encoded)
		if selection then
			page.selection, page.details = selection, message
		else
			page.index = message
		end
	end
	Send(message, "WHISPER", sender)
end

local function FinishPageRequest()
	if active and active.timer then active.timer:Cancel() end
	active = nil
end

local function FlushChanges()
	if sourcesDirty then
		sourcesDirty = nil
		ns.SourcesChanged()
	end
end

local NextPeer
local function Ask(pending)
	if pending.timer then pending.timer:Cancel() end
	local mask = pending.selection and (" " .. pending.selection) or ""
	Send(("G %s %d%s"):format(pending.id, pending.after, mask), "WHISPER", pending.sender)
	pending.timer = C_Timer.NewTimer(60, function()
		if active ~= pending then return end
		if pending.retries > 0 and Ready() and Trusted(pending.sender) then
			pending.retries = pending.retries - 1
			Ask(pending)
		else
			FinishPageRequest()
			FlushChanges()
			NextPeer()
		end
	end)
end

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
	if (ns.db.exchange.received[id] or 0) >= tip then return end
	local peer = active and active.sender == sender and active or waiting[sender]
	if peer and peer.id == id then
		peer.tip = math.max(peer.tip, tip)
	else
		waiting[sender] = { sender = sender, id = id, tip = tip, retries = 2 }
	end
	NextPeer()
end

local discoveryChannels = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }

-- Probe replies follow another addon' version check (Loader.lua, VersionCheck): a probe on a guild
-- or group channel starts a 3 second timer, restarted by further probes, and the reply goes
-- once to that channel, where every prober hears it. Several players arriving together cost
-- each member one reply instead of one whisper per arrival.
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
local function OnMessage(_, message, channel, sender)
	if not Ready() or issecretvalue(sender) or issecretvalue(message) then return end
	if channel == "WHISPER" then
		if not Trusted(sender) then return end
	elseif not discoveryChannels[channel] then return end
	local kind, id, number, rest = message:match("^([HOAGID]) (%d+%-%d+) (%d+)(.*)$")
	local revision = tonumber(number)
	if not revision or revision > 2^32 or #id > 32 then return end
	local exchange = ns.db.exchange
	if kind == "H" or kind == "O" or kind == "A" then
		if rest ~= "" or id == exchange.id then return end
		if kind == "H" then
			if channel == "WHISPER" then
				-- Friends outside the guild and group: answer the prober directly.
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
		end
		QueuePeer(sender, id, revision)
	elseif channel == "WHISPER" and kind == "G" then
		if id ~= exchange.id or revision >= exchange.revision then return end
		local mask = rest:match("^ ([01]+)$")
		if rest ~= "" and (not mask or #mask > ns.findPageSize) then return end
		SendPage(sender, revision, mask)
	elseif channel == "WHISPER" and (kind == "I" or kind == "D") then
		local pending = active
		if not pending or pending.sender ~= sender or pending.id ~= id or pending.after ~= revision then return end
		if (kind == "D") ~= (pending.selection ~= nil) then return end
		local last, encoded = rest:match("^ (%d+) (%S+)$")
		last = tonumber(last)
		if not last or last <= revision or last > revision + ns.findPageSize then return end
		local ok, rows = pcall(Decode, encoded)
		if not ok or not rows then return end
		if kind == "I" then
			local mask = ns.SelectFinds(rows, last - revision)
			if not mask then return end
			if mask:find("1", 1, true) then
				pending.selection, pending.retries = mask, 2
				Ask(pending)
				return
			end
		else
			if last ~= revision + #pending.selection then return end
			local changed = ns.MergeFindPage(rows)
			if changed == nil then return end
			sourcesDirty = sourcesDirty or changed
		end
		exchange.received[id] = last
		if last < pending.tip then
			pending.after, pending.selection, pending.retries = last, nil, 2
			Ask(pending)
		else
			FinishPageRequest()
			FlushChanges()
			NextPeer()
		end
	end
end

-- Discovery is event driven. Broadcast once on joining each channel, and whisper only
-- newly online friends who won't already receive the group or guild probe.
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
	-- BN_FRIEND_INFO_CHANGED also fires for presence changes such as zone or status.
	-- Compare just this friend's reachable character names before rebuilding the roster.
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
		comm:RegisterComm(prefix, OnMessage)
		for _, event in ipairs(events) do frame:RegisterEvent(event) end
		channelDirty, friendDirty, forceChannels, forceFriends = true, true, true, true
		C_FriendList.ShowFriends()
		ScheduleRefresh()
	else
		comm:UnregisterComm(prefix)
		for _, event in ipairs(events) do frame:UnregisterEvent(event) end
		FinishPageRequest()
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
		home, instance, guild, deferred, cachedPages = nil, nil, nil, nil, nil
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
