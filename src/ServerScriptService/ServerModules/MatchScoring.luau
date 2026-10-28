--[[
	MatchScoring (ModuleScript)
	Ubicación: ServerScriptService.ServerModules.MatchScoring

	Calificación de fin de partida (SUPER F ... SS+) y Maldad que otorga.

	!!! PROPUESTA: los pesos, los umbrales y la Maldad por nota son valores PROVISIONALES elegidos para
	    poder probar el sistema. `Enabled = false` hasta que la dirección apruebe la tabla: mientras esté
	    apagado MatchManager no calcula, no reparte Maldad ni muestra nada.

	Métricas (de la lista de la dirección) y su estado:
	  stuns, healed, abilitiesUsed (solo Survivalist), tasksCompleted, bonus por escapar y por caer ... recogidas
	  downs/kills del Killer ......................................... recogidas (acreditadas al Devilish)
	  chaseEscapes, chaseSaves ........................................ PENDIENTE (hace falta un detector de
	                                                                    persecuciones); cuentan 0 hasta entonces
]]

local MatchScoring = {}

MatchScoring.Enabled = false

-- Puntos por unidad de cada métrica
MatchScoring.Weights = {
	Toonflow = {
		tasksCompleted = 5, -- tareas purificadas
		stuns = 8, -- stuns dados al Devilish
		healed = 10, -- supervivientes distintos curados
		chaseEscapes = 15, -- persecuciones de las que escapó
		chaseSaves = 20, -- supervivientes salvados de una persecución
		abilitiesUsed = 2, -- SOLO para el arquetipo Survivalist
	},
	Killer = {
		downs = 15,
		kills = 30,
		abilitiesUsed = 4,
	},
	Bonus = {
		escaped = 40, -- "puntos extras si escapas"
		died = 15, -- "puntos extras si mueres" (consuelo: caer no debe castigar de más)
		teamWin = 20, -- victoria de los Toonflows (para los Toonflows)
		killerWin = 30, -- victoria del Devilish (para el Killer)
	},
}

-- De mayor a menor: la primera nota cuyo mínimo se alcanza
MatchScoring.Grades = {
	{ Grade = "SS+", MinPoints = 250 },
	{ Grade = "SS", MinPoints = 190 },
	{ Grade = "S", MinPoints = 140 },
	{ Grade = "A", MinPoints = 100 },
	{ Grade = "B", MinPoints = 70 },
	{ Grade = "C", MinPoints = 45 },
	{ Grade = "D", MinPoints = 25 },
	{ Grade = "F", MinPoints = 10 },
	{ Grade = "SUPER F", MinPoints = 0 },
}

MatchScoring.MaldadByGrade = {
	["SS+"] = 50,
	["SS"] = 40,
	["S"] = 30,
	["A"] = 22,
	["B"] = 15,
	["C"] = 10,
	["D"] = 6,
	["F"] = 3,
	["SUPER F"] = 1,
}

-- role: "Toonflow" | "Killer";  archetype: "Sentinel" | "Survivalist" | "Support" (solo Toonflows)
-- counters: lo que devuelve MatchStats.get (+ downs/kills para el Killer)
-- flags: { escaped: boolean, died: boolean, won: boolean }
-- Devuelve { points, grade, maldad, breakdown = { { label, points } ... } }
function MatchScoring.compute(role, archetype, counters, flags)
	local points = 0
	local breakdown = {}

	local function add(label, amount)
		amount = math.floor(amount)
		if amount ~= 0 then
			points += amount
			table.insert(breakdown, { label = label, points = amount })
		end
	end

	local weights = MatchScoring.Weights
	if role == "Toonflow" then
		local w = weights.Toonflow
		add("Tareas purificadas", (counters.tasksCompleted or 0) * w.tasksCompleted)
		add("Stuns al Devilish", (counters.stuns or 0) * w.stuns)
		add("Aliados curados", (counters.healed or 0) * w.healed)
		add("Escapes de persecución", (counters.chaseEscapes or 0) * w.chaseEscapes)
		add("Rescates de persecución", (counters.chaseSaves or 0) * w.chaseSaves)
		if archetype == "Survivalist" then
			add("Habilidades usadas", (counters.abilitiesUsed or 0) * w.abilitiesUsed)
		end
		if flags.escaped then add("Escapaste", weights.Bonus.escaped) end
		if flags.died then add("Caíste en combate", weights.Bonus.died) end
		if flags.won then add("Victoria del equipo", weights.Bonus.teamWin) end
	else
		local w = weights.Killer
		add("Derribos", (counters.downs or 0) * w.downs)
		add("Eliminaciones", (counters.kills or 0) * w.kills)
		add("Habilidades usadas", (counters.abilitiesUsed or 0) * w.abilitiesUsed)
		if flags.won then add("Victoria", weights.Bonus.killerWin) end
	end

	points = math.max(0, points)

	local grade = MatchScoring.Grades[#MatchScoring.Grades].Grade
	for _, tier in ipairs(MatchScoring.Grades) do
		if points >= tier.MinPoints then
			grade = tier.Grade
			break
		end
	end

	return {
		points = points,
		grade = grade,
		maldad = MatchScoring.MaldadByGrade[grade] or 0,
		breakdown = breakdown,
	}
end

return MatchScoring
