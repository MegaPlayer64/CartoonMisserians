--!strict
-- Tipos compartidos del minijuego de pesca.
-- Los tipos NO validan nada en red: el servidor valida cada argumento de remote.

export type KindId = "Sardina" | "PezDorado" | "Calamar" | "Cofre" | "Bota" | "Lata" | "PezGlobo" | "Tiburon"
export type Category = "Fish" | "Trash" | "Danger"
export type EndReason = "TimeUp" | "NoLives" | "Quit" | "Left"

-- Definición de un tipo de criatura/objeto que cruza el agua.
export type KindDef = {
	id: KindId,
	name: string,
	category: Category,
	icon: string, -- placeholder (emoji); cámbialo por un ImageLabel con tus dibujos
	image: string, -- asset ID del sprite pixel-art (ej: "rbxassetid://123456789")
	radius: number, -- radio de colisión en unidades de campo
	speedMin: number, -- unidades/segundo
	speedMax: number,
	weight: number, -- peso de aparición
	points: number, -- puede ser negativo (basura / peligro)
	cartonsitos: number, -- recompensa si se atrapa
	livesLost: number,
	stun: boolean, -- el gancho se queda paralizado un momento
}

export type FishingConfig = {
	roundSeconds: number,
	startingLives: number,
	fieldWidth: number, -- unidades
	fieldDepth: number, -- profundidad del agua en unidades (y=0 es la superficie)
	hookX: number,
	hookSpeed: number,
	hookRadius: number,
	stunSeconds: number,
	graceSeconds: number, -- invulnerabilidad a basura/peligros tras un golpe
	tickRate: number,
	snapshotHz: number,
	spawnDelayStart: number,
	spawnDelayMin: number,
	maxEntities: number,
	laneMargin: number,
	offscreenMargin: number,
	restartCooldown: number,
	kinds: { KindDef },
	kindsById: { [string]: KindDef },
}

-- Una criatura en movimiento. Su posición X no se replica por frame:
-- x(t) = inicio + dir * speed * (t - spawnTime)  (ver FishingLogic.entityX)
export type Entity = {
	id: number,
	kind: KindId,
	dir: number, -- 1 = izquierda→derecha, -1 = derecha→izquierda
	y: number,
	speed: number,
	spawnTime: number, -- workspace:GetServerTimeNow()
}

-- Server → Client
export type RoundSnapshot = {
	startedAt: number,
	endsAt: number,
	lives: number,
	points: number,
	cartonsitos: number, -- ganados en esta ronda
	balance: number, -- saldo de Cartonsitos antes de la ronda
	hookY: number,
	stunUntil: number,
	entities: { Entity },
}

export type HookState = {
	y: number,
	stunUntil: number,
}

export type HookResult = {
	entityId: number,
	kind: KindId,
	pointsDelta: number,
	points: number, -- total de la ronda
	cartonsitos: number, -- total de la ronda
	lives: number,
	stunUntil: number,
}

export type RoundEnd = {
	reason: EndReason,
	points: number,
	cartonsitos: number, -- ganados en la ronda
	balance: number, -- saldo final
}

return {}
