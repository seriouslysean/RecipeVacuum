local _, ns = ...

-- Profession rank books: when the open profession's next rank comes from a book (Expert Fishing - The Bass
-- and You), and a source of that book with a place is recorded, a mark right of the link button names it and
-- pins it on the map (owner, 2026-11-25; docs/client-notes.md, "Rank books"). Trainer ranks are not covered yet.
local MARK_SIZE = 20
local MARK_GAP = 4 -- space after the link button
local LINK_X, LINK_Y = -2, -4 -- the link button's anchor offsets on the rank bar

-- Whether this character has the book's rank: the book's own "Already known" requirement, by enum
-- (C_SpellBook.IsSpellKnown says no for a learned rank: 19889 with Fishing at 225, build 71091).
local function Learned(itemID)
	local tooltip = C_TooltipInfo.GetItemByID(itemID)
	for _, line in ipairs(tooltip and tooltip.lines or {}) do
		if line.requirementType == Enum.TooltipDataUsageRequirementType.NotAlreadyKnown then
			return not line.usable
		end
	end
	return false
end

-- The first book of the profession this character has not learned and has a pin for.
local function NeededBook()
	local info = ProfessionsFrame.CraftingPage.professionInfo
	local profession = info and info.profession
	if not profession then
		return nil
	end
	for _, book in ipairs(ns.GetRankBooks(profession)) do
		if not Learned(book.item) then
			local entries, targets = ns.GetItemSources(book.item), {}
			for _, observation in ipairs(entries) do
				local target = ns.SourceTarget(observation)
				if target then
					targets[#targets + 1] = target
				end
			end
			if #targets > 0 then
				return { book = book, entries = entries, targets = targets }
			end
		end
	end
end

local mark

local function OnEnter(button)
	local needed = button.needed
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, C_Spell.GetSpellName(needed.book.spell) or UNKNOWN)
	ns.AddEntryLines(GameTooltip, needed.entries)
	GameTooltip:Show()
end

local function OnClick(button)
	ns.ShowOnMap(button.needed.targets[1])
end

local function Update()
	local page = ProfessionsFrame.CraftingPage
	if not mark then
		mark = CreateFrame("Button", nil, page)
		mark:SetSize(MARK_SIZE, MARK_SIZE)
		local icon = mark:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		icon:SetAtlas(ns.sourceTypes.trainer.atlas) -- the same book as the trainer mark
		-- Brightens on hover, as Blizzard's buttons do, so it reads as clickable without a hint line.
		mark:SetHighlightAtlas(ns.sourceTypes.trainer.atlas, "ADD")
		mark:SetScript("OnEnter", OnEnter)
		mark:SetScript("OnLeave", GameTooltip_Hide)
		mark:SetScript("OnClick", OnClick)
	end
	-- After the link button, or where it would sit when it is hidden (its anchor in Blizzard_ProfessionsCrafting.xml).
	mark:ClearAllPoints()
	if page.LinkButton:IsShown() then
		mark:SetPoint("LEFT", page.LinkButton, "RIGHT", MARK_GAP, 0)
	else
		mark:SetPoint("LEFT", page.RankBar, "RIGHT", LINK_X, LINK_Y)
	end
	mark.needed = Professions.InLocalCraftingMode() and NeededBook() or nil
	mark:SetShown(mark.needed ~= nil)
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
	hooksecurefunc(ProfessionsFrame.CraftingPage, "Init", Update)
end)
