--[[
	TestModeManager (Script)
	Ubicacion: ServerScriptService.TestModeManager

	Escucha comandos en el chat para controlar el Modo de Pruebas:
	  /bot toon     -> Invoca un Bot Toonflow 5 studs frente a ti.
	  /bot killer   -> Invoca un Bot Devilish 5 studs frente a ti.
	  /bot clear    -> Elimina todos los bots del mapa.
	  /resetcd      -> Reinicia el cooldown de tus habilidades (requiere servidor/local).
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotController = require(ServerScriptService:WaitForChild("BotController"))
local StatsModule = require(ReplicatedStorage.Framework.StatsModule)

local function onPlayerChatted(player, message)
	local msg = string.lower(message)
	local char = player.Character
	if not char then return end

	local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
	if not hrp then return end

	-- Spawn Pos: 8 studs enfrente del jugador
	local spawnCFrame = hrp.CFrame * CFrame.new(0, 0, -8)

	if msg == "/bot toon" then
		BotController.SpawnBot(StatsModule.Role.Toonflow, spawnCFrame, "Brothercat")
	elseif msg == "/bot killer" then
		BotController.SpawnBot(StatsModule.Role.Devilish, spawnCFrame, "DummyDevilish")
	elseif msg == "/bot clear" then
		BotController.ClearAllBots()
	elseif msg == "/heal" then
		StatsModule.RestoreHealth(char)
		print("[Debug] Salud de " .. player.Name .. " restaurada al 100%.")
	end
	-- Añadir dentro de la función onPlayerChatted en TestModeManager:
	if msg == "/role toon" then
		player:SetAttribute("ForceRole", "Toonflow")
		print("[TestModeManager] Rol forzado a TOONFLOW para " .. player.Name)
	elseif msg == "/role killer" then
		player:SetAttribute("ForceRole", "Devilish")
		print("[TestModeManager] Rol forzado a DEVILISH para " .. player.Name)
	end
end

-- == ATAJOS DE DEPURAClÓN PARA TRUNKS ==
local Players = game:GetService("Players")

local function setupDebugChatCommands(player)
	player.Chatted:Connect(function(message)
		local args = string.split(message, " ")
		local command = string.lower(args[1] or "")

		local character = player.Character
		if not character then return end

		-- Comandos de prueba
		if command == "/scells" then
			local amount = tonumber(args[2]) or 20

			-- Asegurar estructura de Stats
			local statsFolder = character:FindFirstChild("Stats")
			if not statsFolder then
				statsFolder = Instance.new("Folder")
				statsFolder.Name = "Stats"
				statsFolder.Parent = character
			end

			local sCellsVal = statsFolder:FindFirstChild("SCells")
			if not sCellsVal then
				sCellsVal = Instance.new("NumberValue")
				sCellsVal.Name = "SCells"
				sCellsVal.Parent = statsFolder
			end

			sCellsVal.Value = amount
			character:SetAttribute("SCells", amount)
			print("[TestMode] " .. player.Name .. " recibió " .. amount .. " S-CELLS.")

		elseif command == "/ssj" then
			-- Toggle directo de Super Saiyan omitiendo consumos
			local currentSSJ = character:GetAttribute("IsSuperSaiyan") or false
			character:SetAttribute("IsSuperSaiyan", not currentSSJ)
			print("[TestMode] Super Saiyan forzado a: " .. tostring(not currentSSJ))

		elseif command == "/trunks" then
			player:SetAttribute("SelectedCharacter", "Trunks")
			character:SetAttribute("CharacterName", "Trunks")
			print("[TestMode] Personaje forzado a Trunks para " .. player.Name)
		end
	end)
end

Players.PlayerAdded:Connect(setupDebugChatCommands)
for _, p in ipairs(Players:GetPlayers()) do
	setupDebugChatCommands(p)
end

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)
		onPlayerChatted(player, message)
	end)
end)

print("[TestModeManager] Sistema de pruebas listo. Usa '/bot toon', '/bot killer' o '/bot clear' en el chat.")