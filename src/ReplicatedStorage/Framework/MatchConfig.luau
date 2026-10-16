--[[
	MatchConfig (ModuleScript)
	Ubicacion: ReplicatedStorage.Framework.MatchConfig

	Configuracion central del sistema de partida. Define tiempos, limites
	y parametros ajustables del Match Loop. Compartido entre servidor y cliente.
]]

local MatchConfig = {}

-- == TIEMPOS DE PARTIDA (segundos) ==
MatchConfig.IntermissionDuration = 30       -- Tiempo en lobby antes de iniciar
MatchConfig.RoleSelectionDuration = 10      -- Seleccion de personajes (30s)
MatchConfig.MapVoteDuration = 15             -- Seleccion de mapa por el Devilish (15s)
MatchConfig.MaxMatchDuration = 300          -- 5 minutos maximos de partida
MatchConfig.EndMatchDuration = 15           -- Tiempo en pantalla de fin de partida

-- == CONFIGURACION DE ROLES ==
MatchConfig.MaxPlayers = 8                  -- Jugadores maximos por partida
MatchConfig.MinPlayers = 2                  -- Minimo para iniciar partida
MatchConfig.DevilishCount = 1               -- Siempre 1 Devilish

-- == STATS BASE DE TOONFLOWS ==
MatchConfig.Toonflow = {
	MaxHealth = 100,
	WalkSpeed = 16,
	RunSpeed = 24,
	DownedHealth = 50,           -- Salud al estar derribado
	ReviveTime = 5,              -- Tiempo para revivir a un companero
	BleedOutTime = 30,           -- Tiempo antes de morir cuando esta derribado
}

-- == STATS BASE DE DEVILISH ==
MatchConfig.Devilish = {
	MaxHealth = 200,
	WalkSpeed = 18,
	AttackRange = 8,             -- Rango del ataque melee en studs
	AttackCooldown = 1.0,        -- Cooldown entre ataques en segundos
	AttackDamage = 35,           -- Dano base del ataque melee
	AbsorptionMax = 100,         -- Barra de absorcion/especial maxima
	AbsorptionPerHit = 10,       -- Absorcion ganada por golpe exitoso
}

-- == SISTEMA DE TAREAS Y SALIDA ==
MatchConfig.TaskCount = 6                       -- Tareas interactivas en el mapa
MatchConfig.TaskHoldDuration = 3               -- Segundos manteniendo E para completar
MatchConfig.ExitOpenDuration = 70              -- 1m 10s de salida al completar las 6 tareas
MatchConfig.ExitOpenDurationPenalty = 50       -- 50s si se agota el tiempo sin completar tareas

-- == LAST MAN STANDING ==
MatchConfig.LMSHealthBonusPercent = 0.2        -- +20% de MaxHealth permanente

-- == MAPAS DISPONIBLES ==
-- Cada mapa debe ser un Model dentro de Workspace.Maps con carpetas
-- "ToonflowSpawns" y "DevilishSpawns" que contengan Parts como puntos de spawn.
-- Categoria: "Pequeño", "Mediano" o "Grande".
MatchConfig.MapCategories = {
	Pequeno = "Pequeño",
	Mediano = "Mediano",
	Grande = "Grande",
}

MatchConfig.AvailableMaps = {
	{ Name = "GameMap_Example", Category = "Mediano" },
	{ Name = "DigitalCircus", Category = "Grande" },
}

-- == ESTADOS DE PARTIDA (enum-like) ==
MatchConfig.MatchState = {
	Intermission   = "Intermission",
	RoleSelection  = "RoleSelection",
	MapVoting      = "MapVoting",
	InProgress     = "InProgress",
	Ending         = "Ending",
}

return MatchConfig