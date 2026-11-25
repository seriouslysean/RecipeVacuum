local _, ns = ...

-- Profession ranks: a mark right of the profession window's link button, shown when the rank books of the
-- open profession are known. Its tooltip lists each rank, whether this character has it, and where its book
-- comes from (docs/data.md, "Rank books"). Not yet shown to players: the owner validates it first.
local MARK_SIZE = 20
local MARK_GAP = 4 -- space after the link button

local function Profession()
	local info = ProfessionsFrame and ProfessionsFrame.CraftingPage.professionInfo
	return info and info.profession, info and info.professionName
end

local function ShowRanks(mark)
	local profession, name = Profession()
	GameTooltip:SetOwner(mark, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, ("%s: %s"):format(name or UNKNOWN, RANK))
	for _, book in ipairs(ns.GetRankBooks(profession)) do
		local known = C_SpellBook.IsSpellKnown(book.spell)
		local rank = C_Spell.GetSpellName(book.spell) or UNKNOWN
		GameTooltip_AddColoredLine(GameTooltip, rank, known and DISABLED_FONT_COLOR or HIGHLIGHT_FONT_COLOR)
		if not known then
			local entries = ns.GetItemSources(book.item)
			if #entries > 0 then
				ns.AddEntryLines(GameTooltip, entries)
			else
				GameTooltip_AddColoredLine(GameTooltip, ns.SOURCE_LABEL .. " " .. UNKNOWN, GRAY_FONT_COLOR)
			end
		end
	end
	GameTooltip:Show()
end

local mark

local function Update()
	local page = ProfessionsFrame.CraftingPage
	if not mark then
		mark = CreateFrame("Button", nil, page)
		mark:SetSize(MARK_SIZE, MARK_SIZE)
		mark:SetPoint("LEFT", page.LinkButton, "RIGHT", MARK_GAP, 0)
		local icon = mark:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		icon:SetAtlas(ns.sourceTypes.trainer.atlas) -- the same book as the trainer mark
		mark:SetScript("OnEnter", ShowRanks)
		mark:SetScript("OnLeave", GameTooltip_Hide)
	end
	local profession = Profession()
	mark:SetShown(Professions.InLocalCraftingMode() and profession ~= nil and #ns.GetRankBooks(profession) > 0)
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
	hooksecurefunc(ProfessionsFrame.CraftingPage, "Init", Update)
end)
