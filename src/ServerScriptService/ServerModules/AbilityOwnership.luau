--!strict
--[[
	AbilityOwnership (ModuleScript)
	Ubicación: ServerScriptService.ServerModules.AbilityOwnership

	Fuente de verdad (solo servidor) de QUÉ habilidades puede usar cada personaje.
	AbilityServer la consulta antes de ejecutar: sin esto, cualquier jugador
	podía disparar por el remote cualquier habilidad del Registry (incluidas las
	del rol contrario).

	AL AÑADIR una habilidad o personaje nuevo, agrégalo aquí; si no, el servidor
	la rechazará en silencio.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterDatabase = require(ReplicatedStorage.Framework.CharacterDatabase)

-- Clave = CharacterDatabase.Name (nombre canónico).
local ABILITIES_BY_CHARACTER: { [string]: { string } } = {
	-- Toonflows
	Brothercat = { "HeredadoDeMama", "Gamechild", "UltimaOpcion" },
	TobyWilliams = { "YaLevantate", "BaraNormal", "BaraFantasma", "RayosLaserToby" },
	Takorita = { "EmergenciaSevera", "AnnouncerAttack", "CuracionAumentante" },
	Deerphina = { "Koshintantan", "ChistesDeCiervos", "GalletasParaCiervos", "RegaloDeAmigos" },
	Trunks = { "ZSword", "KiBlasts", "SuperSaiyan" },
	-- Devilishes
	MissCircle = { "LinearThrust", "PunishmentRadius", "FailingGrade", "DetentionTime" },
	["Stan.oma.png"] = { "RayoCorrupto", "BetterCallStan", "CorrupcionGrave", "CambioArma" },
	Mariposaurio = { "HereComes", "AThought", "Boo", "DeadHope" },
	Neuro = { "CallOfStardoom", "LightsAndAction", "LastShow" },
}

-- Plantillas de AbilityTemplates sin dueño concreto: cualquier Devilish.
local GENERIC_DEVILISH_ABILITIES: { [string]: boolean } = {
	RayosLaser = true,
}

local allowed: { [string]: { [string]: boolean } } = {}
for characterName, abilityNames in ABILITIES_BY_CHARACTER do
	local set: { [string]: boolean } = {}
	for _, abilityName in abilityNames do
		set[abilityName] = true
	end
	allowed[characterName] = set
end

local AbilityOwnership = {}

-- characterName puede venir como Name o DisplayName (la selección acepta ambos).
function AbilityOwnership.canUse(characterName: unknown, abilityName: string): boolean
	if typeof(characterName) ~= "string" then
		return false
	end

	local data = CharacterDatabase.GetCharacterData(characterName)
	if not data then
		return false
	end

	local set = allowed[data.Name]
	if set and set[abilityName] then
		return true
	end

	if GENERIC_DEVILISH_ABILITIES[abilityName] and CharacterDatabase.GetDevilish(data.Name) then
		return true
	end

	return false
end

return AbilityOwnership
