--!strict
--[[
	AbilityLoadouts (ModuleScript)
	Ubicación: ReplicatedStorage.Shared.AbilityLoadouts

	FUENTE ÚNICA de qué habilidad va en qué slot (1-4 = teclas 1-4) para cada personaje.
	La usan:
	  - AbilityClient  (tecla -> habilidad que se envía al servidor)
	  - HUDController  (icono/cooldown de cada slot)
	  - AbilityOwnership (servidor: qué habilidades puede usar cada personaje)

	Antes AbilityClient y HUDController tenían cada uno su propia copia y estaban
	desincronizados: Miss Circle, Stan.oma.png, Mariposaurio y Deerphina no podían
	usar sus habilidades con el teclado, y Toby tenía RayosLaserToby en la tecla 3
	mientras el HUD la mostraba en el slot 4.

	Los nombres son público (no hay lógica aquí); la lógica real vive en el servidor.
	"" = slot vacío.
]]

local AbilityLoadouts = {}

-- Clave = CharacterDatabase.Name (nombre canónico).
AbilityLoadouts.ByCharacter = {
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
	Shedmov = { "CargaMotosierra", "FueraDeMiCobertizo", "BienvenidaAPonyville" },
} :: { [string]: { string } }

-- Personajes sin entrada propia (p. ej. bots o nuevos aún sin configurar).
local FALLBACK_BY_ROLE: { [string]: { string } } = {
	Devilish = { "", "", "RayosLaser" },
	Toonflow = { "HeredadoDeMama", "Gamechild", "UltimaOpcion" },
}

local EMPTY: { string } = {}

function AbilityLoadouts.get(characterName: string?, role: string?): { string }
	if characterName then
		local loadout = AbilityLoadouts.ByCharacter[characterName]
		if loadout then
			return loadout
		end
	end
	if role then
		local fallback = FALLBACK_BY_ROLE[role]
		if fallback then
			return fallback
		end
	end
	return EMPTY
end

return AbilityLoadouts
