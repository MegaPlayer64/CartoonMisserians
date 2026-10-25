--[[
	MusicManagerClient (LocalScript)
	Ubicación: StarterPlayer.StarterPlayerScripts.MusicManagerClient
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

-- LIMPIEZA DE SCRIPT ANTIGUO (MusicChaseLS)
local oldChaseScript = script.Parent:FindFirstChild("MusicChaseLS")
if oldChaseScript then
	pcall(function()
		oldChaseScript.Disabled = true
		oldChaseScript:Destroy()
	end)
end

local MusicData = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("MusicData"))
local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local MatchStateRemote = Remotes:WaitForChild("MatchState")
local MapChosenRemote = Remotes:FindFirstChild("MapChosen")

local FADE_TIME = 0.8
local VOLUMES = {
	Lobby = 0.4,
	Ambient = 0.5,
	Tension1 = 0.5,
	Tension2 = 0.6,
	Tension3 = 0.7,
	Chase = 0.8,
}

local currentPhase = ""
local inMatch = false
local myRole = nil
local currentMapName = "Default"
local devilishPlayer = nil
local devilishCharacter = nil

local sounds = {}
local activeTweens = {}

local function clearTween(key)
	if activeTweens[key] then
		activeTweens[key]:Cancel()
		activeTweens[key] = nil
	end
end

local function fadeSound(key, targetVol, duration)
	local s = sounds[key]
	if not s then return end
	clearTween(key)
	local tween = TweenService:Create(
		s,
		TweenInfo.new(duration or FADE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ Volume = targetVol }
	)
	activeTweens[key] = tween
	tween:Play()
end

local function ensureSound(key, soundId)
	if sounds[key] then
		if sounds[key].SoundId ~= soundId then
			sounds[key].SoundId = soundId
			sounds[key].TimePosition = 0
		end
		return sounds[key]
	end

	local s = Instance.new("Sound")
	s.Name = "MusicManager_" .. key
	s.SoundId = soundId
	s.Volume = 0
	s.Looped = true
	s.Parent = SoundService
	s:Play()
	sounds[key] = s
	return s
end

local function destroySound(key)
	if sounds[key] then
		clearTween(key)
		sounds[key]:Stop()
		sounds[key]:Destroy()
		sounds[key] = nil
	end
end

local function switchPhase(newPhase, soundId)
	if currentPhase == newPhase then return end
	currentPhase = newPhase

	if soundId then
		ensureSound(newPhase, soundId)
	end

	for key, _ in pairs(sounds) do
		if key == newPhase then
			local targetVol = VOLUMES[newPhase] or 0.5
			fadeSound(key, targetVol, FADE_TIME)
		else
			fadeSound(key, 0, FADE_TIME)
		end
	end

	task.delay(FADE_TIME + 0.2, function()
		for key, _ in pairs(sounds) do
			if key ~= currentPhase and sounds[key] and sounds[key].Volume <= 0.01 then
				destroySound(key)
			end
		end
	end)
end

-- BÚSQUEDA DINÁMICA DE AUDIOS SEGÚN PERSONAJE O SKIN
local function getDevilishSoundId(devilishChar, soundType)
	if not devilishChar then
		if soundType == "Chase" then
			return MusicData.ChaseThemes["Default"]
		else
			return MusicData.TensionLayers["Default"][soundType]
		end
	end

	local skin = devilishChar:GetAttribute("EquippedSkin") or devilishChar:GetAttribute("MasterySkin")
	local charName = devilishChar:GetAttribute("CharacterName") or devilishChar:GetAttribute("SelectedDevilish")

	-- 1. Evaluar si es el Tema de Persecución (Chase)
	if soundType == "Chase" then
		if skin and MusicData.ChaseThemes[skin] then
			return MusicData.ChaseThemes[skin]
		end
		if charName and MusicData.ChaseThemes[charName] then
			return MusicData.ChaseThemes[charName]
		end
		return MusicData.ChaseThemes["Default"]
	end

	-- 2. Evaluar si es una Capa de Tensión (Layer1, Layer2, Layer3)
	if skin and MusicData.TensionLayers[skin] and MusicData.TensionLayers[skin][soundType] then
		return MusicData.TensionLayers[skin][soundType]
	end

	if charName and MusicData.TensionLayers[charName] and MusicData.TensionLayers[charName][soundType] then
		return MusicData.TensionLayers[charName][soundType]
	end

	return MusicData.TensionLayers["Default"][soundType]
end

local function findDevilishPlayer()
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and p.Character then
			local stats = p.Character:FindFirstChild("Stats")
			if stats and stats:FindFirstChild("Role") and stats.Role.Value == "Devilish" then
				return p
			end
			if p.Character:GetAttribute("Role") == "Devilish" then
				return p
			end
		end
	end
	return nil
end

local function isPlayerAlive(p)
	local char = p and p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0
end

-- BUCLE PRINCIPAL DE DISTANCIA
local loopThread = nil

local function startAudioLoop()
	if loopThread then return end
	loopThread = task.spawn(function()
		while inMatch do
			task.wait(0.2)

			if myRole ~= "Toonflow" or not isPlayerAlive(player) then
				local mapId = MusicData.Maps[currentMapName] or MusicData.Maps["Default"]
				switchPhase("Ambient", mapId)
				continue
			end

			if not devilishPlayer or not devilishPlayer.Parent then
				devilishPlayer = findDevilishPlayer()
			end

			if devilishPlayer and devilishPlayer.Character ~= devilishCharacter then
				devilishCharacter = devilishPlayer.Character
			end

			if not (devilishCharacter and isPlayerAlive(devilishPlayer)) then
				local mapId = MusicData.Maps[currentMapName] or MusicData.Maps["Default"]
				switchPhase("Ambient", mapId)
				continue
			end

			local myHRP = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local devilishHRP = devilishCharacter:FindFirstChild("HumanoidRootPart")

			if not (myHRP and devilishHRP) then continue end

			local dist = (myHRP.Position - devilishHRP.Position).Magnitude

			-- Radio de terror: un Devilish puede reducirlo (p. ej. la pasiva de Shed.mov lo deja al 50%
			-- fuera de persecución). Escalar la distancia desplaza TODAS las capas de tensión a la vez.
			local terrorMultiplier = devilishCharacter:GetAttribute("TerrorRadiusMultiplier") or 1
			dist = dist / math.max(terrorMultiplier, 0.1)

			-- EVALUACIÓN DE CAPAS DE TENCIÓN Y CHASE PERSONALIZADAS
			if dist < 25 then
				local chaseId = getDevilishSoundId(devilishCharacter, "Chase")
				switchPhase("Chase", chaseId)

			elseif dist >= 25 and dist < 45 then
				local layer3Id = getDevilishSoundId(devilishCharacter, "Layer3")
				switchPhase("Tension3", layer3Id)

			elseif dist >= 45 and dist < 80 then
				local layer2Id = getDevilishSoundId(devilishCharacter, "Layer2")
				switchPhase("Tension2", layer2Id)

			elseif dist >= 80 and dist <= 120 then
				local layer1Id = getDevilishSoundId(devilishCharacter, "Layer1")
				switchPhase("Tension1", layer1Id)

			else
				local mapId = MusicData.Maps[currentMapName] or MusicData.Maps["Default"]
				switchPhase("Ambient", mapId)
			end
		end
	end)
end

local function stopAudioLoop()
	if loopThread then
		task.cancel(loopThread)
		loopThread = nil
	end
end

-- EVENTOS DE ESTADO
MatchStateRemote.OnClientEvent:Connect(function(state, data)
	if state == "Intermission" then
		inMatch = false
		myRole = nil
		devilishPlayer = nil
		devilishCharacter = nil
		stopAudioLoop()
		switchPhase("Lobby", MusicData.Lobby)

	elseif state == "RoleAssigned" then
		if data and data.role then
			myRole = data.role
		end

	elseif state == "InProgress" then
		-- El servidor repite InProgress cada 5 s para sincronizar el reloj: solo la primera vez
		-- se pasa a Ambient. Antes cada repetición cortaba la música de persecución cada 5 s.
		if not inMatch then
			inMatch = true
			local mapId = MusicData.Maps[currentMapName] or MusicData.Maps["Default"]
			switchPhase("Ambient", mapId)
		end
		startAudioLoop()

	elseif state == "Ending" then
		inMatch = false
		stopAudioLoop()
		switchPhase("Lobby", MusicData.Lobby)
	end
end)

if MapChosenRemote then
	MapChosenRemote.OnClientEvent:Connect(function(data)
		local mapName = nil
		if typeof(data) == "table" then
			mapName = data.mapName or data.name
		elseif typeof(data) == "string" then
			mapName = data
		end

		if mapName then
			currentMapName = mapName
			if inMatch and currentPhase == "Ambient" then
				local mapId = MusicData.Maps[mapName] or MusicData.Maps["Default"]
				switchPhase("Ambient", mapId)
			end
		end
	end)
end

local function connectDeath(character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid then
		humanoid.Died:Connect(function()
			if inMatch then
				local mapId = MusicData.Maps[currentMapName] or MusicData.Maps["Default"]
				switchPhase("Ambient", mapId)
			end
		end)
	end
end

player.CharacterAdded:Connect(connectDeath)
if player.Character then connectDeath(player.Character) end

switchPhase("Lobby", MusicData.Lobby)
print("[MusicManagerClient] Sistema de audio con Capas de Tensión y Chase por Personaje/Skin activo.")