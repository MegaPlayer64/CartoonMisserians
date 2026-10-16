--!strict
-- Lógica pura del minijuego: números dentro, números fuera.
-- Sin servicios de Roblox y con el azar inyectado (`rng: () -> number` en [0, 1)).
-- El servidor es autoritativo; el cliente usa las mismas funciones solo para
-- dibujar/predecir.

local Types = require(script.Parent.Parent.Types)

local FishingLogic = {}

-- 0 al empezar, 1 al terminar la ronda.
function FishingLogic.progress(startedAt: number, now: number, roundSeconds: number): number
	return math.clamp((now - startedAt) / roundSeconds, 0, 1)
end

-- Los peligrosos pesan más conforme avanza la ronda (hasta x2).
function FishingLogic.effectiveWeight(kind: Types.KindDef, progress: number): number
	if kind.category == "Danger" then
		return kind.weight * (1 + progress)
	end
	return kind.weight
end

function FishingLogic.pickKind(rng: () -> number, kinds: { Types.KindDef }, progress: number): Types.KindDef
	assert(#kinds > 0, "pickKind needs at least one kind")
	local total = 0
	for _, kind in kinds do
		total += FishingLogic.effectiveWeight(kind, progress)
	end
	local roll = rng() * total
	for _, kind in kinds do
		roll -= FishingLogic.effectiveWeight(kind, progress)
		if roll < 0 then
			return kind
		end
	end
	return kinds[#kinds]
end

-- Orden de llamadas a rng: dirección, carril, velocidad (los tests dependen de esto).
function FishingLogic.makeEntity(
	rng: () -> number,
	id: number,
	kind: Types.KindDef,
	now: number,
	cfg: Types.FishingConfig
): Types.Entity
	local dir = if rng() < 0.5 then 1 else -1
	local lane = cfg.laneMargin + rng() * (cfg.fieldDepth - 2 * cfg.laneMargin)
	local speed = kind.speedMin + rng() * (kind.speedMax - kind.speedMin)
	return {
		id = id,
		kind = kind.id,
		dir = dir,
		y = lane,
		speed = speed,
		spawnTime = now,
	}
end

-- Segundos hasta el siguiente spawn: baja linealmente con el progreso.
function FishingLogic.spawnDelay(progress: number, cfg: Types.FishingConfig): number
	return cfg.spawnDelayStart + (cfg.spawnDelayMin - cfg.spawnDelayStart) * progress
end

function FishingLogic.entityX(entity: Types.Entity, t: number, cfg: Types.FishingConfig): number
	local startX = if entity.dir == 1 then -cfg.offscreenMargin else cfg.fieldWidth + cfg.offscreenMargin
	return startX + entity.dir * entity.speed * (t - entity.spawnTime)
end

function FishingLogic.isGone(entity: Types.Entity, t: number, cfg: Types.FishingConfig): boolean
	local x = FishingLogic.entityX(entity, t, cfg)
	if entity.dir == 1 then
		return x > cfg.fieldWidth + cfg.offscreenMargin
	end
	return x < -cfg.offscreenMargin
end

-- input: -1 sube (y disminuye hacia la superficie), 0 quieto, 1 baja.
function FishingLogic.stepHook(y: number, input: number, dt: number, speed: number, minY: number, maxY: number): number
	return math.clamp(y + input * speed * dt, minY, maxY)
end

-- Colisión círculo-círculo (borde incluido).
function FishingLogic.hits(ax: number, ay: number, ar: number, bx: number, by: number, br: number): boolean
	local dx = ax - bx
	local dy = ay - by
	local r = ar + br
	return dx * dx + dy * dy <= r * r
end

-- La puntuación de la ronda nunca baja de 0.
function FishingLogic.applyPoints(current: number, delta: number): number
	return math.max(0, current + delta)
end

return FishingLogic
