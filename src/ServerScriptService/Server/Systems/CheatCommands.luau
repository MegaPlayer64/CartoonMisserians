--!strict
-- Remotes de QA. La puerta está en el SERVIDOR, en cada handler: los nombres de
-- los remotes son públicos y cualquier cliente puede dispararlos.
-- Todo pasa por las mismas APIs que el juego real (Economy / Fishing).

local RunService = game:GetService("RunService")

local Net = require(script.Parent.Parent.Net)
local Fishing = require(script.Parent.Fishing)
local Economy = require(script.Parent.Economy)

-- Añade aquí tu UserId para poder usar los comandos en servidores reales.
local DEV_USER_IDS: { [number]: boolean } = {
	-- [12345678] = true,
}

local function isAuthorized(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return DEV_USER_IDS[player.UserId] == true
end

local CheatCommands = {}

function CheatCommands.init()
	-- Cheat_Grant(cantidad)  → suma Cartonsitos (Economy valida el valor)
	Net.on("Cheat_Grant", 2, 4, function(player: Player, amount: unknown)
		if not isAuthorized(player) then
			return
		end
		if typeof(amount) ~= "number" then
			return
		end
		Economy.addCartonsitos(player, amount)
	end)

	-- Cheat_Spawn("Tiburon")  → criatura en el carril del gancho
	Net.on("Cheat_Spawn", 4, 8, function(player: Player, kindId: unknown)
		if not isAuthorized(player) then
			return
		end
		if typeof(kindId) ~= "string" then
			return
		end
		Fishing.spawnForQA(player, kindId)
	end)

	-- Cheat_EndRound()  → termina la ronda (reparte recompensas)
	Net.on("Cheat_EndRound", 2, 4, function(player: Player)
		if not isAuthorized(player) then
			return
		end
		Fishing.endRound(player, "Quit")
	end)

	-- Cheat_Reset()  → saldo a 0
	Net.on("Cheat_Reset", 1, 2, function(player: Player)
		if not isAuthorized(player) then
			return
		end
		Economy.reset(player)
	end)
end

return CheatCommands
