local _, ns = ...

-- Profession rank books: when the open profession's next rank comes from a book (Expert Fishing - The Bass
-- and You), and a source of that book with a place is recorded, a mark right of the link button names it and
-- pins it on the map (owner, 2026-11-25; docs/client-notes.md, "Rank books"). Trainer ranks are not covered yet.
local MARK_SIZE = 20
local MARK_GAP = 4 -- space after the link button

-- The first book of the profession this character has not learned, with its pins.
local function NeededBook()
	local info = ProfessionsFrame.CraftingPage.professionInfo
	local profession = info and info.profession
	if not profession then
		return nil
	end
	for _, book in ipairs(ns.GetRankBooks(profession)) do
		if not C_SpellBook.IsSpellKnown(book.spell) then
			local entries, targets = ns.GetItemSources(book.item), {}
			for _, observation in ipairs(entries) do
				local target = ns.SourceTarget(observation)
				if target then
					targets[#targets + 1] = target
				end
			end
			return #targets > 0 and { book = book, entries = entries, targets = targets } or nil
		end
	end
end

local mark

local function OnEnter(button)
	local needed = button.needed
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, C_Spell.GetSpellName(needed.book.spell) or UNKNOWN)
	ns.AddEntryLines(GameTooltip, needed.entries)
	GameTooltip_AddInstructionLine(GameTooltip, SHOW_MAP)
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
		mark:SetPoint("LEFT", page.LinkButton, "RIGHT", MARK_GAP, 0)
		local icon = mark:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		icon:SetAtlas(ns.sourceTypes.trainer.atlas) -- the same book as the trainer mark
		mark:SetScript("OnEnter", OnEnter)
		mark:SetScript("OnLeave", GameTooltip_Hide)
		mark:SetScript("OnClick", OnClick)
	end
	mark.needed = Professions.InLocalCraftingMode() and NeededBook() or nil
	mark:SetShown(mark.needed ~= nil)
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
	hooksecurefunc(ProfessionsFrame.CraftingPage, "Init", Update)
end)
