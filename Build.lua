-- The working build's deploy stamp. deploy-deck writes it here because the client reads the TOC's Version only at startup,
-- not on a reload; a checkout or release leaves it nil and the TOC's Version stands.
local _, ns = ...
ns.build = nil
