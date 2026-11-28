local _, ns = ...
local L = ns.L

-- Every line the Vacuum says; read docs/voice.md before adding one.
ns.voice = {
	-- The voiced line: the noise, then the report (the toolkit's docs/standards.md, "Voice"); the library
	-- puts "Boltgrip's Recipe Vacuum" in front and the period after the noise.
	-- Report arguments: count, "recipe" or "recipes", who or where.
	intake = { noise = L["whirs and rattles"], report = L["Intake complete! %d recipes from %s!"],
		reportOne = L["Intake complete! %d recipe from %s!"] },
	-- Said when the last of the bags, auction house, bank, trade or mail closes on recipes first seen while it was open
	-- for a profession the character has. Argument: count.
	seen = { noise = L["whirs and rattles"], report = L["%d recipes seen!"], reportOne = L["%d recipe seen!"] },
	-- Said when a map pin is set; argument: the source's label.
	pinned = { noise = L["whirs and rattles"], report = L["Map pin set! %s located in %s!"] },
	-- Development lines (checkout builds only): plain, not voiced. The watch and log lines are the toolkit's.
	-- Arguments: count, "recipe" or "recipes".
	detected = "%d %s detected!",
	-- Argument: where. The error itself follows on its own line.
	malfunction = "Malfunction in %s!",
}

--@debug@
-- Development commands, stripped from released builds.
ns.voice.scanBusy = "Scan in progress! Stand clear!"
ns.voice.scanStart = "Scanners engaged! Sweeping %s schemata!" -- profession
ns.voice.scanDone = "Analysis complete! %d of %d unlearned %s recipes traced to their recipe items in %.1f s!"
ns.voice.scanNoWindow = "Scan aborted! No profession window detected!"
ns.voice.scanBadCount = "Scan aborted! Item count exceeds tolerances!"
ns.voice.scanFailed = "Scan aborted! Malfunction: %s!" -- the error
ns.voice.perfWindow = "Diagnostics complete! Profession window ready in %s!" -- time or "no sample"
ns.voice.perfScan = "Last scan logged! %s in %.1f s: item walk %.0f ms over %.1f s for %d IDs!"
ns.voice.perfRequests = "Item requests logged! %d sent, %d answered in %.1f s! Report built in %.1f ms!"
ns.voice.perfNoScan = "No scan on record!"
ns.voice.noSample = "no sample"
--@end-debug@
