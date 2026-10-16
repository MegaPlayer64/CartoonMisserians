--!strict
-- Todos los números de balance del minijuego en un solo sitio.
-- Ojo: esta copia es legible por el cliente; las comprobaciones autoritativas
-- siempre se hacen en el servidor.

local Types = require(script.Parent.Types)

local kinds: { Types.KindDef } = {
	-- PECES (recompensa) ---------------------------------------------------
	{
		id = "Sardina", name = "Sardina", category = "Fish", icon = "🐟", image = "",
		radius = 0.45, speedMin = 2.5, speedMax = 4.0, weight = 40,
		points = 100, cartonsitos = 1, livesLost = 0, stun = false,
	},
	{
		id = "PezDorado", name = "Pez dorado", category = "Fish", icon = "🐠", image = "",
		radius = 0.40, speedMin = 4.5, speedMax = 6.5, weight = 14,
		points = 300, cartonsitos = 3, livesLost = 0, stun = false,
	},
	{
		id = "Calamar", name = "Calamar", category = "Fish", icon = "🦑", image = "",
		radius = 0.55, speedMin = 3.0, speedMax = 4.5, weight = 12,
		points = 200, cartonsitos = 2, livesLost = 0, stun = false,
	},
	{
		id = "Cofre", name = "Cofre pirata", category = "Fish", icon = "💰", image = "",
		radius = 0.50, speedMin = 5.0, speedMax = 7.0, weight = 4,
		points = 800, cartonsitos = 10, livesLost = 0, stun = false,
	},
	-- BASURA (quita puntos, paraliza el gancho) -------------------------------
	{
		id = "Bota", name = "Bota vieja", category = "Trash", icon = "🥾", image = "",
		radius = 0.50, speedMin = 2.0, speedMax = 3.0, weight = 14,
		points = -150, cartonsitos = 0, livesLost = 0, stun = true,
	},
	{
		id = "Lata", name = "Lata", category = "Trash", icon = "🥫", image = "",
		radius = 0.45, speedMin = 2.0, speedMax = 3.5, weight = 12,
		points = -100, cartonsitos = 0, livesLost = 0, stun = true,
	},
	-- PELIGROSOS (quitan una vida y paralizan el gancho) ----------------------
	{
		id = "PezGlobo", name = "Pez globo", category = "Danger", icon = "🐡", image = "",
		radius = 0.60, speedMin = 2.0, speedMax = 3.0, weight = 10,
		points = -200, cartonsitos = 0, livesLost = 1, stun = true,
	},
	{
		id = "Tiburon", name = "Tiburón", category = "Danger", icon = "🦈", image = "",
		radius = 0.80, speedMin = 5.5, speedMax = 8.0, weight = 8,
		points = -300, cartonsitos = 0, livesLost = 1, stun = true,
	},
}

local kindsById: { [string]: Types.KindDef } = {}
for _, kind in kinds do
	kindsById[kind.id] = kind
end

local Fishing: Types.FishingConfig = {
	roundSeconds = 60,
	startingLives = 3,

	fieldWidth = 16,
	fieldDepth = 9,
	hookX = 6.6,
	hookSpeed = 6,
	hookRadius = 0.35,
	stunSeconds = 1.2,
	graceSeconds = 0.8,

	tickRate = 30,
	snapshotHz = 10,

	spawnDelayStart = 1.1,
	spawnDelayMin = 0.45,
	maxEntities = 14,
	laneMargin = 0.6,
	-- Las criaturas nacen fuera del campo; el margen absorbe la latencia del
	-- evento de spawn (a 8 u/s, 2.5 u cubren ~300 ms) para que no "aparezcan".
	offscreenMargin = 2.5,
	restartCooldown = 2,

	kinds = kinds,
	kindsById = kindsById,
}

return {
	Fishing = Fishing,
}
