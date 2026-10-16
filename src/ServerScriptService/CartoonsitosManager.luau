--[[
	CartoonsitosManager (ModuleScript)
	Ubicacion: ServerScriptService.CartoonsitosManager

	Sistema de economia del juego. Gestiona la moneda "Cartoonsitos" (Coins)
	mediante atributos en Player. Proporciona funciones de recompensa
	que se integran con TaskManager y MatchManager.

	Tabla de recompensas:
	  - Tarea reparada       +15
	  - Sobrevivir ronda      +50
	  - Escapar              +100
	  - Derribo Devilish      +25
	  - Victoria Devilish    +150
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Remotes = ReplicatedStorage.Framework.Remotes
local CoinUpdateRemote = Remotes:WaitForChild("CoinUpdate")

local CartoonsitosManager = {}

-- == TABLA DE RECOMPENSAS ==
local REWARDS = {
	TaskRepaired = 15,
	SurviveRound = 50,
	Escape = 100,
	DownDevilish = 25,
	DevilishWin = 150,
}

-- == FUNCIONES DE PERSISTENCIA (atributos en Player) ==

local function getCoins(player)
	return player:GetAttribute("Coins") or 0
end

local function setCoins(player, amount)
	player:SetAttribute("Coins", amount)
	CoinUpdateRemote:FireClient(player, amount)
end

-- == API PUBLICA ==

--[[
	Anade coins a un jugador y notifica al cliente.
	Parametros:
	  player  -> Player
	  amount  -> numero (positivo o negativo)
	  reason  -> string descriptivo (opcional, para logs)
]]
function CartoonsitosManager.AddCoins(player, amount, reason)
	if not (player and player:IsA("Player")) then return end
	if typeof(amount) ~= "number" then return end

	local current = getCoins(player)
	local newTotal = math.max(0, current + amount)
	setCoins(player, newTotal)

	if reason then
		print(string.format("[Cartoonsitos] %s %s%d coins (Total: %d) - %s",
			player.Name, amount >= 0 and "+" or "", amount, newTotal, reason))
	end
end

--[[
	Obtiene el balance actual de un jugador.
]]
function CartoonsitosManager.GetCoins(player)
	return getCoins(player)
end

-- == FUNCIONES DE RECOMPENSA ESPECIFICAS ==

--[[
	Recompensa al jugador por completar una tarea (+15).
]]
function CartoonsitosManager.RewardTaskRepaired(player)
	CartoonsitosManager.AddCoins(player, REWARDS.TaskRepaired, "Tarea reparada")
end

--[[
	Recompensa a todos los Toonflows que sobrevivieron la ronda (+50).
	Parametros:
	  assignedRoles   -> tabla [Player] = role
	  escapedToonflows -> tabla [Player] = true
]]
function CartoonsitosManager.RewardSurviveRound(assignedRoles, escapedToonflows)
	for player, role in pairs(assignedRoles) do
		if typeof(player) == "Instance" and player:IsA("Player") and role == "Toonflow" then
			local char = player.Character
			if char then
				local humanoid = char:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					CartoonsitosManager.AddCoins(player, REWARDS.SurviveRound, "Sobrevivir ronda")
				end
			end
		end
	end
end

--[[
	Recompensa a los Toonflows que escaparon por la salida (+100).
]]
function CartoonsitosManager.RewardEscape(escapedToonflows)
	for player, _ in pairs(escapedToonflows) do
		if typeof(player) == "Instance" and player:IsA("Player") then
			CartoonsitosManager.AddCoins(player, REWARDS.Escape, "Escapar")
		end
	end
end

--[[
	Recompensa a los Toonflows por derrotar al Devilish (+25 cada uno).
]]
function CartoonsitosManager.RewardDownDevilish(assignedRoles)
	for player, role in pairs(assignedRoles) do
		if typeof(player) == "Instance" and player:IsA("Player") and role == "Toonflow" then
			local char = player.Character
			if char then
				local humanoid = char:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					CartoonsitosManager.AddCoins(player, REWARDS.DownDevilish, "Derribo Devilish")
				end
			end
		end
	end
end

--[[
	Recompensa al Devilish por ganar la partida (+150).
]]
function CartoonsitosManager.RewardDevilishWin(assignedRoles)
	for player, role in pairs(assignedRoles) do
		if typeof(player) == "Instance" and player:IsA("Player") and role == "Devilish" then
			CartoonsitosManager.AddCoins(player, REWARDS.DevilishWin, "Victoria Devilish")
		end
	end
end

--[[
	Procesa todas las recompensas al final de una partida.
	Parametros:
	  result          -> "ToonflowsWin" | "DevilishWins"
	  assignedRoles   -> tabla [Player] = role
	  escapedToonflows -> tabla [Player] = true
]]
function CartoonsitosManager.ProcessMatchEnd(result, assignedRoles, escapedToonflows)
	if result == "ToonflowsWin" then
		CartoonsitosManager.RewardEscape(escapedToonflows or {})
		CartoonsitosManager.RewardSurviveRound(assignedRoles or {})
		CartoonsitosManager.RewardDownDevilish(assignedRoles or {})
	elseif result == "DevilishWins" then
		CartoonsitosManager.RewardDevilishWin(assignedRoles or {})
		CartoonsitosManager.RewardSurviveRound(assignedRoles or {})
	end
	print("[Cartoonsitos] Recompensas de partida procesadas: " .. tostring(result))
end

-- == INICIALIZACION DE JUGADORES ==

local function initPlayer(player)
	if not player:GetAttribute("Coins") then
		player:SetAttribute("Coins", 0)
	end
end

Players.PlayerAdded:Connect(initPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	initPlayer(p)
end

print("[CartoonsitosManager] Sistema de economia inicializado.")

return CartoonsitosManager