--!strict
-- Minijuego de pesca (servidor = autoridad).
--
-- El servidor es dueño de TODO el estado de la ronda: posición del gancho,
-- criaturas, colisiones, vidas, puntos y Cartonsitos. El cliente solo envía la
-- dirección del gancho (-1/0/1) y dibuja lo que el servidor le cuenta.
-- No se replica nada por frame: cada criatura viaja en línea recta, así que
-- basta enviar (dirección, carril, velocidad, instante de spawn) una vez.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local FishingLogic = require(ReplicatedStorage.Shared.Util.FishingLogic)
local Net = require(script.Parent.Parent.Net)
local Economy = require(script.Parent.Economy)

local C = Config.Fishing

local Fishing = {}

type Round = {
	player: Player,
	roll: () -> number,
	startedAt: number,
	endsAt: number,
	lastTick: number,
	lives: number,
	points: number,
	cartonsitos: number,
	hookY: number,
	hookInput: number,
	stunUntil: number,
	graceUntil: number,
	entities: { [number]: Types.Entity },
	entityCount: number,
	nextEntityId: number,
	nextSpawnAt: number,
	nextStateAt: number,
}

local rounds: { [Player]: Round } = {}
local lastRoundEndedAt: { [Player]: number } = {}

-- Reloj compartido con los clientes.
local function now(): number
	return workspace:GetServerTimeNow()
end

local function makeRoll(): () -> number
	local rng = Random.new()
	return function()
		return rng:NextNumber()
	end
end

local function snapshot(round: Round): Types.RoundSnapshot
	local list: { Types.Entity } = {}
	for _, entity in round.entities do
		table.insert(list, entity)
	end
	return {
		startedAt = round.startedAt,
		endsAt = round.endsAt,
		lives = round.lives,
		points = round.points,
		cartonsitos = round.cartonsitos,
		balance = Economy.get(round.player),
		hookY = round.hookY,
		stunUntil = round.stunUntil,
		entities = list,
	}
end

local function removeEntity(round: Round, id: number)
	if round.entities[id] ~= nil then
		round.entities[id] = nil
		round.entityCount -= 1
	end
end

local function spawnEntity(round: Round, kind: Types.KindDef, t: number, laneOverride: number?)
	local id = round.nextEntityId
	round.nextEntityId += 1
	local entity = FishingLogic.makeEntity(round.roll, id, kind, t, C)
	if laneOverride then
		entity.y = laneOverride
	end
	round.entities[id] = entity
	round.entityCount += 1
	Net.fire(round.player, "Fishing_Spawn", entity)
end

local function resolveHit(round: Round, entity: Types.Entity, kind: Types.KindDef, t: number)
	removeEntity(round, entity.id)

	local newPoints = FishingLogic.applyPoints(round.points, kind.points)
	local pointsDelta = newPoints - round.points
	round.points = newPoints
	round.cartonsitos += kind.cartonsitos
	round.lives = math.max(0, round.lives - kind.livesLost)

	if kind.stun then
		round.stunUntil = t + C.stunSeconds
		round.graceUntil = round.stunUntil + C.graceSeconds
	end

	Net.fire(round.player, "Fishing_Result", {
		entityId = entity.id,
		kind = kind.id,
		pointsDelta = pointsDelta,
		points = round.points,
		cartonsitos = round.cartonsitos,
		lives = round.lives,
		stunUntil = round.stunUntil,
	} :: Types.HookResult)

	if round.lives <= 0 then
		Fishing.endRound(round.player, "NoLives")
	end
end

local function tickRound(round: Round, t: number)
	local dt = math.clamp(t - round.lastTick, 0, 0.25)
	round.lastTick = t

	if t >= round.endsAt then
		Fishing.endRound(round.player, "TimeUp")
		return
	end

	-- Gancho: se mueve con la última dirección recibida, salvo si está paralizado.
	if t >= round.stunUntil then
		round.hookY = FishingLogic.stepHook(round.hookY, round.hookInput, dt, C.hookSpeed, 0, C.fieldDepth)
	end

	-- Aparición aleatoria (la dificultad sube con el progreso de la ronda).
	if t >= round.nextSpawnAt and round.entityCount < C.maxEntities then
		local progress = FishingLogic.progress(round.startedAt, t, C.roundSeconds)
		local kind = FishingLogic.pickKind(round.roll, C.kinds, progress)
		spawnEntity(round, kind, t, nil)
		round.nextSpawnAt = t + FishingLogic.spawnDelay(progress, C)
	end

	-- Caducidad + colisiones.
	for id, entity in round.entities do
		if FishingLogic.isGone(entity, t, C) then
			removeEntity(round, id)
			continue
		end

		local kind = C.kindsById[entity.kind]
		local x = FishingLogic.entityX(entity, t, C)
		if FishingLogic.hits(C.hookX, round.hookY, C.hookRadius, x, entity.y, kind.radius) then
			-- Tras un golpe, el gancho es inmune a basura/peligros un instante.
			if kind.category ~= "Fish" and t < round.graceUntil then
				continue
			end
			resolveHit(round, entity, kind, t)
			if rounds[round.player] ~= round then
				return -- la ronda terminó dentro de resolveHit
			end
		end
	end

	-- Corrección periódica del gancho para el cliente (~10 Hz, no por frame).
	if t >= round.nextStateAt then
		round.nextStateAt = t + 1 / C.snapshotHz
		Net.fire(round.player, "Fishing_HookState", {
			y = round.hookY,
			stunUntil = round.stunUntil,
		} :: Types.HookState)
	end
end

-- API pública (la usan también los comandos de QA) ---------------------------

function Fishing.startRound(player: Player): boolean
	if rounds[player] then
		return false
	end
	local t = now()
	local last = lastRoundEndedAt[player]
	if last and t - last < C.restartCooldown then
		return false
	end

	local round: Round = {
		player = player,
		roll = makeRoll(),
		startedAt = t,
		endsAt = t + C.roundSeconds,
		lastTick = t,
		lives = C.startingLives,
		points = 0,
		cartonsitos = 0,
		hookY = C.fieldDepth * 0.35,
		hookInput = 0,
		stunUntil = 0,
		graceUntil = 0,
		entities = {},
		entityCount = 0,
		nextEntityId = 1,
		nextSpawnAt = t + 0.6,
		nextStateAt = t,
	}
	rounds[player] = round
	Net.fire(player, "Fishing_State", snapshot(round))
	return true
end

function Fishing.endRound(player: Player, reason: Types.EndReason)
	local round = rounds[player]
	if not round then
		return
	end
	rounds[player] = nil -- primero: evita reentradas
	lastRoundEndedAt[player] = now()

	if round.cartonsitos > 0 then
		Economy.addCartonsitos(player, round.cartonsitos)
	end

	Net.fire(player, "Fishing_End", {
		reason = reason,
		points = round.points,
		cartonsitos = round.cartonsitos,
		balance = Economy.get(player),
	} :: Types.RoundEnd)
end

-- QA: hace aparecer una criatura en el carril actual del gancho.
function Fishing.spawnForQA(player: Player, kindId: string): boolean
	local round = rounds[player]
	local kind = C.kindsById[kindId]
	if not round or not kind then
		return false
	end
	spawnEntity(round, kind, now(), round.hookY)
	return true
end

-- Ciclo de vida ---------------------------------------------------------------

function Fishing.init()
	-- Todos los handlers: rate limit (en Net) → tipo → rango → estado.
	Net.on("Fishing_Start", 1, 2, function(player: Player)
		local round = rounds[player]
		if round then
			Net.fire(player, "Fishing_State", snapshot(round)) -- re-sincronizar
			return
		end
		Fishing.startRound(player)
	end)

	Net.on("Fishing_Input", 15, 30, function(player: Player, input: unknown)
		if typeof(input) ~= "number" then
			return
		end
		-- Solo -1, 0 o 1. Esto también descarta NaN, infinitos y fracciones.
		if input ~= -1 and input ~= 0 and input ~= 1 then
			return
		end
		local round = rounds[player]
		if not round then
			return
		end
		round.hookInput = input
	end)

	Net.on("Fishing_Quit", 1, 2, function(player: Player)
		Fishing.endRound(player, "Quit")
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		Fishing.endRound(player, "Left")
		lastRoundEndedAt[player] = nil
	end)
end

function Fishing.start()
	-- Una sola conexión para todo el sistema (vive tanto como el servidor).
	local step = 1 / C.tickRate
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < step then
			return
		end
		acc = 0
		local t = now()
		for _, round in rounds do
			tickRound(round, t)
		end
	end)
end

return Fishing
