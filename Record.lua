-- GPL-3.0 with additional terms under section 7: README.md, "License".

local _, ns = ...

-- Records where recipes come from, for every profession, into the self-found layer (Core.lua); trainers by recipe ID from tooltips.
-- Only Enum.ItemClass.Recipe items are kept, so other loot costs one item-class check.

-- Positions are rounded to three decimals of the 0..1 map coordinate.
local COORDINATE_PRECISION = 1000

local function Round(value)
	return math.floor(value * COORDINATE_PRECISION + 0.5) / COORDINATE_PRECISION
end

function ns.GetPlayerLocation()
	local mapID = C_Map.GetBestMapForUnit("player")
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not position then
		return mapID
	end
	local x, y = position:GetXY()
	-- A position the client hides is no position: Round would do arithmetic on it.
	if not (ns.toolkit.Readable(x) and ns.toolkit.Readable(y)) then
		return mapID
	end
	mapID, x, y = ns.ZonePosition(mapID, x, y)
	return mapID, Round(x), Round(y)
end
local GetPlayerLocation = ns.GetPlayerLocation

local BUILD = ns.BUILD
local Readable, GUID = ns.toolkit.Readable, ns.toolkit.GUID
-- A name or faction the client may hide: a hidden value is nil here, as a bare test of one is a Lua error on this client.
local function Visible(value)
	return Readable(value) and value or nil
end

-- The NPC being talked to, or nil when the client hides it (secret values); saved by NoteVisit only for an NPC with a recipe.
local function CurrentNPC()
	local unitType, npcID = GUID(UnitGUID("npc"))
	if unitType ~= "Creature" then
		return nil
	end
	local seen = GetServerTime()
	local mapID, x, y = GetPlayerLocation()
	return { field = "npc", value = npcID, npcID = npcID, faction = (UnitFactionGroup("player")), seen = seen,
		name = Visible(UnitName("npc")), mapID = mapID, x = x, y = y, npcFaction = Visible((UnitFactionGroup("npc"))) }
end

-- Runs when a scan found at least one recipe, new or saved, so a trainer whose recipes are all known still refreshes its position.
local function NoteVisit(npc)
	ns.NoteNPC(ns.db.npcs, npc.npcID, npc.name, npc.mapID, npc.x, npc.y, npc.seen)
	ns.NoteNPCFaction(npc.npcID, npc.npcFaction)
end

-- A source of another kind; field is the observation field that identifies it (object, container, fishing, zone, quest, or npc).
local function Source(field, value)
	return { field = field, value = value, faction = (UnitFactionGroup("player")), seen = GetServerTime() }
end

-- Details compared on every sighting; a missing field keeps its saved value. npc is a detail for quests (the giver), the identity otherwise.
local DETAIL_FIELDS = { "faction", "skill", "cost", "price", "limited", "spellID", "choice", "npc",
	"finisher", "giverItem", "map", "x", "y", "area", "instance" }

-- Adds or updates one self-found observation; returns isNew and whether anything besides the seen time changed (which bumps the revision).
local function Save(bucket, id, kind, npc, details)
	local observations = ns.db.found[bucket][id]
	if not observations then
		observations = {}
		ns.db.found[bucket][id] = observations
	end
	local observation = ns.FindSource(observations, { kind = kind, [npc.field] = npc.value,
		map = details.map, area = details.area, instance = details.instance })
	local isNew = observation == nil
	if isNew then
		observation = { kind = kind, [npc.field] = npc.value }
		table.insert(observations, observation)
	end
	details.faction = npc.faction
	local changed = isNew
	if kind == "drop" then
		-- Each loot window is one more time seen. A repeat alone is not a new revision: farming would
		-- add one per kill, and every reply walks them; the count goes out with the next real change.
		observation.count = (observation.count or 0) + 1
	end
	for _, field in ipairs(DETAIL_FIELDS) do
		if details[field] ~= nil and observation[field] ~= details[field] then
			observation[field] = details[field]
			changed = true
		end
	end
	-- No deletion on absence: a visit only refreshes seen time and build.
	observation.seen, observation.build = npc.seen, BUILD
	if changed then
		ns.MarkFind(observation, bucket == "items" and "item" or "recipe", id)
	end
	return isNew, changed
end

local function Announce(count, name)
	if count > 0 and ns.db.announceNewFinds then
		ns.toolkit:Say(ns.module, ns.voice.intake, count, name or UNKNOWN)
	end
end

-- A recipe item waits here until its tooltip data loads and names its recipe (ns.LinkPending).
local function NotePendingItem(itemID)
	if not ns.db.itemRecipe[itemID] and not ns.GetSeededRecipe(itemID) then
		ns.db.pendingItems[itemID] = ns.db.pendingItems[itemID] or {}
	end
end

local function IsRecipeItem(itemID)
	return itemID ~= nil and ns.IsRecipeItem(itemID) ~= nil
end

-- Some NPCs teach recipes without the profession trainer flag, so a service counts only when its spell belongs to a profession (docs/client-notes.md, "Trainers").
-- The scan reads what the window shows under the player's own filters and never sets one: a filter change makes Blizzard's trainer list
-- rebuild (TRAINER_UPDATE), which showed as a flicker (docs/client-notes.md, "Trainers").
local TRAINER_SERVICE_TYPES = { "available", "unavailable", "used" }

-- The spell a trainer's service teaches is saved per account, by NPC and the service's name (RecipeVacuumDB.trainerSpells, docs/data.md): the
-- name is only a key into what the tooltip said, the recipe is matched by the spell's ID. A trainer is read once, on any character.
local trainerMisses = {} -- "npcID:service name" = tooltip reads that gave no spell this session; capped like an item that never answers
local trainerJob -- the scan in progress: { npc, professionTrainer, index, services, skipped, ... }

-- The first read of a trainer is a tooltip per service (about 1.5 ms each on the Deck, 23 to 33 ms in all), so it runs in steps of
-- TRAINER_STEP_MS, one frame apart; a service already in the saved spell cache costs none. A step ends before a tooltip would pass the
-- 5 ms frame bar, so the budget is the bar less one tooltip (docs/client-notes.md, "Trainers").
local TRAINER_STEP_MS = 3
local TRAINER_MAX_RESTARTS = 5 -- the list changed under a scan this many times (filters, a purchase): stop and let the next update ask again
local FinishScan -- defined below, after Scan's pieces
local LearnedStep -- the read of learned services, below
local QueueLearned
-- Our own filter change fires TRAINER_UPDATE; those are counted and not taken for the player's change (docs/client-notes.md, "Trainers").
local LEARNED_SETTLE = 0.5 -- seconds the window for our own TRAINER_UPDATEs stays open
local ownWindow, ownUpdates

local function CachedSpell(npcID, name)
	local byName = ns.db.trainerSpells[npcID]
	return byName and byName[name]
end

-- The spell ID in a service's tooltip, from the saved cache or one tooltip read; also the ms the read took and whether a tooltip was read.
-- Forever's TooltipUtil.GetDisplayedSpell checks the tooltip type before reading id. One trainer's services of a name teach the same spell;
-- one that gave no spell is asked again only up to MAX_ITEM_ATTEMPTS.
local function ReadServiceSpell(npcID, name, index)
	local spellID = CachedSpell(npcID, name)
	if spellID then return spellID, 0, false end
	local key = npcID .. ":" .. name
	if (trainerMisses[key] or 0) >= ns.MAX_ITEM_ATTEMPTS then return nil, 0, false end
	local started = debugprofilestop()
	local tooltip = C_TooltipInfo.GetTrainerService(index)
	local ms = debugprofilestop() - started
	spellID = tooltip and tooltip.type == Enum.TooltipDataType.Spell and tooltip.id
	if spellID then
		local byName = ns.db.trainerSpells[npcID]
		if not byName then
			byName = {}
			ns.db.trainerSpells[npcID] = byName
		end
		byName[name] = spellID
	else
		trainerMisses[key] = (trainerMisses[key] or 0) + 1
		if trainerMisses[key] >= ns.MAX_ITEM_ATTEMPTS then
			ns.toolkit:Trace(ns.module, "trainer service skipped", "name", name, "npc", npcID, "misses", trainerMisses[key], "reason", "no_spell")
		end
	end
	return spellID, ms, true
end

local function EndTrainerJob(job)
	if trainerJob == job then trainerJob = nil end
end

-- A scan that ends before its finish frame still saved the recipes it read, so the visit's count and the panel's sources follow.
local function AbortTrainerJob(job, reason)
	if trainerJob ~= job then return end
	ns.toolkit:Trace(ns.module, "trainer scan stopped", "service", job.index, "of", job.services, "reason", reason, "kept_new", job.count)
	EndTrainerJob(job)
	FinishScan(job.count, job.npc, job.changed)
end

local function Skip(job, reason)
	job.skipped[reason] = (job.skipped[reason] or 0) + 1
end

-- "used 1, no spell 2" for the trace.
-- Skip counts as log pairs, by reason in a stable order: "skipped_<reason>", n.
local function SkippedPairs(skipped)
	local reasons, out = {}, {}
	for reason in pairs(skipped) do reasons[#reasons + 1] = reason end
	table.sort(reasons)
	for _, reason in ipairs(reasons) do
		out[#out + 1], out[#out + 2] = "skipped_" .. reason:gsub("[^%w]+", "_"):lower(), skipped[reason]
	end
	if #out == 0 then out[1], out[2] = "skipped", 0 end
	return out
end

-- Which of the player's filters hide a type of service, for the trace; they are only read.
local function HiddenTypes()
	local hidden = {}
	for _, serviceType in ipairs(TRAINER_SERVICE_TYPES) do
		if not GetTrainerServiceTypeFilter(serviceType) then
			hidden[#hidden + 1] = serviceType
		end
	end
	return #hidden > 0 and table.concat(hidden, ",") or "none"
end

local function ReadTrainerService(job, index)
	local npc = job.npc
	local name, serviceType, _, _, _, category = GetTrainerServiceInfo(index)
	if not name then
		Skip(job, "no name yet")
	elseif serviceType == "header" then
		Skip(job, "header")
	elseif index == job.stepIndex then
		Skip(job, "rank step")
	elseif not category or category == "" then
		Skip(job, "no category")
	else
		local _, skillRank = GetTrainerServiceSkillReq(index)
		local cost = GetTrainerServiceCost(index)
		local spellID, tooltipMs = ReadServiceSpell(npc.npcID, name, index)
		job.tooltipMs = job.tooltipMs + tooltipMs
		-- No Spell tooltip means no recipe ID; skip it.
		if not spellID then
			Skip(job, "no spell")
		elseif job.professionTrainer or C_TradeSkillUI.GetTradeSkillLineForRecipe(spellID) then
			-- Blizzard hides a learned row's cost and skill, so 0 on a "used" row is "not shown" and never saved over a real value.
			local details = { skill = skillRank, cost = cost }
			if serviceType == "used" then
				if not (skillRank and skillRank > 0) then details.skill = nil end
				if not (cost and cost > 0) then details.cost = nil end
			end
			local isNew, updated = Save("recipes", spellID, "trainer", npc, details)
			job.line = job.line or ns.ProfessionLine(C_TradeSkillUI.GetTradeSkillLineForRecipe(spellID))
			job.recipes = job.recipes + 1
			job.changed = job.changed or updated
			if isNew then job.count = job.count + 1 end
		else
			Skip(job, "not a profession")
		end
	end
end

local function TrainerStep(job)
	if trainerJob ~= job then return end -- the window closed or another trainer opened
	local started = debugprofilestop()
	-- The player changed a filter (or a purchase moved the list): the indices read so far are stale, so read again from the top. Services
	-- already asked for cost no tooltip (the spell cache), so a restart is cheap.
	if job.stale then
		job.stale = nil
		job.restarts = job.restarts + 1
		if job.restarts > TRAINER_MAX_RESTARTS then
			AbortTrainerJob(job, ("the list kept changing through %d restarts"):format(TRAINER_MAX_RESTARTS))
			return
		end
		ns.toolkit:Trace(ns.module, "trainer list changed", "service", job.index, "of", job.services, "restart", job.restarts)
		job.services, job.stepIndex = GetNumTrainerServices(), GetTrainerServiceStepIndex()
		job.index, job.first, job.recipes, job.tooltipMs = 1, 1, 0, 0
		wipe(job.skipped)
	end
	job.steps = job.steps + 1
	while job.index <= job.services and (job.index == job.first or debugprofilestop() - started < TRAINER_STEP_MS) do
		ReadTrainerService(job, job.index)
		job.index = job.index + 1
	end
	local stepMs = debugprofilestop() - started
	job.ms = job.ms + stepMs
	job.worstMs = math.max(job.worstMs, stepMs)
	--@debug@
	ns.PerfMs("trainer scan step", debugprofilestop() - started)
	--@end-debug@
	if job.index <= job.services then
		job.first = job.index
		RunNextFrame(function() TrainerStep(job) end)
		return
	end
	-- The closing work is one step a frame (the rank read is a tooltip, the finish saves and redraws), each timed (docs/client-notes.md, "Trainers").
	local function Closing(name, work, after)
		RunNextFrame(function()
			if trainerJob ~= job then return end
			if job.stale then return TrainerStep(job) end
			local closeStart = debugprofilestop()
			work()
			local ms = debugprofilestop() - closeStart
			job.closingMs = job.closingMs + ms
			--@debug@
			ns.PerfMs("trainer scan " .. name, ms)
			--@end-debug@
			if after then after() end
		end)
	end
	Closing("rank", function()
		-- The trainer's next rank for this character (Blizzard's trainer window shows it apart, as its skill step).
		if job.professionTrainer and ns.NoteTrainerRank(job.npc.npcID) then
			job.rankNoted = true
		end
	end, function()
		Closing("visit", function()
			if job.rankNoted or job.recipes > 0 then NoteVisit(job.npc) end
		end, function()
			-- The job is over; the last step runs unguarded.
			EndTrainerJob(job)
			RunNextFrame(function()
				local finishStart = debugprofilestop()
				FinishScan(job.count, job.npc, job.changed)
				local ms = debugprofilestop() - finishStart
				--@debug@
				ns.PerfMs("trainer scan finish", ms)
				ns.PerfMs("trainer scan tooltips", job.tooltipMs)
				--@end-debug@
				ns.toolkit:Trace(ns.module, "trainer scan", "services", job.services, "steps", job.steps, "ms", job.ms,
					"tooltip_ms", job.tooltipMs or 0, "worst_step_ms", job.worstMs, "close_ms", job.closingMs, "finish_ms", ms,
					"recipes", job.recipes, "new", job.count, "filters_off", HiddenTypes(), "restarts", job.restarts,
					unpack(SkippedPairs(job.skipped)))
				-- The learned read waits for the frame after this one.
				QueueLearned(job.npc, job.recipes > 0, job.line)
			end)
		end)
	end)
end

-- Learned ("used") services: a series of atomic one-frame passes, each with "used" on only inside its own frame, reading a few spell IDs
-- from tooltips; the batch is sized from the measured pass and a pass always reads one service, so it never starves
-- (docs/client-notes.md, "Trainers").
local LEARNED_PASS_MS = 4 -- the batch is sized to this, under the 5 ms bar
local FRAME_BAR_MS = 5 -- the kit's frame bar; a one-service pass over it is the named atomic exception
local LEARNED_START_BATCH = 1
local LEARNED_MAX_PASSES = 300 -- a hard cap on the passes of one read; no trainer lists this many services
local learned = {} -- [npcID] = { attempts, done, visit }: this session's reads of that trainer's learned services
-- A trainer read to the end is done for the account (ns.db.learnedReads, docs/data.md, "Learned reads"): what a trainer hides as learned
-- differs by character only in which rows are hidden, so a character asks again only when it knows a recipe of that profession with no
-- trainer source recorded since the read (ns.NoteUnsourced, from the profession window's read of known recipes).
local function CharacterKey() return UnitGUID("player") or "?" end

local function UnsourcedRev(line)
	local mine = ns.db.unsourcedKnown[CharacterKey()]
	local byLine = mine and line and mine[line]
	return byLine and byLine.rev or 0
end

local function HasTrainerSource(recipeID)
	for _, observation in ipairs(ns.db.found.recipes[recipeID] or {}) do
		if observation.kind == "trainer" then return true end
	end
	return false
end

-- A known recipe of skill line `line` with no trainer source; true when it is new for this character, which makes done trainers of
-- that profession ask once more.
function ns.NoteUnsourced(line, recipeID)
	if not line or HasTrainerSource(recipeID) then return false end
	local key = CharacterKey()
	local mine = ns.db.unsourcedKnown[key] or {}
	ns.db.unsourcedKnown[key] = mine
	local byLine = mine[line] or { rev = 0, ids = {} }
	mine[line] = byLine
	if byLine.ids[recipeID] then return false end
	byLine.ids[recipeID], byLine.rev = true, byLine.rev + 1
	return true
end
-- Each trainer window shown is one visit; a read runs at most once a visit, so a pass that finds nothing waits for a later visit instead of
-- toggling the filter again when the scan finishes (docs/client-notes.md, "Trainers").
local visitSerial = 0
local learnedQueued -- the npcID whose read is queued or running; one at a time
local learnedJob -- the read in progress

local ownTimer, ownNpc

-- Closes the window for our own TRAINER_UPDATEs; the split (inside the filter calls, between passes) is in the finish line, the total here.
local function EndOwnWindow(reason)
	if not ownWindow then return end
	if ownTimer then ownTimer:Cancel() end
	ownTimer, ownWindow = nil, nil
	ns.toolkit:Trace(ns.module, "trainer updates", "npc", ownNpc, "count", ownUpdates or 0, "reason", reason, "used_filter", GetTrainerServiceTypeFilter("used"))
end

-- Blizzard's trainer list selection and gamepad focus, read only, for the Deck to compare before and after our filter calls.
local function SelectionPairs(prefix)
	local window = ClassTrainerFrame
	local button = window and window.isFocused and SmartNavigation and SmartNavigation:GetCurrentButton()
	prefix = prefix or ""
	return { prefix .. "selection", GetTrainerSelectionIndex(), prefix .. "window_service", window and window.selectedService,
		prefix .. "focused", window and window.isFocused or false, prefix .. "cursor_service", button and button.displayIndex }
end

-- Two pair lists as one, for a log call that ends with both.
local function Joined(first, second)
	local out = {}
	for _, list in ipairs({ first, second }) do
		for index = 1, #list do out[#out + 1] = list[index] end
	end
	return out
end

local function AtTrainer(npc)
	local unitType, npcID = GUID(UnitGUID("npc"))
	return unitType == "Creature" and npcID == npc.npcID
end

local function LearnedState(npcID)
	local state = learned[npcID]
	if not state then
		state = { attempts = 0 }
		learned[npcID] = state
	end
	return state
end

-- Ends the read, keeping what it saved; the trainer is asked again on a later visit unless every service was read.
local function EndLearned(job, reason)
	if learnedJob ~= job then return end
	learnedJob, learnedQueued = nil, nil
	local state = job.state
	if reason == "done" then
		state.done = not job.gap or state.attempts >= ns.MAX_ITEM_ATTEMPTS
		if not job.gap then
			local read = ns.db.learnedReads[job.npc.npcID] or { revs = {} }
			read.line = job.line or read.line
			read.revs[CharacterKey()] = UnsourcedRev(read.line)
			ns.db.learnedReads[job.npc.npcID] = read
		end
	elseif reason == "the player shows learned services" then
		state.done = true -- the window lists them, so the scan reads them
	end
	if job.saved > 0 then NoteVisit(job.npc) end
	FinishScan(job.count, job.npc, job.changed)
	-- The window for our own updates stays open a moment after the last pass, for the deferred ones.
	if ownWindow then
		if ownTimer then ownTimer:Cancel() end
		local timer
		timer = C_Timer.NewTimer(LEARNED_SETTLE, function()
			if ownTimer == timer then EndOwnWindow("settled") end
			ns.toolkit:Trace(ns.module, "trainer settled", "npc", job.npc.npcID, unpack(SelectionPairs()))
		end)
		ownTimer = timer
	end
	ns.toolkit:Trace(ns.module, "trainer read", "npc", job.npc.npcID, "result", reason, "passes", job.passes, "used", job.seen,
		"tooltips", job.tooltips, "tooltip_ms", job.tooltipMs, "cached", job.cached, "saved", job.saved, "new", job.count,
		"ms", job.ms, "worst_pass_ms", job.worstMs, "over_bar", job.exceptions, "bar_ms", FRAME_BAR_MS, "list_changes", job.restarts,
		"updates_inside", job.during, "updates_between", job.after, "attempt", state.attempts, "done", state.done and true or false,
		unpack(SkippedPairs(job.skipped)))
end

-- Why the read must end before this pass, or nil.
local function LearnedStopReason(job)
	if not AtTrainer(job.npc) then return "the window closed or another trainer opened" end
	if InCombatLockdown() then return "combat" end
	if GetTrainerServiceTypeFilter("used") then return "the player shows learned services" end
	local shown = GetNumTrainerServices()
	if job.shown and shown ~= job.shown then
		-- The player changed a filter or bought something; the next pass walks the new list from its names, so only the count of changes is kept.
		job.restarts = job.restarts + 1
		ns.toolkit:Trace(ns.module, "trainer list moved", "npc", job.npc.npcID, "from", job.shown, "to", shown, "change", job.restarts)
		if job.restarts > TRAINER_MAX_RESTARTS then return ("the list kept changing through %d changes"):format(TRAINER_MAX_RESTARTS) end
	end
	if job.passes >= LEARNED_MAX_PASSES then return "the pass cap" end
end

-- One atomic pass. Rows are named in the walk and read by index in the same frame, because indices exist only while the filter is on.
local function LearnedPass(job)
	if learnedJob ~= job then return end
	local reason = LearnedStopReason(job)
	if reason then
		ns.toolkit:Trace(ns.module, "trainer read stopped", "npc", job.npc.npcID, "reason", reason)
		return EndLearned(job, reason)
	end
	local npc = job.npc
	local logging = ns.toolkit:IsLogging(ns.module)
	local selectionBefore = logging and SelectionPairs("before_") or {}
	job.passes = job.passes + 1
	job.after = job.after + (ownUpdates - job.updatesAtEnd)
	local updatesBefore = ownUpdates
	local started = debugprofilestop()
	SetTrainerServiceTypeFilter("used", true)
	local onMs = debugprofilestop() - started
	local tipMs, tooltips, cached, pending, resolved, processed = 0, 0, 0, 0, {}, 0
	local shownDuring, usedRows, left = 0, 0, 0
	local ok, failure = pcall(function()
		local stepIndex = GetTrainerServiceStepIndex()
		shownDuring = GetNumTrainerServices()
		local rows = {}
		for serviceIndex = 1, shownDuring do
			local name, serviceType, _, _, _, category = GetTrainerServiceInfo(serviceIndex)
			if serviceType == "used" then
				usedRows = usedRows + 1
				if not name then
					job.gap = true
					Skip(job, "no name yet")
				elseif serviceIndex == stepIndex or not category or category == "" then
					job.done[name] = true -- a rank, not a recipe
				elseif not job.done[name] then
					rows[#rows + 1] = { index = serviceIndex, name = name }
				end
			end
		end
		pending = #rows
		for _, row in ipairs(rows) do
			local spellID = CachedSpell(npc.npcID, row.name)
			-- A pass always takes one row (no starvation), then stops at its tooltip batch or its time.
			if processed > 0 and ((not spellID and tooltips >= job.batch) or debugprofilestop() - started >= LEARNED_PASS_MS) then
				left = left + 1
			else
				processed = processed + 1
				if spellID then
					cached = cached + 1
				else
					local read, ms
					spellID, ms, read = ReadServiceSpell(npc.npcID, row.name, row.index)
					tipMs = tipMs + ms
					if read then tooltips = tooltips + 1 end
				end
				job.done[row.name] = true
				if spellID then
					local _, skillRank = GetTrainerServiceSkillReq(row.index)
					resolved[#resolved + 1] = { spellID = spellID, skill = skillRank, cost = GetTrainerServiceCost(row.index) }
				else
					job.gap = true
					Skip(job, "no spell")
				end
			end
		end
	end)
	local offStarted = debugprofilestop()
	local restored, restoreFailure = pcall(SetTrainerServiceTypeFilter, "used", false)
	local offMs = debugprofilestop() - offStarted
	local filterBack = GetTrainerServiceTypeFilter("used")
	local during = ownUpdates - updatesBefore
	job.during, job.updatesAtEnd = job.during + during, ownUpdates
	job.shown = GetNumTrainerServices()
	local atomicMs = debugprofilestop() - started
	if not ok then geterrorhandler()(failure) end
	if not restored then geterrorhandler()(restoreFailure) end
	-- Saving is outside the filter calls but inside the frame, so it is in the pass's time.
	for _, row in ipairs(resolved) do
		if job.professionTrainer or C_TradeSkillUI.GetTradeSkillLineForRecipe(row.spellID) then
			-- Blizzard hides a learned row's cost and skill, so 0 is "not shown", never a value to save over a real one.
			local details = {}
			if row.skill and row.skill > 0 then details.skill = row.skill end
			if row.cost and row.cost > 0 then details.cost = row.cost end
			local isNew, updated = Save("recipes", row.spellID, "trainer", npc, details)
			job.saved = job.saved + 1
			job.changed = job.changed or updated
			if isNew then job.count = job.count + 1 end
		else
			Skip(job, "not a profession")
		end
	end
	local passMs = debugprofilestop() - started
	job.ms, job.worstMs = job.ms + passMs, math.max(job.worstMs, passMs)
	job.seen, job.tooltips, job.cached, job.tooltipMs = job.seen + #resolved, job.tooltips + tooltips, job.cached + cached, job.tooltipMs + tipMs
	--@debug@
	ns.PerfMs("trainer learned pass", passMs)
	--@end-debug@
	local batch = job.batch
	if tooltips > 0 and passMs > 0 then
		-- Sized from the measured pass (fixed costs included, so it errs small); never below one, and at most doubling a step.
		job.batch = math.max(1, math.min(batch * 2, math.floor(batch * LEARNED_PASS_MS / passMs)))
	end
	local exception = passMs > FRAME_BAR_MS and tooltips <= 1
	if exception then job.exceptions = job.exceptions + 1 end
	ns.toolkit:Trace(ns.module, "trainer pass", "n", job.passes, "npc", npc.npcID, "used", usedRows, "to_read", pending,
		"tooltips", tooltips, "cached", cached, "left", left, "filter_on_ms", onMs, "tooltip_ms", tipMs, "filter_off_ms", offMs,
		"window_ms", atomicMs, "ms", passMs, "batch", batch, "next_batch", job.batch, "atomic", exception and true or false,
		"updates_inside", during, "updates_between", job.after, "filter_back", filterBack and true or false,
		unpack(Joined(selectionBefore, logging and SelectionPairs("after_") or {})))
	if not ok or not restored or filterBack then
		return EndLearned(job, "an error")
	end
	if left > 0 then
		RunNextFrame(function() LearnedPass(job) end)
	else
		EndLearned(job, "done")
	end
end

-- Once per trainer and session after the scan's finish frame, only when the player hides "used", at a profession trainer, out of combat,
-- and still at that trainer. hadRecipes: the scan saved a recipe here (some NPCs teach recipes without the trainer flag).
function LearnedStep(npc, hadRecipes, line)
	if trainerJob or not AtTrainer(npc) then -- a rescan is running and queues this again at its end
		learnedQueued = nil
		return
	end
	local state = LearnedState(npc.npcID)
	if state.visit == visitSerial then
		ns.toolkit:Trace(ns.module, "trainer read skipped", "npc", npc.npcID, "reason", "read_this_visit", "attempt", state.attempts)
		learnedQueued = nil
		return
	end
	if state.done then
		learnedQueued = nil
		return
	end
	if not (IsTradeskillTrainer() or hadRecipes) then
		ns.toolkit:Trace(ns.module, "trainer read skipped", "npc", npc.npcID, "reason", "not_profession_trainer")
		learnedQueued = nil
		return
	end
	if InCombatLockdown() then
		ns.toolkit:Trace(ns.module, "trainer read skipped", "npc", npc.npcID, "reason", "combat")
		learnedQueued = nil
		return
	end
	if GetTrainerServiceTypeFilter("used") then
		state.done = true
		learnedQueued = nil
		return -- the window shows them, so the scan read them
	end
	state.attempts = state.attempts + 1
	state.visit = visitSerial
	if state.attempts > ns.MAX_ITEM_ATTEMPTS then
		state.done = true
		learnedQueued = nil
		ns.toolkit:Trace(ns.module, "trainer read skipped", "npc", npc.npcID, "reason", "attempts", "attempts", state.attempts - 1)
		return
	end
	local job = { npc = npc, line = line, state = state, professionTrainer = IsTradeskillTrainer(), done = {}, skipped = {}, batch = LEARNED_START_BATCH,
		passes = 0, seen = 0, tooltips = 0, cached = 0, saved = 0, count = 0, changed = false, gap = false, ms = 0, worstMs = 0, tooltipMs = 0,
		exceptions = 0, restarts = 0, during = 0, after = 0, updatesAtEnd = 0 }
	learnedJob = job
	if ownTimer then ownTimer:Cancel() end
	ownTimer, ownWindow, ownUpdates, ownNpc = nil, true, 0, npc.npcID
	ns.toolkit:Trace(ns.module, "trainer read start", "npc", npc.npcID, "services", GetNumTrainerServices(),
		"attempt", state.attempts, "batch", job.batch, unpack(ns.toolkit:IsLogging(ns.module) and SelectionPairs() or {}))
	LearnedPass(job)
end

function QueueLearned(npc, hadRecipes, line)
	if learnedQueued then return end
	local read = ns.db.learnedReads[npc.npcID]
	if not read and learned[npc.npcID] and learned[npc.npcID].done then return end -- this session's reads ran out on gaps
	if read then
		local rev, seen = UnsourcedRev(read.line or line), read.revs[CharacterKey()] or 0
		if rev <= seen then
			ns.toolkit:Trace(ns.module, "trainer read skipped", "npc", npc.npcID, "reason", "done", "line", read.line or line, "unsourced_rev", rev, "read_at", seen)
			return
		end
		ns.toolkit:Trace(ns.module, "trainer read again", "npc", npc.npcID, "new_unsourced", rev - seen, "line", read.line or line)
	end
	if read then learned[npc.npcID] = nil end -- a re-ask is a fresh read, whatever this session read before
	learnedQueued = npc.npcID
	RunNextFrame(function() LearnedStep(npc, hadRecipes, line) end)
end

-- Starts the scan; true when the services are there, false when the window has none yet (the caller asks again on the next update).
local function RecordTrainer()
	if not ns.db.selfFound then
		return true
	end
	local professionTrainer = IsTradeskillTrainer()
	local npc = CurrentNPC()
	if not npc then
		-- The client can hide the NPC's GUID at the show; the next update asks again.
		ns.toolkit:Trace(ns.module, "trainer waits", "reason", "no_creature")
		return false
	end
	if trainerJob or learnedJob then
		ns.toolkit:Trace(ns.module, "trainer busy", "job", trainerJob and "scan" or "read")
		return true
	end
	local services = GetNumTrainerServices()
	if services == 0 then
		return false -- the window has none yet; the next update asks again, and the learned read waits for a finished scan
	end
	local job = { npc = npc, professionTrainer = professionTrainer, index = 1, first = 1, services = services,
		-- A recipe has a category; a profession rank has none.
		stepIndex = GetTrainerServiceStepIndex(), count = 0, recipes = 0, changed = false, steps = 0, ms = 0, worstMs = 0, tooltipMs = 0, closingMs = 0, restarts = 0, skipped = {} }
	trainerJob = job
	local hidden = HiddenTypes()
	if hidden ~= "none" then
		-- Services of a hidden type are not in the list, so they are not seen and their count is not known without changing the filter.
		ns.toolkit:Trace(ns.module, "trainer filters", "off", hidden)
	end
	TrainerStep(job)
	return true
end

-- Vendor recipe items; also runs on MERCHANT_UPDATE, since a row's details can arrive after the window opens.
local missingItems = {}
local function RecordVendor()
	if not ns.db.selfFound then
		return 0
	end
	local npc = CurrentNPC()
	if not npc then
		return 0
	end
	local count, recipes = 0, 0
	local changed = false
	local items = GetMerchantNumItems()
	for index = 1, items do
		local itemID = GetMerchantItemID(index)
		if IsRecipeItem(itemID) then
			local info = C_MerchantFrame.GetItemInfo(index)
			-- The row can arrive after the window opens; MERCHANT_UPDATE reads it again.
			if not info then
				missingItems[itemID] = true
			end
			if info then
				NotePendingItem(itemID)
				local isNew, updated = Save("items", itemID, "vendor", npc, {
					spellID = info.spellID,
					price = info.price,
					limited = info.numAvailable >= 0,
				})
				recipes = recipes + 1
				changed = changed or updated
				if isNew then count = count + 1 end
			end
		end
	end
	if recipes > 0 then NoteVisit(npc) end
	return count, npc, items > 0, changed
end

-- Coalesce late names within the visit and report the total once; filter changes also fire TRAINER_UPDATE, so wait for service names.
local SCAN_DELAY = 0.2
local frame -- made below, once its handlers exist
local record, timer, visitNPC
local newSources = 0

local function FinishVisit()
	if timer then
		timer:Cancel()
		timer = nil
	end
	if trainerJob then
		AbortTrainerJob(trainerJob, "the visit ended")
	end
	if learnedJob then
		ns.toolkit:Trace(ns.module, "trainer read stopped", "npc", learnedJob.npc.npcID, "reason", "visit_ended")
		EndLearned(learnedJob, "the visit ended")
	end
	EndOwnWindow("the visit ended")
	Announce(newSources, visitNPC and (ns.GetNPC(visitNPC.npcID) or {}).name)
	newSources, visitNPC, record = 0, nil, nil
	wipe(missingItems)
	frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
end

-- What follows a scan, whether it ran at once (a vendor) or in steps (a trainer).
function FinishScan(count, npc, changed)
	if next(missingItems) then
		frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	else
		frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	end
	if count > 0 then
		newSources, visitNPC = newSources + count, npc
	end
	if count > 0 or changed then
		ns.SourcesChanged()
	end
end

local function Scan()
	timer = nil
	wipe(missingItems)
	if record == RecordTrainer then
		return RecordTrainer()
	end
	--@debug@
	local perfStart = debugprofilestop()
	--@end-debug@
	local count, npc, ready, changed = record()
	--@debug@
	ns.Perf("vendor scan", perfStart)
	--@end-debug@
	FinishScan(count, npc, changed)
	return ready
end

local function OnVisitEvent(event, itemID)
	if event == "TRAINER_UPDATE" and ownWindow then
		ownUpdates = ownUpdates + 1
		return
	end
	if event == "TRAINER_SHOW" or event == "MERCHANT_SHOW" then
		FinishVisit()
		if event == "TRAINER_SHOW" then visitSerial = visitSerial + 1 end
		record = event == "TRAINER_SHOW" and RecordTrainer or RecordVendor
		if not ns.db.selfFound or Scan() then
			return
		end
	elseif (event == "TRAINER_CLOSED" and record == RecordTrainer)
		or (event == "MERCHANT_CLOSED" and record == RecordVendor) then
		FinishVisit()
	elseif trainerJob and (event == "TRAINER_UPDATE" or (event == "TRAINER_SERVICE_INFO_NAME_UPDATE" and trainerJob.skipped["no name yet"])) then
		-- Filters and purchases fire TRAINER_UPDATE, and a name that arrives after the scan skipped its service fills it in; either way a
		-- scan in progress reads again from the top (services read before cost no tooltip), as the 0.2 s timer would find the job still running.
		trainerJob.stale = true
		return
	elseif not ((record == RecordTrainer and (event == "TRAINER_SERVICE_INFO_NAME_UPDATE" or event == "TRAINER_UPDATE"))
		or (record == RecordVendor and (event == "MERCHANT_UPDATE" or missingItems[itemID]))) then
		return
	end
	if record and not timer then
		timer = C_Timer.NewTimer(SCAN_DELAY, Scan)
	end
end

--@debug@
-- Working-build test: one learned read at the open trainer, whatever this session's reads did, to see whether "used" rows appear at all.
function ns.ReadLearnedNow()
	local npc = CurrentNPC()
	if record ~= RecordTrainer or not npc then
		ns.toolkit:Print("Open a trainer first.")
		return
	end
	if learnedJob or trainerJob then
		ns.toolkit:Print("A trainer read is running; press again when it ends.")
		return
	end
	learned[npc.npcID] = nil
	learnedQueued = npc.npcID
	ns.toolkit:Trace(ns.module, "trainer read forced", "npc", npc.npcID)
	LearnedStep(npc, true, (ns.db.learnedReads[npc.npcID] or {}).line)
end
--@end-debug@

local visitHandlers = {}
for _, event in ipairs({ "TRAINER_SHOW", "TRAINER_SERVICE_INFO_NAME_UPDATE", "TRAINER_UPDATE", "TRAINER_CLOSED", "MERCHANT_SHOW",
	"MERCHANT_UPDATE", "MERCHANT_CLOSED", "GET_ITEM_INFO_RECEIVED" }) do
	visitHandlers[event] = function(...)
		if ns.db then OnVisitEvent(event, ...) end
	end
end
-- The item event is asked for only while a scan waits on item data.
frame = ns.toolkit:EventFrame(ns.module, visitHandlers, { later = { GET_ITEM_INFO_RECEIVED = true } })

-- Loot windows, read once each; sources come from GetLootSourceInfo and fishing is kept by zone (docs/client-notes.md, "Loot, quests and vendors").
local castTarget, castAt, lootRead
-- An object's name is the target of the cast that opened it. Opening, mining and herb casts run at most
-- about five seconds, so an older cast was at something else and its target is not this object's name.
local OPEN_CAST_SECONDS = 6

-- Where a drop happened, by ID: the dungeon or raid when inside one, else the subzone at the spot
-- (docs/data.md, "Drops").
local function DropPlace(mapID, x, y)
	local inInstance, instanceType = IsInInstance()
	if inInstance and (instanceType == "party" or instanceType == "raid") then
		return nil, select(8, GetInstanceInfo())
	end
	local areas = mapID and x and C_MapExplorationInfo.GetExploredAreaIDsAtPosition(mapID, CreateVector2D(x, y))
	return areas and areas[1], nil
end

local function LootSource(guid)
	if not Readable(guid) then
		return nil
	end
	if IsFishingLoot() then
		local mapID, x, y = GetPlayerLocation()
		return mapID and Source("fishing", mapID), { map = mapID, x = x, y = y }, C_Spell.GetSpellName(ns.FISHING_SPELL_ID)
	end
	local unitType, id = GUID(guid)
	local mapID, x, y = GetPlayerLocation()
	if (unitType == "Creature" or unitType == "Vehicle") and id then
		-- The target's GUID and name can be secret (unit identity restricted); comparing one errors.
		local targetGUID = UnitGUID("target")
		local name = Readable(targetGUID) and targetGUID == guid and UnitName("target") or nil
		if not Readable(name) then name = nil end
		ns.NoteNPC(ns.db.npcs, id, name, mapID, x, y, GetServerTime())
		local area, instance = DropPlace(mapID, x, y)
		return Source("npc", id), { map = mapID, x = x, y = y, area = area, instance = instance }, (ns.GetNPC(id) or {}).name
	elseif unitType == "GameObject" and id then
		local name = castAt and GetTime() - castAt <= OPEN_CAST_SECONDS and castTarget or nil
		ns.NoteNPC(ns.db.objects, id, name, mapID, x, y, GetServerTime())
		local area, instance = DropPlace(mapID, x, y)
		return Source("object", id), { map = mapID, x = x, y = y, area = area, instance = instance },
			name or (ns.db.objects[id] or {}).name
	elseif unitType == "Item" then
		local itemID = C_Item.GetItemIDByGUID(guid)
		return itemID and Source("container", itemID), {}, itemID and C_Item.GetItemNameByID(itemID)
	end
end

-- Recipe items in the player's own loot window, by time, so a roll on the same item adds nothing.
local lootedAt = {}

local function ReadLoot()
	if lootRead or not ns.db or not ns.db.selfFound then
		return
	end
	lootRead = true
	-- One loot window is one sighting per recipe item and source, however many slots hold it.
	local counted, newItems, names, changed = {}, {}, {}, false
	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotType(slot) == Enum.LootSlotType.Item and GetLootSlotLink(slot)
		local itemID = link and ns.IsRecipeItem(link)
		if itemID then
			local sources = { GetLootSourceInfo(slot) }
			for index = 1, #sources, 2 do
				local source, details, name = LootSource(sources[index])
				local key = source and ("%d %s %s"):format(itemID, source.field, tostring(source.value))
				if key and not counted[key] then
					counted[key] = true
					NotePendingItem(itemID)
					lootedAt[itemID] = GetTime()
					local isNew, updated = Save("items", itemID, "drop", source, details)
					changed = changed or updated
					if isNew then
						newItems[itemID] = true
						names[name or UNKNOWN] = true
					end
				end
			end
		end
	end
	-- The line names the source only when every new recipe came from it; otherwise the zone.
	local count, onlyName = 0, nil
	for _ in pairs(newItems) do count = count + 1 end
	for name in pairs(names) do onlyName = onlyName == nil and name or false end
	local mapID = C_Map.GetBestMapForUnit("player")
	local mapInfo = mapID and C_Map.GetMapInfo(mapID)
	Announce(count, onlyName or (mapInfo and mapInfo.name))
	if changed then
		ns.SourcesChanged()
	end
end

-- QUEST_DETAIL has the giver, QUEST_COMPLETE the finisher; both list rewards, and an item-started quest reports an Item GUID as giver.
local function ReadQuest(event)
	if not (ns.db and ns.db.selfFound) then
		return
	end
	local questID = GetQuestID()
	if not questID or questID == 0 then
		return
	end
	-- The quest NPC is saved only when the quest rewards a recipe (NoteQuestNPC).
	local details, questNPC = {}, nil
	local guid = UnitGUID("questnpc")
	local unitType, id = GUID(guid)
	if unitType then
		if unitType == "Creature" and id then
			local mapID, x, y = GetPlayerLocation()
			questNPC = { id, Visible(UnitName("questnpc")), mapID, x, y, GetServerTime(), faction = Visible((UnitFactionGroup("questnpc"))) }
			details[event == "QUEST_COMPLETE" and "finisher" or "npc"] = id
			-- A quest's place is where it is given; the turn-in may be elsewhere.
			if event == "QUEST_DETAIL" then details.map = mapID end
		elseif unitType == "Item" and event == "QUEST_DETAIL" then
			details.giverItem = C_Item.GetItemIDByGUID(guid)
		end
	end
	local count, changed = 0, false
	for _, kind in ipairs({ "reward", "choice" }) do
		local total = kind == "reward" and GetNumQuestRewards() or GetNumQuestChoices()
		for index = 1, total do
			local _, _, _, _, _, itemID = GetQuestItemInfo(kind, index)
			if IsRecipeItem(itemID) then
				NotePendingItem(itemID)
				if questNPC then
					ns.NoteNPC(ns.db.npcs, unpack(questNPC))
					ns.NoteNPCFaction(questNPC[1], questNPC.faction)
					questNPC = nil
				end
				local rowDetails = CopyTable(details)
				rowDetails.choice = kind == "choice"
				local isNew, updated = Save("items", itemID, "quest", Source("quest", questID), rowDetails)
				changed = changed or updated
				if isNew then count = count + 1 end
			end
		end
	end
	Announce(count, C_QuestLog.GetTitleForQuestID(questID))
	if changed then
		ns.SourcesChanged()
	end
end

-- A group roll names no source, so the find is kept by zone, read a moment later so the player's own loot window counts first.
local ROLL_SETTLE = 1 -- seconds before a roll is read
local ROLL_AFTER_LOOT = 120 -- a roll this soon after looting the same item is that drop

local function ReadRoll(rollID)
	if not (ns.db and ns.db.selfFound) then
		return
	end
	local link = GetLootRollItemLink(rollID)
	if not Readable(link) then
		return
	end
	local itemID = ns.IsRecipeItem(link)
	local looted = itemID and lootedAt[itemID]
	if not itemID or (looted and GetTime() - looted < ROLL_AFTER_LOOT) then
		return
	end
	local mapID = GetPlayerLocation()
	if not mapID then
		return
	end
	NotePendingItem(itemID)
	local isNew, updated = Save("items", itemID, "drop", Source("zone", mapID), { map = mapID })
	local mapInfo = C_Map.GetMapInfo(mapID)
	Announce(isNew and 1 or 0, mapInfo and mapInfo.name)
	if updated then
		ns.SourcesChanged()
	end
end

local function ReadLootWindow()
	--@debug@
	local perfStart = debugprofilestop()
	--@end-debug@
	ReadLoot()
	--@debug@
	ns.Perf("loot window", perfStart)
	--@end-debug@
end

local function ReadQuestWindow(event)
	--@debug@
	local perfStart = debugprofilestop()
	--@end-debug@
	ReadQuest(event)
	--@debug@
	ns.Perf("quest window", perfStart)
	--@end-debug@
end

ns.toolkit:EventFrame(ns.module, {
	START_LOOT_ROLL = function(rollID)
		C_Timer.After(ROLL_SETTLE, function() ReadRoll(rollID) end)
	end,
	UNIT_SPELLCAST_SENT = function(unit, target)
		if unit == "player" and ns.toolkit.Readable(target) then
			castTarget, castAt = target ~= "" and target or nil, GetTime()
		end
	end,
	LOOT_READY = ReadLootWindow,
	LOOT_OPENED = ReadLootWindow,
	LOOT_CLOSED = function()
		lootRead, castTarget, castAt = nil, nil, nil
	end,
	QUEST_DETAIL = function() ReadQuestWindow("QUEST_DETAIL") end,
	QUEST_COMPLETE = function() ReadQuestWindow("QUEST_COMPLETE") end,
})
