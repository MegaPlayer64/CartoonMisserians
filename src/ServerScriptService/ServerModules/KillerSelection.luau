--[[
	KillerSelection (ModuleScript)
	Ubicación: ServerScriptService.ServerModules.KillerSelection

	Quién es el Devilish (Killer) de la próxima partida:
	  1. Solo cuentan los jugadores que NO desactivaron "poder ser Killer" en Opciones (KillerOptIn).
	  2. Gana el que tenga MÁS Maldad; los empates se sortean entre los empatados.
	  3. Si nadie quiere ser Killer, para que la partida pueda empezar se elige entre todos con la
	     misma regla (Maldad y sorteo). Es la única excepción a la opción.

	Al tocarle ser Killer su Maldad se gasta (vuelve a 0): lo hace MatchManager al EMPEZAR la partida,
	no al asignar el rol, para no cobrarlo si la partida se cancela antes.
]]

local PlayerData = require(script.Parent.PlayerData)

local KillerSelection = {}

local function highestMaldad(players)
	local best = {}
	local bestMaldad = -1
	for _, player in ipairs(players) do
		local maldad = PlayerData.getMaldad(player)
		if maldad > bestMaldad then
			bestMaldad = maldad
			best = { player }
		elseif maldad == bestMaldad then
			table.insert(best, player)
		end
	end
	return best
end

-- players: lista de Players elegibles (MatchManager ya excluye a los AFK). Devuelve el elegido o nil.
function KillerSelection.pick(players)
	if #players == 0 then return nil end

	local candidates = {}
	for _, player in ipairs(players) do
		if PlayerData.isKillerOptIn(player) then
			table.insert(candidates, player)
		end
	end

	if #candidates == 0 then
		warn("[KillerSelection] Nadie quiere ser Killer: se elige entre todos para poder empezar la partida")
		candidates = players
	end

	local best = highestMaldad(candidates)
	return best[math.random(1, #best)]
end

return KillerSelection
