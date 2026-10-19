--[[
	AchievementsAndMastery (ModuleScript)
	Ubicacion: ServerScriptService.ServerModules.AchievementsAndMastery

	Base de datos del sistema de Trofeos/Logros y Maestrias de Personaje.
	- Maestria: niveles 1 al 100 con formula de XP escalar (level * 200)
	- Logros: FirstWin, Win10, Win100, BlazerBrothercatLMS
	- Premio nivel 100: skin exclusiva registrada en OwnedSkins (JSON)
]]

local AchievementsAndMastery = {}

-- == CONFIGURACION DE MAESTRIA ==
AchievementsAndMastery.MAX_LEVEL = 100
AchievementsAndMastery.XP_PER_MATCH = 150

--[[
	Formula de XP necesaria para subir de nivel:
	  XP necesaria para pasar de 'level' a 'level + 1' = level * 200
	  Ejemplo: nivel 1 -> 200 XP, nivel 10 -> 2000 XP, nivel 50 -> 10000 XP
]]
function AchievementsAndMastery.GetXPForLevel(level)
	return level * 200
end

--[[
	Calcula el nivel y XP actual dados los XP totales acumulados.
	Devuelve: level (int), currentXP (int), xpToNext (int)
]]
function AchievementsAndMastery.CalculateLevel(totalXP)
	local level = 1
	local remaining = totalXP

	while level < AchievementsAndMastery.MAX_LEVEL do
		local xpNeeded = AchievementsAndMastery.GetXPForLevel(level)
		if remaining < xpNeeded then
			break
		end
		remaining = remaining - xpNeeded
		level = level + 1
	end

	if level >= AchievementsAndMastery.MAX_LEVEL then
		return AchievementsAndMastery.MAX_LEVEL, 0, 0
	end

	local xpToNext = AchievementsAndMastery.GetXPForLevel(level)
	return level, remaining, xpToNext
end

--[[
	Devuelve la XP total acumulada necesaria para alcanzar un nivel dado.
]]
function AchievementsAndMastery.GetTotalXPForLevel(targetLevel)
	local total = 0
	for i = 1, targetLevel - 1 do
		total = total + AchievementsAndMastery.GetXPForLevel(i)
	end
	return total
end

-- == DEFINICION DE LOGROS / TROFEOS ==
AchievementsAndMastery.Achievements = {
	FirstWin = {
		Id = "FirstWin",
		Name = "Primera Victoria",
		Description = "Gana tu primera partida como Toonflow",
		CoinReward = 100,
		Condition = function(stats)
			return stats.TotalWins >= 1
		end,
	},
	Win10 = {
		Id = "Win10",
		Name = "Veterano",
		Description = "Gana 10 partidas",
		CoinReward = 500,
		Condition = function(stats)
			return stats.TotalWins >= 10
		end,
	},
	Win100 = {
		Id = "Win100",
		Name = "Leyenda",
		Description = "Gana 100 partidas",
		CoinReward = 2500,
		Condition = function(stats)
			return stats.TotalWins >= 100
		end,
	},
	BlazerBrothercatLMS = {
		Id = "BlazerBrothercatLMS",
		Name = "Blazer Brothercat LMS",
		Description = "Sobrevive como ultimo Toonflow con Brothercat",
		CoinReward = 1000,
		Condition = function(stats)
			return stats.BrothercatLMSCount >= 1
		end,
	},
}

--[[
	Verifica todos los logros contra las estadisticas del jugador.
	Devuelve una lista de IDs de logros recien desbloqueados.
]]
function AchievementsAndMastery.CheckAchievements(stats, unlockedAchievements)
	unlockedAchievements = unlockedAchievements or {}
	local newlyUnlocked = {}

	for id, achievement in pairs(AchievementsAndMastery.Achievements) do
		if not unlockedAchievements[id] then
			if achievement.Condition(stats) then
				table.insert(newlyUnlocked, id)
			end
		end
	end

	return newlyUnlocked
end

--[[
	Obtiene los datos de un logro por su ID.
]]
function AchievementsAndMastery.GetAchievement(id)
	return AchievementsAndMastery.Achievements[id]
end

-- == SKIN EXCLUSIVA DE NIVEL 100 ==
AchievementsAndMastery.MASTERY_100_SKIN = "GoldenMasterySkin"

return AchievementsAndMastery