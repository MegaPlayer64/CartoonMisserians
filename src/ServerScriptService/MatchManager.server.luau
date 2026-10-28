--[[
	MatchManager (Script)
	Ubicación: ServerScriptService.MatchManager

	Gestor principal del Match Loop del juego.
	Corregido:
	  - Soporte de testing de 1 jugador en Studio (Spawnea bot oponente automático).
	  - Notificación de progreso de tareas en tiempo real hacia la GUI (`TaskProgressRemote`).
	  - Salida exclusiva por tareas completadas.
	  - Teleport seguro al Lobby con dispersión.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local MatchConfig = require(ReplicatedStorage.Framework.MatchConfig)
local StatsModule = require(game:GetService("ServerScriptService").ServerModules.StatsModule)
local CharacterDatabase = require(ReplicatedStorage.Framework.CharacterDatabase)
local AbilityFramework = require(game:GetService("ServerScriptService").ServerModules.AbilityFramework)
local AbilityTemplates = require(game:GetService("ServerScriptService").ServerModules.AbilityTemplates)
local MapSelection = require(game:GetService("ServerScriptService").ServerModules.MapSelection)
local TaskManager = require(game:GetService("ServerScriptService").ServerModules.TaskManager)
local BotController = require(ServerScriptService.BotController)
local CartoonsitosManager = require(ServerScriptService:WaitForChild("CartoonsitosManager"))

local Remotes = ReplicatedStorage.Framework.Remotes
local MatchStateRemote = Remotes:WaitForChild("MatchState")
local MapChosenRemote = Remotes:WaitForChild("MapChosen")
local LMSActivatedRemote = Remotes:WaitForChild("LMSActivated")
local ExitTimerRemote = Remotes:WaitForChild("ExitTimer")
local TaskProgressRemote = Remotes:WaitForChild("TaskProgress", 10) or Remotes:FindFirstChild("TaskProgress")

local MatchManager = {}

-- == ESTADO INTERNO ==
local currentMatchState = MatchConfig.MatchState.Intermission
local currentMap = nil
local assignedRoles = {}  -- [Player/Bot] = "Toonflow" | "Devilish"
local aliveToons = 0
local matchThread = nil
local lmsActivated = false
local exitOpen = false
local exitClosed = false
local exitThread = nil
local escapedToonflows = {}  -- [Player] = true
local tasksCompleted = 0
local lmsPlayer = nil  -- [Player] ultimo sobreviviente Toonflow
local exitTriggerConnections = {}
local activeExits = {} -- Models de salida activos en ESTA partida (según el tamaño del mapa)

-- Salidas del mapa: una carpeta "Exits" con un Model por salida; si no existe, la salida única
-- heredada ("Exit" o "ExitDoor").
local function getExitModels()
	local models = {}
	if not currentMap then return models end

	local folder = currentMap:FindFirstChild("Exits")
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Model") or child:IsA("BasePart") then
				table.insert(models, child)
			end
		end
	else
		local single = currentMap:FindFirstChild("Exit") or currentMap:FindFirstChild("ExitDoor")
		if single then
			table.insert(models, single)
		end
	end
	return models
end

local function getMapCategory()
	if not currentMap then return nil end
	for _, map in ipairs(MatchConfig.AvailableMaps) do
		if map.Name == currentMap.Name then
			return map.Category
		end
	end
	return nil
end

-- QNA: Chico 1 salida, Mediano 2, Grande 3. Si el mapa tiene más Models de salida de los que
-- le tocan, se eligen al azar; si tiene menos, se usan todos.
local function selectActiveExits()
	local models = getExitModels()
	local allowed = MatchConfig.ExitsByCategory[getMapCategory()] or 1

	for i = #models, 2, -1 do
		local j = math.random(i)
		models[i], models[j] = models[j], models[i]
	end

	local active = {}
	for i = 1, math.min(allowed, #models) do
		active[i] = models[i]
	end
	return active
end

-- Abre (sin colisión, semitransparente) o cierra visualmente la puerta de salida.
local function setExitVisuals(exitModel, open)
	if not exitModel then return end
	for _, part in ipairs(exitModel:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "Trigger" then
			part.CanCollide = not open
			part.Transparency = open and 0.5 or 0
		end
	end
end

local function setAllExitVisuals(open)
	for _, exitModel in ipairs(activeExits) do
		setExitVisuals(exitModel, open)
	end
end

local function broadcastMatchState(state, extraData)
	MatchStateRemote:FireAllClients(state, extraData or {})
end

local function getAllPlayers()
	return Players:GetPlayers()
end

local function getEligiblePlayers()
	local eligible = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if not (p:GetAttribute("IsAFK") or false) then
			table.insert(eligible, p)
		end
	end
	return eligible
end

local function teleportPlayer(player, spawnPart)
	if not (player and player.Character and spawnPart) then return end
	local character = player.Character
	if character then
		local randomOffset = Vector3.new(math.random(-3, 3), 3.5, math.random(-3, 3))
		character:PivotTo(spawnPart.CFrame + randomOffset)
	end
end

local function getRandomSpawn(spawnFolder)
	local spawns = spawnFolder:GetChildren()
	if #spawns == 0 then return nil end
	return spawns[math.random(1, #spawns)]
end

local function applyCustomCharacterModel(player, characterName)
	if characterName == "Trunks GT" then
		characterName = "Trunks"
	end

	local charsFolder = ReplicatedStorage:FindFirstChild("Characters") or workspace:FindFirstChild("Characters")
	local modelToClone = charsFolder and charsFolder:FindFirstChild(characterName)

	if modelToClone and player.Character then
		local oldChar = player.Character
		local oldHRP = oldChar:FindFirstChild("HumanoidRootPart") or oldChar.PrimaryPart
		local spawnCFrame = oldHRP and oldHRP.CFrame or CFrame.new(0, 10, 0)

		local newChar = modelToClone:Clone()
		newChar.Name = player.Name

		for _, part in ipairs(newChar:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = false
			end
		end

		local hrp = newChar:FindFirstChild("HumanoidRootPart") or newChar:FindFirstChildOfClass("BasePart")
		if hrp then
			newChar.PrimaryPart = hrp
		end

		if newChar.PrimaryPart then
			newChar:SetPrimaryPartCFrame(spawnCFrame)
		end

		player.Character = newChar
		newChar.Parent = workspace
		oldChar:Destroy()

		local hum = newChar:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = hum.MaxHealth
			-- workspace.CurrentCamera es nil en el servidor (indexarlo daba error justo
			-- después de destruir el personaje viejo); el cliente sigue su Character solo.
			local camera = workspace.CurrentCamera
			if camera then
				camera.CameraSubject = hum
			end
		end

		print("[MatchManager] Modelo personalizado asignado a " .. player.Name .. ": " .. characterName)
		return newChar
	end

	return player.Character
end

local function assignRoles()
	local allPlayers = getEligiblePlayers()
	local playerCount = #allPlayers

	assignedRoles = {}

	local minReq = RunService:IsStudio() and 1 or MatchConfig.MinPlayers
	if playerCount < minReq then
		return false
	end

	local forcedToon = nil
	for _, p in ipairs(allPlayers) do
		if p:GetAttribute("ForceRole") == "Toonflow" then
			forcedToon = p
			break
		end
	end

	if forcedToon and RunService:IsStudio() then
		for _, player in ipairs(allPlayers) do
			if player == forcedToon then
				assignedRoles[player] = StatsModule.Role.Toonflow
			else
				assignedRoles[player] = StatsModule.Role.Devilish
			end
		end
	else
		local devilishIndex = math.random(1, playerCount)
		for i, player in ipairs(allPlayers) do
			if i == devilishIndex then
				assignedRoles[player] = StatsModule.Role.Devilish
			else
				assignedRoles[player] = StatsModule.Role.Toonflow
			end
		end
	end

	-- CORRECCIÓN PARA 1 JUGADOR EN STUDIO: Generar Bot oponente automático
	if RunService:IsStudio() and playerCount == 1 then
		local singlePlayer = allPlayers[1]
		local pRole = assignedRoles[singlePlayer]

		task.defer(function()
			local spawnCFrame = CFrame.new(0, 5, 0)
			if pRole == StatsModule.Role.Toonflow then
				BotController.SpawnBot(StatsModule.Role.Devilish, spawnCFrame, "DummyDevilish")
			else
				BotController.SpawnBot(StatsModule.Role.Toonflow, spawnCFrame, "DummyToonflow")
			end
		end)
	end

	return true
end

local function setupPlayerRole(player, role)
	local characterName = nil
	local config = nil

	if role == StatsModule.Role.Devilish then
		local selectedDevilish = player:GetAttribute("SelectedDevilish")
		if selectedDevilish and CharacterDatabase.IsValidDevilish(selectedDevilish) then
			config = CharacterDatabase.GetDevilishStats(selectedDevilish)
			characterName = selectedDevilish
		else
			config = CharacterDatabase.GetDevilishStats(CharacterDatabase.DefaultDevilish)
			characterName = CharacterDatabase.DefaultDevilish
		end
	else
		local selectedToonflow = player:GetAttribute("SelectedToonflow")
		if selectedToonflow and CharacterDatabase.IsValidToonflow(selectedToonflow) then
			config = CharacterDatabase.GetToonflowStats(selectedToonflow)
			characterName = selectedToonflow
		else
			config = CharacterDatabase.GetToonflowStats(CharacterDatabase.DefaultToonflow)
			characterName = CharacterDatabase.DefaultToonflow
		end
	end

	local character = applyCustomCharacterModel(player, characterName)
	if not character then return end

	character:SetAttribute("CharacterName", characterName)
	character:SetAttribute("Role", role)
	character:SetAttribute("Escaped", nil) -- por si el personaje se reutiliza entre partidas
	StatsModule.InitializeStats(character, role, config)
	AbilityFramework.InitPlayer(player)

	-- Estado propio de cada personaje: el Character puede reutilizarse entre partidas, y las cargas de
	-- galletas de Deerphina, el modo láser de Stan o las marionetas de Mariposaurio no deben heredarse.
	character:SetAttribute("CookieCharges", nil)
	character:SetAttribute("LaserModeActive", nil)
	character:SetAttribute("ActivePuppets", nil)
	-- Shed.mov: efectos y estados que no deben heredarse entre partidas
	for _, attribute in ipairs({ "StunImmune", "SlowImmune", "AttackSpeedMultiplier", "BerserkActive",
		"TerrorRadiusMultiplier", "ShedChasing", "Bleeding", "Revealed" }) do
		character:SetAttribute(attribute, nil)
	end

	-- Pasiva de Stan ("Corrupción Inminente"): antes StartPassiveTrail no se llamaba desde ningún sitio
	-- Pasiva de Shed.mov ("Mantente fuera"): radio de terror reducido fuera de persecución y bono en ella
	if characterName == "Shedmov" and role == StatsModule.Role.Devilish then
		require(game:GetService("ServerScriptService").ServerModules.ShedMovAbilities).StartPassive(character)
	end

	if characterName == "Stan.oma.png" and role == StatsModule.Role.Devilish then
		require(game:GetService("ServerScriptService").ServerModules.StanAbilities).StartPassiveTrail(character)
	end
end

local function teleportToGameMap()
	if not currentMap then
		warn("[MatchManager] No hay un mapa seleccionado en currentMap!")
		return
	end

	local toonflowSpawns = currentMap:FindFirstChild("ToonflowSpawns") or currentMap:FindFirstChild("ToonSpawns") or currentMap:FindFirstChild("Spawns")
	local devilishSpawns = currentMap:FindFirstChild("DevilishSpawns") or currentMap:FindFirstChild("KillerSpawns") or toonflowSpawns

	BotController.TeleportBotsToSpawns(toonflowSpawns, devilishSpawns)

	for player, role in pairs(assignedRoles) do
		if typeof(player) == "Instance" and player:IsA("Player") then
			local setupOk, setupErr = pcall(setupPlayerRole, player, role)
			if not setupOk then
				warn("[MatchManager] Error preparando a " .. player.Name .. ": " .. tostring(setupErr))
			end
			task.wait(0.2)

			local char = player.Character
			if char then
				local spawnFolder = (role == StatsModule.Role.Devilish) and devilishSpawns or toonflowSpawns
				local spawnPart = spawnFolder and getRandomSpawn(spawnFolder)

				if spawnPart then
					teleportPlayer(player, spawnPart)
					print("[MatchManager] Teletransportado " .. player.Name .. " (" .. tostring(role) .. ") a " .. spawnPart.Name)
				end
			end
		end
	end
end

local function teleportToLobby()
	local maps = workspace:FindFirstChild("Maps")
	local lobby = maps and maps:FindFirstChild("Lobby")
	if not lobby then return end

	local lobbySpawn = lobby:FindFirstChild("LobbySpawn")
	if not lobbySpawn then return end

	for _, player in ipairs(getAllPlayers()) do
		if player.Character then
			teleportPlayer(player, lobbySpawn)
		end
	end
end

local function countStandingToons()
	local standingCount = 0

	for playerOrBot, role in pairs(assignedRoles) do
		if role == StatsModule.Role.Toonflow then
			local char = (typeof(playerOrBot) == "Instance" and playerOrBot:IsA("Player")) and playerOrBot.Character or playerOrBot
			if char then
				local stats = StatsModule.GetStats(char)
				local isAlive = stats and stats:FindFirstChild("IsAlive") and stats.IsAlive.Value
				local isDowned = char:GetAttribute("IsDowned") or false

				if isAlive and not isDowned then
					standingCount += 1
				end
			end
		end
	end

	return standingCount
end

local function isDevilishAlive()
	for playerOrBot, role in pairs(assignedRoles) do
		if role == StatsModule.Role.Devilish then
			if typeof(playerOrBot) == "Instance" and playerOrBot:IsA("Player") then
				local player = playerOrBot
				if not player:IsDescendantOf(Players) then continue end

				local char = player.Character
				if char then
					local stats = StatsModule.GetStats(char)
					if stats then
						local isAlive = stats:FindFirstChild("IsAlive")
						if isAlive then return isAlive.Value end
					end
					return true
				else
					return true
				end
			else
				local botModel = playerOrBot
				local stats = StatsModule.GetStats(botModel)
				if stats then
					local isAlive = stats:FindFirstChild("IsAlive")
					if isAlive then return isAlive.Value end
				end
				return true
			end
		end
	end

	for _, model in ipairs(workspace:GetChildren()) do
		if string.find(model.Name, "BOT_") or model:GetAttribute("CharacterName") == "DummyDevilish" then
			local stats = StatsModule.GetStats(model)
			if stats then
				local role = stats:FindFirstChild("Role")
				local isAlive = stats:FindFirstChild("IsAlive")
				if role and role.Value == StatsModule.Role.Devilish and isAlive and isAlive.Value then
					return true
				end
			end
		end
	end

	return false
end

local function cleanupMatch()
	TaskManager.Stop()

	-- La salida no debe sobrevivir a la partida: antes el hilo del temporizador
	-- seguía corriendo, podía marcar exitClosed en la PARTIDA SIGUIENTE (victoria
	-- instantánea del Devilish) y la puerta quedaba abierta; además cada partida
	-- añadía otra conexión Touched al mismo Trigger sin soltar la anterior.
	if exitThread then
		task.cancel(exitThread)
		exitThread = nil
	end
	if exitOpen then
		setAllExitVisuals(false)
		ExitTimerRemote:FireAllClients({ remaining = 0, open = false })
	end
	exitOpen = false
	exitClosed = false
	for _, connection in ipairs(exitTriggerConnections) do
		connection:Disconnect()
	end
	table.clear(exitTriggerConnections)
	activeExits = {}
	for player, _ in pairs(assignedRoles) do
		if typeof(player) == "Instance" and player:IsA("Player") then
			AbilityFramework.ClearPlayer(player)
			if player.Character then
				local stats = player.Character:FindFirstChild("Stats")
				if stats then stats:Destroy() end
				player.Character:SetAttribute("Escaped", nil)
			end
		end
	end
	assignedRoles = {}
	escapedToonflows = {}
end

local function activateLMS()
	if lmsActivated then return end

	local lastToonflow = nil
	for player, role in pairs(assignedRoles) do
		if role == StatsModule.Role.Toonflow then
			local char = (typeof(player) == "Instance" and player:IsA("Player")) and player.Character or player
			if char then
				local stats = StatsModule.GetStats(char)
				if stats then
					local isAlive = stats:FindFirstChild("IsAlive")
					local isDowned = char:GetAttribute("IsDowned") or false
					-- En pie: vivo Y no derribado (la condición de LMS usa el mismo criterio).
					if isAlive and isAlive.Value and not isDowned then
						lastToonflow = player
						break
					end
				end
			end
		end
	end

	if not lastToonflow then return end
	lmsActivated = true
	lmsPlayer = lastToonflow

	local character = (typeof(lastToonflow) == "Instance" and lastToonflow:IsA("Player")) and lastToonflow.Character or lastToonflow
	if character then
		StatsModule.IncreaseMaxHealthPercent(character, MatchConfig.LMSHealthBonusPercent)
		StatsModule.RestoreHealth(character)
	end

	local nameStr = (typeof(lastToonflow) == "Instance") and lastToonflow.Name or "Toonflow"
	LMSActivatedRemote:FireAllClients({ player = nameStr })
	print("[MatchManager] LMS activado para " .. nameStr)
end

-- Duración de la salida abierta. PUNTO ÚNICO de la regla de "tiempo de salida según tareas" (QNA):
-- cuando se confirme la fórmula, se cambia SOLO esta función (hoy: valor fijo de MatchConfig).
-- Ver docs/QNA_ACTUALIZACION.md.
local function computeExitDuration()
	return MatchConfig.ExitOpenDuration
end

local function openExit(duration)
	if exitOpen then return end
	exitOpen = true
	exitClosed = false

	setAllExitVisuals(true)

	ExitTimerRemote:FireAllClients({ remaining = duration, open = true })

	if exitThread then task.cancel(exitThread) end
	exitThread = task.spawn(function()
		local remaining = duration
		while remaining > 0 do
			task.wait(1)
			remaining = remaining - 1
			if remaining % 5 == 0 then
				ExitTimerRemote:FireAllClients({ remaining = remaining, open = true })
			end
		end

		exitOpen = false
		exitClosed = true

		setAllExitVisuals(false)

		ExitTimerRemote:FireAllClients({ remaining = 0, open = false })
	end)
end

-- Zona segura de quienes escapan: "EscapeSpawn" (BasePart) dentro del mapa si existe;
-- si no, el spawn del lobby.
local function getSafeZoneSpawn()
	local mapSpawn = currentMap and currentMap:FindFirstChild("EscapeSpawn")
	if mapSpawn and mapSpawn:IsA("BasePart") then
		return mapSpawn
	end
	local maps = workspace:FindFirstChild("Maps")
	local lobby = maps and maps:FindFirstChild("Lobby")
	return lobby and lobby:FindFirstChild("LobbySpawn")
end

local function onExitTouched(otherPart)
	if not exitOpen then return end

	-- Model ancestro (no Parent): un accesorio o una parte anidada también cuenta
	local character = otherPart:FindFirstAncestorOfClass("Model")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end
	if assignedRoles[player] ~= StatsModule.Role.Toonflow then return end
	if escapedToonflows[player] then return end

	local stats = StatsModule.GetStats(character)
	local isAlive = stats and stats:FindFirstChild("IsAlive") and stats.IsAlive.Value
	local isDowned = character:GetAttribute("IsDowned") or false

	if isAlive and not isDowned then
		escapedToonflows[player] = true
		-- Invulnerable (StatsModule.ApplyDamage lo respeta) y fuera del alcance del
		-- Devilish: antes seguía en el mapa y podía ser golpeado después de escapar.
		character:SetAttribute("Escaped", true)
		local safeSpawn = getSafeZoneSpawn()
		if safeSpawn then
			teleportPlayer(player, safeSpawn)
		end
		print("[MatchManager] " .. player.Name .. " escapó exitosamente por la salida!")
	end
end

-- Un Touched por cada salida activa (cualquiera sirve para escapar)
local function setupExitTrigger()
	for _, connection in ipairs(exitTriggerConnections) do
		connection:Disconnect()
	end
	table.clear(exitTriggerConnections)

	for _, exitModel in ipairs(activeExits) do
		local trigger = exitModel:FindFirstChild("Trigger") or exitModel:FindFirstChild("ExitSpawn") or exitModel
		if trigger and trigger:IsA("BasePart") then
			table.insert(exitTriggerConnections, trigger.Touched:Connect(onExitTouched))
		end
	end
end

-- == ESTADOS DE PARTIDA ==

local function runIntermission()
	currentMatchState = MatchConfig.MatchState.Intermission
	broadcastMatchState(currentMatchState, {
		timer = MatchConfig.IntermissionDuration,
		message = "Esperando jugadores..."
	})

	local elapsed = 0
	local minReq = RunService:IsStudio() and 1 or MatchConfig.MinPlayers

	while elapsed < MatchConfig.IntermissionDuration do
		task.wait(1)
		elapsed = elapsed + 1

		local eligibleCount = #getEligiblePlayers()
		local totalPlayers = #getAllPlayers()

		if eligibleCount < minReq then
			elapsed = 0
			local afkCount = totalPlayers - eligibleCount
			local msg = "Esperando jugadores mínimos (" .. minReq .. ")..."
			if afkCount > 0 then
				msg = msg .. " (" .. afkCount .. " AFK)"
			end
			broadcastMatchState(currentMatchState, {
				timer = 0,
				message = msg
			})
		else
			broadcastMatchState(currentMatchState, {
				timer = MatchConfig.IntermissionDuration - elapsed,
				message = "La partida comienza en..."
			})
		end
	end
end

local function runRoleSelection()
	currentMatchState = MatchConfig.MatchState.RoleSelection

	local success = assignRoles()
	if not success then
		return false
	end

	local roleData = {}
	for player, role in pairs(assignedRoles) do
		if typeof(player) == "Instance" and player:IsA("Player") then
			roleData[player] = role
		end
	end

	broadcastMatchState(currentMatchState, {
		timer = MatchConfig.RoleSelectionDuration,
		roles = roleData,
	})

	for player, role in pairs(assignedRoles) do
		if typeof(player) == "Instance" and player:IsA("Player") then
			local characterName = nil
			if role == StatsModule.Role.Devilish then
				characterName = player:GetAttribute("SelectedDevilish") or CharacterDatabase.DefaultDevilish
			else
				characterName = player:GetAttribute("SelectedToonflow") or CharacterDatabase.DefaultToonflow
			end
			MatchStateRemote:FireClient(player, "RoleAssigned", { role = role, characterName = characterName })
		end
	end

	task.wait(MatchConfig.RoleSelectionDuration)
	return true
end

local function runMapVoting()
	currentMatchState = MatchConfig.MatchState.MapVoting

	local devilishPlayer = nil
	for player, role in pairs(assignedRoles) do
		if role == StatsModule.Role.Devilish and typeof(player) == "Instance" and player:IsA("Player") then
			devilishPlayer = player
			break
		end
	end

	broadcastMatchState(currentMatchState, {
		timer = MatchConfig.MapVoteDuration,
	})

	local mapName = nil
	if devilishPlayer then
		local options = MapSelection.GetVoteOptions(3)
		local chosen = MapSelection.RunVote(devilishPlayer, options, MatchConfig.MapVoteDuration)
		mapName = chosen or (options[1] and options[1].Name) or MapSelection.PickRandomMap()
	else
		mapName = MapSelection.PickRandomMap()
	end

	local maps = workspace:FindFirstChild("Maps")
	currentMap = (maps and typeof(mapName) == "string") and maps:FindFirstChild(mapName) or nil
	if not currentMap then
		-- Antes se seguía con currentMap = nil: los jugadores se quedaban en el lobby
		-- con roles asignados y la partida corría hasta agotar el tiempo.
		warn("[MatchManager] No se encontró el mapa '" .. tostring(mapName) .. "': se cancela esta partida.")
		return false
	end
	MapChosenRemote:FireAllClients({ mapName = mapName })
	return true
end

local function runInProgress()
	currentMatchState = MatchConfig.MatchState.InProgress

	teleportToGameMap()
	task.wait(3)

	aliveToons = countStandingToons()
	escapedToonflows = {}
	lmsActivated = false
	lmsPlayer = nil
	exitOpen = false
	exitClosed = false
	tasksCompleted = 0

	activeExits = selectActiveExits()
	setupExitTrigger()

	broadcastMatchState(currentMatchState, {
		timer = MatchConfig.MaxMatchDuration,
		message = "¡La partida ha comenzado!",
		aliveToons = aliveToons,
	})

	if TaskManager and typeof(TaskManager.Start) == "function" then
		TaskManager.Start(currentMap, {
			onTaskCompleted = function(completed, total, player)
				tasksCompleted = completed
				if player then
					CartoonsitosManager.RewardTaskRepaired(player)
				end
				-- NOTIFICAR A LA GUI DEL CLIENTE
				if TaskProgressRemote then
					TaskProgressRemote:FireAllClients({ completed = completed, total = total })
				end
			end,
			onAllCompleted = function(completed, total)
				tasksCompleted = completed
				if TaskProgressRemote then
					TaskProgressRemote:FireAllClients({ completed = completed, total = total })
				end
				if not exitOpen then
					openExit(computeExitDuration())
				end
			end,
		})
	end

	local elapsed = 0

	while true do
		task.wait(1)
		elapsed = elapsed + 1

		local aliveInMapCount = 0
		local escapedCount = 0

		for playerOrBot, role in pairs(assignedRoles) do
			if role == StatsModule.Role.Toonflow then
				local player = (typeof(playerOrBot) == "Instance" and playerOrBot:IsA("Player")) and playerOrBot or nil

				if player and escapedToonflows[player] then
					escapedCount += 1
				else
					local char = player and player.Character or playerOrBot
					if char then
						local stats = StatsModule.GetStats(char)
						local isAlive = stats and stats:FindFirstChild("IsAlive") and stats.IsAlive.Value
						local isDowned = char:GetAttribute("IsDowned") or false

						if isAlive and not isDowned then
							aliveInMapCount += 1
						end
					end
				end
			end
		end

		-- Contar los escapados desde escapedToonflows, no desde assignedRoles: un Toonflow que escapa y
		-- luego se desconecta salía de assignedRoles y la partida pasaba de victoria de Toonflows a
		-- "el Devilish eliminó a todos".
		escapedCount = 0
		for _ in pairs(escapedToonflows) do
			escapedCount += 1
		end

		aliveToons = aliveInMapCount

		-- LMS: Queda solo 1 Toonflow
		if aliveInMapCount == 1 and escapedCount == 0 and not lmsActivated then
			activateLMS()
		end

		-- CONDICIÓN 1: Ya no quedan Toonflows en el mapa
		if aliveInMapCount == 0 then
			if escapedCount > 0 then
				broadcastMatchState(currentMatchState, {
					timer = 0,
					message = "¡Los Toonflows escaparon por la salida!",
					winner = "Toonflows",
				})
				return "ToonflowsWin"
			else
				broadcastMatchState(currentMatchState, {
					timer = 0,
					message = "El Devilish ha eliminado a todos los Toonflows",
					winner = "Devilish",
				})
				return "DevilishWins"
			end
		end

		-- CONDICIÓN 2: El Devilish fue derrotado
		if not isDevilishAlive() then
			broadcastMatchState(currentMatchState, {
				timer = 0,
				message = "¡Los Toonflows derrotaron al Devilish!",
				winner = "Toonflows",
			})
			return "ToonflowsWin"
		end

		-- CONDICIÓN 3: El tiempo de la salida abierta expiró
		if exitClosed then
			broadcastMatchState(currentMatchState, {
				timer = 0,
				message = "¡La salida se cerró! El Devilish gana.",
				winner = "Devilish",
			})
			return "DevilishWins"
		end

		-- CONDICIÓN 4: Tiempo máximo de ronda alcanzado sin completar tareas
		if elapsed >= MatchConfig.MaxMatchDuration and not exitOpen then
			broadcastMatchState(currentMatchState, {
				timer = 0,
				message = "¡Tiempo agotado sin reparar las tareas! El Devilish gana.",
				winner = "Devilish",
			})
			return "DevilishWins"
		end

		if elapsed % 5 == 0 then
			broadcastMatchState(currentMatchState, {
				timer = math.max(0, MatchConfig.MaxMatchDuration - elapsed),
				aliveToons = aliveToons,
			})
		end
	end
end

local function runEnding(winner)
	currentMatchState = MatchConfig.MatchState.Ending

	CartoonsitosManager.ProcessMatchEnd(winner, assignedRoles, escapedToonflows)

	local masteryBindable = ServerScriptService:FindFirstChild("ProcessMasteryMatchEnd")
	if masteryBindable then
		for player, role in pairs(assignedRoles) do
			if typeof(player) == "Instance" and player:IsA("Player") then
				local characterName = nil
				if role == StatsModule.Role.Devilish then
					characterName = player:GetAttribute("SelectedDevilish") or CharacterDatabase.DefaultDevilish
				else
					characterName = player:GetAttribute("SelectedToonflow") or CharacterDatabase.DefaultToonflow
				end

				local isWinner = false
				if winner == "ToonflowsWin" and role == StatsModule.Role.Toonflow then
					isWinner = true
				elseif winner == "DevilishWins" and role == StatsModule.Role.Devilish then
					isWinner = true
				end

				local isLMS = (lmsPlayer == player)

				masteryBindable:Fire(player, characterName, isWinner, isLMS)
			end
		end
	end

	-- El HUD compara data.winner con "Toonflows"/"Devilish". Antes se enviaba el
	-- resultado interno ("ToonflowsWin"/"DevilishWins"), así que el cartel final
	-- siempre decía "¡EL DEVILISH GANA!", incluso cuando ganaban los Toonflows.
	broadcastMatchState(currentMatchState, {
		timer = MatchConfig.EndMatchDuration,
		winner = (winner == "ToonflowsWin") and "Toonflows" or "Devilish",
		result = winner,
	})

	task.wait(MatchConfig.EndMatchDuration)
	BotController.ClearAllBots()
	teleportToLobby()
	cleanupMatch()
end

local function runMatchCycle()
	runIntermission()

	local roleSuccess = runRoleSelection()
	if not roleSuccess then
		return
	end

	if not runMapVoting() then
		cleanupMatch()
		return
	end

	local result = runInProgress()
	runEnding(result)
end

-- Devuelve el servidor a un estado limpio tras un error a mitad de partida.
local function recoverFromError()
	pcall(BotController.ClearAllBots)
	pcall(teleportToLobby)
	pcall(cleanupMatch)
	currentMatchState = MatchConfig.MatchState.Intermission
end

-- Antes, cualquier error en cualquier fase (p. ej. una recompensa, un teleport)
-- terminaba este hilo y el servidor se quedaba sin partidas hasta reiniciarlo.
local function matchLoop()
	while true do
		local ok, err = pcall(runMatchCycle)
		if not ok then
			warn("[MatchManager] Error en el ciclo de partida, recuperando: " .. tostring(err))
			recoverFromError()
			task.wait(3) -- evita un bucle de errores a toda velocidad
		end
	end
end

-- == CONEXIONES DE JUGADORES ==

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		if currentMatchState == MatchConfig.MatchState.Intermission then
			task.wait(0.5)
			local maps = workspace:FindFirstChild("Maps")
			local lobby = maps and maps:FindFirstChild("Lobby")
			if lobby then
				local lobbySpawn = lobby:FindFirstChild("LobbySpawn")
				if lobbySpawn then
					teleportPlayer(player, lobbySpawn)
				end
			end
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	assignedRoles[player] = nil
	AbilityFramework.ClearPlayer(player)
end)

matchThread = task.spawn(matchLoop)

print("[MatchManager] Sistema de partida inicializado correctamente.")