--[[
	MasteryAndTrophyServer (Script)
	Ubicacion: ServerScriptService.MasteryAndTrophyServer

	Gestor del sistema de Maestrias de Personaje (niveles 1-100) y Trofeos/Logros.
	- Otorga XP por partida jugada (150 XP)
- Verifica y desbloquea logros automaticamente
	- Premio nivel 100: skin exclusiva en OwnedSkins (JSON)
	- Persistencia mediante atributos en Player (JSON)

	Dependencias:
	  - ServerScriptService.ServerModules.AchievementsAndMastery
	  - ServerScriptService.CartoonsitosManager
	  - ReplicatedStorage.Framework.Remotes.MasteryUpdate
	  - ReplicatedStorage.Framework.Remotes.TrophyUnlock
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

local AchievementsAndMastery = require(game:GetService("ServerScriptService").ServerModules.AchievementsAndMastery)
local CartoonsitosManager = require(ServerScriptService:WaitForChild("CartoonsitosManager"))
local PlayerData = require(game:GetService("ServerScriptService").ServerModules.PlayerData)
local CharacterDatabase = require(ReplicatedStorage.Framework.CharacterDatabase)

local Remotes = ReplicatedStorage.Framework.Remotes
local MasteryUpdateRemote = Remotes:WaitForChild("MasteryUpdate")
local TrophyUnlockRemote = Remotes:WaitForChild("TrophyUnlock")

-- == HELPERS DE PERSISTENCIA (JSON en atributos) ==

local function getPlayerData(player)
	local raw = player:GetAttribute("MasteryData")
	if not raw then
		return {
			TotalWins = 0,
			TotalMatches = 0,
			BrothercatLMSCount = 0,
			UnlockedAchievements = {},
			CharacterMastery = {}, -- [characterName] = { TotalXP = 0, Level = 1 }
			OwnedSkins = {},
		}
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not ok or type(data) ~= "table" then
		return {
			TotalWins = 0,
			TotalMatches = 0,
			BrothercatLMSCount = 0,
			UnlockedAchievements = {},
			CharacterMastery = {},
			OwnedSkins = {},
		}
	end
	-- Asegurar campos existen
	data.TotalWins = data.TotalWins or 0
	data.TotalMatches = data.TotalMatches or 0
	data.BrothercatLMSCount = data.BrothercatLMSCount or 0
	data.UnlockedAchievements = data.UnlockedAchievements or {}
	data.CharacterMastery = data.CharacterMastery or {}
	data.OwnedSkins = data.OwnedSkins or {}
	return data
end

local function setPlayerData(player, data)
	player:SetAttribute("MasteryData", HttpService:JSONEncode(data))
end

local function getCharacterMastery(data, characterName)
	if not data.CharacterMastery[characterName] then
		data.CharacterMastery[characterName] = { TotalXP = 0, Level = 1 }
	end
	return data.CharacterMastery[characterName]
end

local function ownsSkin(data, skinId)
	for _, id in ipairs(data.OwnedSkins) do
		if id == skinId then return true end
	end
	return false
end

-- == NOTIFICACIONES AL CLIENTE ==

local function notifyMasteryUpdate(player, characterName, level, currentXP, xpToNext)
	MasteryUpdateRemote:FireClient(player, {
		characterName = characterName,
		level = level,
		currentXP = currentXP,
		xpToNext = xpToNext,
		maxLevel = AchievementsAndMastery.MAX_LEVEL,
	})
end

local function notifyTrophyUnlock(player, achievementId, achievementName, coinReward)
	TrophyUnlockRemote:FireClient(player, {
		id = achievementId,
		name = achievementName,
		coinReward = coinReward,
	})
end

-- == API PUBLICA ==

--[[
	Otorga XP de maestria a un jugador para un personaje especifico.
	Verifica subida de nivel y desbloquea skin exclusiva al nivel 100.
]]
local function addMasteryXP(player, characterName, xpAmount)
	if not (player and player:IsA("Player") and characterName) then return end

	local data = getPlayerData(player)
	local mastery = getCharacterMastery(data, characterName)

	if mastery.Level >= AchievementsAndMastery.MAX_LEVEL then
		return -- Ya esta al maximo nivel
	end

	mastery.TotalXP = mastery.TotalXP + xpAmount

	local newLevel, currentXP, xpToNext = AchievementsAndMastery.CalculateLevel(mastery.TotalXP)
	local leveledUp = newLevel > mastery.Level
	mastery.Level = newLevel

	setPlayerData(player, data)
	notifyMasteryUpdate(player, characterName, newLevel, currentXP, xpToNext)

	if leveledUp then
		print(string.format("[Mastery] %s subio a nivel %d con %s",
			player.Name, newLevel, characterName))
	end

	-- Premio nivel 100: skin exclusiva
	if newLevel >= AchievementsAndMastery.MAX_LEVEL and not ownsSkin(data, AchievementsAndMastery.MASTERY_100_SKIN) then
		table.insert(data.OwnedSkins, AchievementsAndMastery.MASTERY_100_SKIN)
		setPlayerData(player, data)
		print("[Mastery] " .. player.Name .. " desbloqueo la skin exclusiva de Maestria 100 con " .. characterName .. "!")
	end
end

--[[
	Registra una victoria para el jugador y su personaje.
	Verifica logros, otorga recompensas en coins y XP de maestria.
]]
local function registerWin(player, characterName, isLMS)
	if not (player and player:IsA("Player")) then return end

	local data = getPlayerData(player)
	data.TotalWins = data.TotalWins + 1

	if isLMS and characterName == "Brothercat" then
		data.BrothercatLMSCount = data.BrothercatLMSCount + 1
	end

	setPlayerData(player, data)
end

--[[
	Procesa el fin de partida para un jugador: XP, victorias, logros.
	Parametros:
	  player        -> Player
	  characterName -> string (personaje usado)
	  isWinner      -> bool (si el jugador gano)
	  isLMS         -> bool (si el jugador fue el ultimo sobreviviente)
]]
local function processMatchEnd(player, characterName, isWinner, isLMS)
	if not (player and player:IsA("Player") and characterName) then return end
	-- Sin perfil cargado no se toca nada (se perdería o se sobrescribiría al cargar).
	if not PlayerData.isLoaded(player) then return end

	-- Nombre canónico: la selección podía traer el DisplayName y partir la maestría en dos.
	local characterData = CharacterDatabase.GetCharacterData(characterName)
	if characterData then
		characterName = characterData.Name
	end

	-- 1. Contar la partida y GUARDARLA ya: registerWin y addMasteryXP vuelven a leer
	--    el atributo, así que antes este incremento se perdía y TotalMatches nunca subía.
	local data = getPlayerData(player)
	data.TotalMatches = data.TotalMatches + 1
	setPlayerData(player, data)

	if isWinner then
		registerWin(player, characterName, isLMS)
	end

	-- 2. Otorgar XP de maestria por participar en la partida
	addMasteryXP(player, characterName, AchievementsAndMastery.XP_PER_MATCH)

	-- 3. Verificar logros con datos RECARGADOS: antes TotalWins llegaba sin la victoria
	--    de esta partida y cada logro se desbloqueaba una partida tarde.
	data = getPlayerData(player)
	local stats = {
		TotalWins = data.TotalWins,
		BrothercatLMSCount = data.BrothercatLMSCount,
	}

	local newlyUnlocked = AchievementsAndMastery.CheckAchievements(stats, data.UnlockedAchievements)

	for _, achievementId in ipairs(newlyUnlocked) do
		data = getPlayerData(player) -- Recargar datos actualizados
		data.UnlockedAchievements[achievementId] = true
		setPlayerData(player, data)

		local achievement = AchievementsAndMastery.GetAchievement(achievementId)
		if achievement then
			CartoonsitosManager.AddCoins(player, achievement.CoinReward, "Logro: " .. achievement.Name)
			notifyTrophyUnlock(player, achievementId, achievement.Name, achievement.CoinReward)
			print(string.format("[Mastery] %s desbloqueo el logro: %s (+%d coins)",
				player.Name, achievement.Name, achievement.CoinReward))
		end
	end

	-- 4. Guardar ya: el fin de partida es el momento con más progreso nuevo.
	PlayerData.saveNow(player)
end

-- == EXPONER FUNCIONES VIA BINDABLE PARA MATCHMANAGER ==

local function setupBindable()
	local bindable = ServerScriptService:FindFirstChild("ProcessMasteryMatchEnd")
	if not bindable then
		bindable = Instance.new("BindableEvent")
		bindable.Name = "ProcessMasteryMatchEnd"
		bindable.Parent = ServerScriptService
	end

	bindable.Event:Connect(function(player, characterName, isWinner, isLMS)
		processMatchEnd(player, characterName, isWinner, isLMS)
	end)
end

setupBindable()

-- == INICIALIZACION DE JUGADORES ==

local function defaultMasteryData()
	return {
		TotalWins = 0,
		TotalMatches = 0,
		BrothercatLMSCount = 0,
		UnlockedAchievements = {},
		CharacterMastery = {},
		OwnedSkins = {},
	}
end

-- MasteryData (si existía) la carga PlayerData. Solo cuando el perfil ya cargó y no
-- había nada guardado ponemos el valor por defecto; antes se ponía al entrar y
-- cualquier progreso se perdía al salir.
local function initPlayer(player)
	local function ensureDefault()
		if not player:GetAttribute("MasteryData") then
			setPlayerData(player, defaultMasteryData())
		end
	end

	if PlayerData.isLoaded(player) then
		ensureDefault()
		return
	end

	local connection
	connection = player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
		if PlayerData.isLoaded(player) then
			connection:Disconnect()
			ensureDefault()
		end
	end)
end

Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(function(player)
	-- Nada que limpiar, los datos estan en atributos
end)

for _, p in ipairs(Players:GetPlayers()) do
	initPlayer(p)
end

print("[MasteryAndTrophyServer] Sistema de Maestrias y Trofeos inicializado.")