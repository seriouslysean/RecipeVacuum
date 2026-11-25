local _, ns = ...

-- Every line the Vacuum says; read docs/voice.md before adding one.
ns.voice = {
	-- Voiced lines: the library puts "Boltgrip's Recipe Vacuum" in front, so each is the rest of a sentence.
	-- Arguments: count, "recipe" or "recipes", who or where.
	intake = "sucks up %d %s from %s!",
	watchOn = "switches on its recipe sensors!",
	watchOff = "switches off its recipe sensors!",
	-- Arguments: count, "recipe" or "recipes".
	detected = "detects %d %s!",
	-- Argument: where. The error itself follows on a plain line.
	malfunction = "malfunctions in %s!",
	logPurged = "purges its log!",
	-- Window titles.
	logTitle = "Log ready! Select all, then copy!",
	exportTitle = "Export ready! Copy it and send it to the maintainer as a .json file!",
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
ns.voice.perfList = "Recipe list assembled in %s! Slowest run %s, %d runs since reload!"
ns.voice.perfCold = "Cold start logged! %d unlearned: recipes %.1f ms, sources %.1f ms, grouping %.1f ms!"
ns.voice.perfScan = "Last scan logged! %s in %.1f s: item walk %.0f ms over %.1f s for %d IDs!"
ns.voice.perfRequests = "Item requests logged! %d sent, %d answered in %.1f s! Report built in %.1f ms!"
ns.voice.perfNoScan = "No scan on record!"
ns.voice.noSample = "no sample"
--@end-debug@
