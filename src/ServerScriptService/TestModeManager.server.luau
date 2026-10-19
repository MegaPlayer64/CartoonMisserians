--[[
	TestModeManager (Script)
	Ubicacion: ServerScriptService.TestModeManager

	Comandos de chat de DEPURACIÓN. Todos pasan por DevAuth: solo funcionan
	en Studio o para los UserIds de DevAuth.DEV_USER_IDS. En un servidor real,
	cualquier otro jugador que escriba un comando es ignorado.

	  /bot toon      -> Invoca un Bot Toonflow frente a ti.
	  /bot killer    -> Invoca un Bot Devilish frente a ti.
	  /bot clear     -> Elimina todos los bots del mapa.
	  /heal          -> Restaura tu salud.
	  /role toon     -> Fuerza tu rol a Toonflow (solo Studio, lo aplica MatchManager).
	  /role killer   -> Fuerza tu rol a Devilish (solo Studio, lo aplica MatchManager).
	  /scells [n]    -> Fija tus S-CELLS (0-100, por defecto 20).
	  /ssj           -> Alterna Super Saiyan sin consumir S-CELLS.
	  /trunks        -> Fuerza tu personaje a Trunks.
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local DevAuth = require(ServerScriptService:WaitForChild("ServerModules"):WaitForChild("DevAuth"))

local MAX_SCELLS = 100

local BotController = require(ServerScriptService:WaitForChild("BotController"))
local StatsModule = require(ServerScriptService:WaitForChild("ServerModules"):WaitForChild("StatsModule"))

local function handleCommand(player: Player, message: string)
	-- AUTORIZACIÓN: primera línea, antes de tocar nada.
	if not DevAuth.isAuthorized(player) then return end
	if typeof(message) ~= "string" or string.sub(message, 1, 1) ~= "/" then return end

	local char = player.Character
	if not char then return end

	local args = string.split(string.lower(message), " ")
	local command = args[1]
	local msg = string.lower(message)

	if command == "/bot" then
		local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
		if not hrp then return end
		local spawnCFrame = hrp.CFrame * CFrame.new(0, 0, -8)

		if args[2] == "toon" then
			BotController.SpawnBot(StatsModule.Role.Toonflow, spawnCFrame, "Brothercat")
		elseif args[2] == "killer" then
			BotController.SpawnBot(StatsModule.Role.Devilish, spawnCFrame, "DummyDevilish")
		elseif args[2] == "clear" then
			BotController.ClearAllBots()
		end

	elseif command == "/heal" then
		StatsModule.RestoreHealth(char)
		print("[Debug] Salud de " .. player.Name .. " restaurada al 100%.")

	elseif msg == "/role toon" then
		player:SetAttribute("ForceRole", "Toonflow")
		print("[TestModeManager] Rol forzado a TOONFLOW para " .. player.Name)

	elseif msg == "/role killer" then
		player:SetAttribute("ForceRole", "Devilish")
		print("[TestModeManager] Rol forzado a DEVILISH para " .. player.Name)

	elseif command == "/scells" then
		local amount = tonumber(args[2]) or 20
		if amount ~= amount then return end -- NaN
		amount = math.clamp(math.floor(amount), 0, MAX_SCELLS)

		local statsFolder = char:FindFirstChild("Stats")
		if not statsFolder then
			statsFolder = Instance.new("Folder")
			statsFolder.Name = "Stats"
			statsFolder.Parent = char
		end

		local sCellsVal = statsFolder:FindFirstChild("SCells")
		if not sCellsVal then
			sCellsVal = Instance.new("NumberValue")
			sCellsVal.Name = "SCells"
			sCellsVal.Parent = statsFolder
		end

		sCellsVal.Value = amount
		char:SetAttribute("SCells", amount)
		print("[TestMode] " .. player.Name .. " recibió " .. amount .. " S-CELLS.")

	elseif command == "/ssj" then
		local currentSSJ = char:GetAttribute("IsSuperSaiyan") or false
		char:SetAttribute("IsSuperSaiyan", not currentSSJ)
		print("[TestMode] Super Saiyan forzado a: " .. tostring(not currentSSJ))

	elseif command == "/trunks" then
		player:SetAttribute("SelectedCharacter", "Trunks")
		char:SetAttribute("CharacterName", "Trunks")
		print("[TestMode] Personaje forzado a Trunks para " .. player.Name)
	end
end

-- Una sola conexión por jugador, incluidos los que ya estaban al arrancar el script.
local function hookPlayer(player: Player)
	player.Chatted:Connect(function(message)
		handleCommand(player, message)
	end)
end

Players.PlayerAdded:Connect(hookPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	hookPlayer(p)
end

print("[TestModeManager] Listo. Comandos solo para Studio / DevAuth.DEV_USER_IDS.")
