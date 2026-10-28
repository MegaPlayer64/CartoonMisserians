--[[
	MatchStats (ModuleScript)
	Ubicación: ServerScriptService.ServerModules.MatchStats

	Contadores de rendimiento de la partida en curso. Alimentan MatchScoring (calificación y Maldad).
	MatchManager los reinicia al empezar cada partida. Los sistemas del juego solo llaman a add/addUnique:

	  Toonflow: tasksCompleted, stuns (al Devilish), healed (supervivientes DISTINTOS curados),
	            abilitiesUsed, chaseEscapes y chaseSaves (pendientes de un detector de persecuciones)
	  Devilish: downs y kills se acreditan al Killer como eventos de equipo (addDevilishEvent), porque en
	            una partida solo hay un Devilish; abilitiesUsed por jugador.
]]

local MatchStats = {}

local counters = setmetatable({}, { __mode = "k" }) -- [Player] = { [clave] = número }
local uniques = setmetatable({}, { __mode = "k" }) -- [Player] = { [clave] = { [id] = true } }
local devilishEvents = { downs = 0, kills = 0 }

local function isPlayer(value)
	return typeof(value) == "Instance" and value:IsA("Player")
end

function MatchStats.reset()
	counters = setmetatable({}, { __mode = "k" })
	uniques = setmetatable({}, { __mode = "k" })
	devilishEvents = { downs = 0, kills = 0 }
end

-- Suma `amount` (por defecto 1) al contador `key` del jugador. Ignora lo que no sea un Player (bots, nil).
function MatchStats.add(player, key, amount)
	if not isPlayer(player) then return end
	amount = amount or 1
	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then return end

	local playerCounters = counters[player]
	if not playerCounters then
		playerCounters = {}
		counters[player] = playerCounters
	end
	playerCounters[key] = (playerCounters[key] or 0) + amount
end

-- Cuenta valores DISTINTOS (p. ej. a cuántos supervivientes distintos ha curado, no cuántas curaciones)
function MatchStats.addUnique(player, key, uniqueId)
	if not isPlayer(player) or uniqueId == nil then return end

	local playerUniques = uniques[player]
	if not playerUniques then
		playerUniques = {}
		uniques[player] = playerUniques
	end
	local set = playerUniques[key]
	if not set then
		set = {}
		playerUniques[key] = set
	end
	set[uniqueId] = true
end

function MatchStats.addDevilishEvent(key)
	if devilishEvents[key] ~= nil then
		devilishEvents[key] += 1
	end
end

function MatchStats.getDevilishEvents()
	return { downs = devilishEvents.downs, kills = devilishEvents.kills }
end

-- Copia de los contadores del jugador (los "unique" aparecen como su cantidad de elementos)
function MatchStats.get(player)
	local result = {}
	for key, value in pairs(counters[player] or {}) do
		result[key] = value
	end
	for key, set in pairs((uniques[player]) or {}) do
		local count = 0
		for _ in pairs(set) do
			count += 1
		end
		result[key] = count
	end
	return result
end

return MatchStats
