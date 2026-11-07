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
-- (ExitOpenDuration ya no se usa: la salida tiene ahora un temporizador dinámico, ver ExitTiming.)
MatchConfig.ExitOpenDuration = 70

-- TEMPORIZADOR DE SALIDA DINÁMICO (QNA). Las partidas duran ~5 minutos.
--  * Sin tareas la salida se abre igualmente, pero tarde: en el último minuto (BaseOpenAt).
--  * Cada tarea purificada adelanta esa apertura; con todas, hasta MaxTaskReduction segundos antes.
--  * Una vez abierta dura entre WindowNoTasks (0:50) y WindowAllTasks (1:10), según las tareas hechas.
MatchConfig.ExitTiming = {
	BaseOpenAt = 240, -- segundo de la partida en el que se abre sin tareas (4:00 = último minuto)
	MaxTaskReduction = 120, -- con todas las tareas se adelanta hasta 2:00
	WindowNoTasks = 50, -- 0:50 abierta sin tareas
	WindowAllTasks = 70, -- 1:10 abierta con todas
}

-- LAST MAN STANDING: al quedar un solo Toonflow en pie la partida se acorta a esta duración (segundos
-- desde ese momento) según el arquetipo del último superviviente: los Centinelas (Trunks, Toby) aguantan
-- más que los de Soporte (Deerphina, Takorita). Solo acorta: nunca alarga lo que ya quedara.
MatchConfig.LMSDuration = {
	Sentinel = 110, -- 1:50
	Survivalist = 90, -- 1:30
	Support = 70, -- 1:10
}
MatchConfig.LMSMinOpenWindow = 50 -- la salida debe quedar abierta al menos esto antes de que acabe la partida
-- (Se eliminó ExitOpenDurationPenalty: nunca se usó. Decisión de diseño: si se agota el tiempo sin
--  reparar las tareas, el Devilish gana al instante; no hay salida de penalización.)

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

-- Salidas activas por tamaño de mapa (QNA): Chico 1, Mediano 2, Grande 3.
-- Un mapa puede tener más Models de salida de los que se activan: se eligen al azar.
MatchConfig.ExitsByCategory = {
	["Pequeño"] = 1,
	["Mediano"] = 2,
	["Grande"] = 3,
}

-- RecommendedKillers: nombres canónicos de CharacterDatabase (p. ej. "Shedmov", "Stan.oma.png");
-- se muestran al Devilish en la votación. Vacío = no se muestra la línea.
MatchConfig.AvailableMaps = {
	{ Name = "GameMap_Example", Category = "Mediano", RecommendedKillers = {} },
	{ Name = "DigitalCircus", Category = "Grande", RecommendedKillers = {} },
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