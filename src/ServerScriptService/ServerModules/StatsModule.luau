--[[
	StatsModule (ModuleScript)
	Ubicacion: ServerScriptService.ServerModules.StatsModule
	
	Gestiona las estadisticas, estados, dano, curacion, remates (Downed/Bleedout)
	y sistemas especiales (Fame de Neuro y SCells de Trunks).
]]

local MatchStats = require(script.Parent.MatchStats)
local Players = game:GetService("Players")

local StatsModule = {}

-- Velocidad "de base" que dan ciertas condiciones mientras duran.
local SSJ_SPEED_MULTIPLIER = 1.35
local FAME_SPEED_MULTIPLIER = 1.25
local FAME_SPEED_THRESHOLD = 45

-- Fuentes de velocidad con nombre (ver ApplySpeedMultiplier): [personaje] = { [nombre] = { multiplier, token } }.
-- Se combinan multiplicando y caducan solas; claves débiles, no retienen personajes destruidos.
local speedSources = setmetatable({}, { __mode = "k" })

-- == ENUMERACION DE ESTADOS DE PERSONAJE ==
StatsModule.CharacterState = {
	Normal = "Normal",
	Stunned = "Stunned",
	Ragdoll = "Ragdoll",
	Downed = "Downed",
	Dead = "Dead",
}

-- == ENUMERACION DE ROLES ==
StatsModule.Role = {
	Toonflow = "Toonflow",
	Devilish = "Devilish",
}

function StatsModule.InitializeStats(character, role, config)
	speedSources[character] = nil
	local existing = character:FindFirstChild("Stats")
	if existing then
		existing:Destroy()
	end

	local statsFolder = Instance.new("Folder")
	statsFolder.Name = "Stats"
	statsFolder.Parent = character

	local function createValue(name, valueType, value)
		local vo = Instance.new(valueType)
		vo.Name = name
		vo.Value = value
		vo.Parent = statsFolder
		return vo
	end

	-- ATRIBUTOS COMUNES
	createValue("Role", "StringValue", role)
	createValue("MaxHealth", "IntValue", config.MaxHealth or 100)
	createValue("Health", "IntValue", config.MaxHealth or 100)
	createValue("WalkSpeed", "IntValue", config.WalkSpeed or 16)
	createValue("SpeedMultiplier", "NumberValue", 1.0)
	createValue("State", "StringValue", StatsModule.CharacterState.Normal)
	createValue("IsAlive", "BoolValue", true)

	-- ATRIBUTOS ESPECIFICOS DE TOONFLOWS
	if role == StatsModule.Role.Toonflow then
		createValue("RunSpeed", "IntValue", config.RunSpeed or 24)
		createValue("DownedHealth", "IntValue", config.DownedHealth or 50)
		createValue("BleedOutTime", "IntValue", config.BleedOutTime or 30)
		createValue("IsDowned", "BoolValue", false)
		createValue("ReviveProgress", "NumberValue", 0)
	end

	-- ATRIBUTOS ESPECIFICOS DE DEVILISH
	if role == StatsModule.Role.Devilish then
		createValue("Absorption", "NumberValue", 0)
		createValue("AbsorptionMax", "IntValue", config.AbsorptionMax or 100)
		createValue("AttackRange", "IntValue", config.AttackRange or 8)
		createValue("AttackCooldown", "NumberValue", config.AttackCooldown or 1.0)
		createValue("AttackDamage", "IntValue", config.AttackDamage or 35)
		createValue("LastAttackTime", "NumberValue", 0)

		-- FAME SYSTEM (Neuro pasiva)
		local charName = character:GetAttribute("CharacterName")
		if charName == "Neuro" then
			character:SetAttribute("Fame", 0)
		end

	end

	-- SCELLS SYSTEM (Trunks pasiva). Trunks es Toonflow: este bloque antes vivía
	-- dentro del "if Devilish" y nunca se ejecutaba (las habilidades lo creaban a demanda).
	if character:GetAttribute("CharacterName") == "Trunks" then
		createValue("SCells", "NumberValue", 0)
		createValue("SCellsMax", "IntValue", 20)
		createValue("IsSuperSaiyan", "BoolValue", false)
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = config.MaxHealth or 100
		humanoid.Health = config.MaxHealth or 100
		humanoid.WalkSpeed = config.WalkSpeed or 16
	end

	return statsFolder
end

function StatsModule.GetStats(character)
	if not character then return nil end
	return character:FindFirstChild("Stats")
end

function StatsModule.GetStat(character, statName)
	local stats = StatsModule.GetStats(character)
	if not stats then return nil end
	return stats:FindFirstChild(statName)
end

local function applyDamageInternal(character, damage, ignoreDowned)
	local stats = StatsModule.GetStats(character)
	if not stats then return false end

	-- Un Toonflow que ya escapó por la salida es invulnerable (ver MatchManager).
	if character:GetAttribute("Escaped") then return false end

	local state = stats:FindFirstChild("State")
	local health = stats:FindFirstChild("Health")
	local isAlive = stats:FindFirstChild("IsAlive")

	if not (state and health and isAlive) or not isAlive.Value then return false end

	-- SI YA ESTÁ DERRIBADO -> RECIBIR OTRA ACOMETIDA LO REMATA DE INMEDIATO
	if state.Value == StatsModule.CharacterState.Downed then
		StatsModule.SetState(character, StatsModule.CharacterState.Dead)
		print("[StatsModule] " .. character.Name .. " ha sido REMATADO estando derribado.")
		return true, "Executed"
	end

	-- DAÑO NORMAL
	health.Value = math.max(0, health.Value - damage)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = health.Value
	end

	-- SI LA SALUD LLEGA A 0
	if health.Value <= 0 then
		local role = stats:FindFirstChild("Role")
		if role and role.Value == StatsModule.Role.Toonflow then
			local isDowned = stats:FindFirstChild("IsDowned")
			if isDowned and not isDowned.Value then
				-- TRANSICION A ESTADO DERRIBADO (DOWNED)
				isDowned.Value = true
				character:SetAttribute("IsDowned", true)
				state.Value = StatsModule.CharacterState.Downed

				local downedHealth = stats:FindFirstChild("DownedHealth")
				local bleedOutTime = stats:FindFirstChild("BleedOutTime")
				local defaultBleed = bleedOutTime and bleedOutTime.Value or 30

				if downedHealth then
					health.Value = downedHealth.Value
					if humanoid then humanoid.Health = downedHealth.Value end
				end

				-- TEMPORIZADOR AUTOMÁTICO DE SANGRADO (BLEEDOUT)
				-- Token: si lo reaniman y lo derriban otra vez, el temporizador anterior
				-- queda invalidado (antes lo mataba antes de tiempo).
				local bleedId = (character:GetAttribute("BleedId") or 0) + 1
				character:SetAttribute("BleedId", bleedId)
				task.delay(defaultBleed, function()
					if character and character.Parent and character:GetAttribute("BleedId") == bleedId then
						local currentStats = StatsModule.GetStats(character)
						local currentState = currentStats and currentStats:FindFirstChild("State")
						if currentState and currentState.Value == StatsModule.CharacterState.Downed then
							StatsModule.SetState(character, StatsModule.CharacterState.Dead)
							print("[StatsModule] " .. character.Name .. " murio por sangrado (Bleedout).")
						end
					end
				end)

				return true, "Downed"
			else
				StatsModule.SetState(character, StatsModule.CharacterState.Dead)
				return true, "Dead"
			end
		else
			StatsModule.SetState(character, StatsModule.CharacterState.Dead)
			return true, "Dead"
		end
	end

	return true, "Damaged"
end

function StatsModule.ApplyDamage(character, damage, ignoreDowned)
	local applied, outcome = applyDamageInternal(character, damage, ignoreDowned)
	-- Estadísticas de partida: derribar a un Toonflow se acredita al Devilish
	if applied and outcome == "Downed" then
		MatchStats.addDevilishEvent("downs")
	end
	return applied, outcome
end

function StatsModule.ApplyHeal(character, healAmount, source)
	local stats = StatsModule.GetStats(character)
	if not stats then return false end

	local health = stats:FindFirstChild("Health")
	local maxHealth = stats:FindFirstChild("MaxHealth")
	local isAlive = stats:FindFirstChild("IsAlive")

	if not (health and maxHealth and isAlive) or not isAlive.Value then return false end

	-- Estadísticas de partida: a cuántos supervivientes DISTINTOS ha curado `source` (opcional, no cuenta a sí mismo)
	if source then
		local healedPlayer = Players:GetPlayerFromCharacter(character)
		if healedPlayer and healedPlayer ~= source and health.Value < maxHealth.Value then
			MatchStats.addUnique(source, "healed", healedPlayer.UserId)
		end
	end

	health.Value = math.min(maxHealth.Value, health.Value + healAmount)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = health.Value
	end

	return true
end

function StatsModule.SetSpeedMultiplier(character, multiplier)
	local stats = StatsModule.GetStats(character)
	if not stats then return false end

	-- Inmunidad a ralentizaciones: se ignora cualquier multiplicador < 1
	if multiplier < 1 and character:GetAttribute("SlowImmune") then return false end

	local speedMult = stats:FindFirstChild("SpeedMultiplier")
	local walkSpeed = stats:FindFirstChild("WalkSpeed")
	if not (speedMult and walkSpeed) then return false end

	speedMult.Value = multiplier

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = walkSpeed.Value * multiplier
	end

	return true
end

-- Multiplicador que corresponde ahora mismo SIN efectos temporales:
-- aturdido = 0, Super Saiyan = 1.35, Fame alta (Neuro) = 1.25, resto = 1.
local function baselineSpeedMultiplier(character, stats)
	local state = stats:FindFirstChild("State")
	if state and state.Value == StatsModule.CharacterState.Stunned then
		return 0
	end

	local multiplier = 1.0
	local ssj = stats:FindFirstChild("IsSuperSaiyan")
	if ssj and ssj.Value then
		multiplier = SSJ_SPEED_MULTIPLIER
	elseif (character:GetAttribute("Fame") or 0) >= FAME_SPEED_THRESHOLD then
		multiplier = FAME_SPEED_MULTIPLIER
	end

	-- Fuentes con nombre (bonos de Shed.mov, ralentizaciones de habilidades...). Con SlowImmune
	-- las que ralentizan (< 1) se ignoran.
	local sources = speedSources[character]
	if sources then
		local slowImmune = character:GetAttribute("SlowImmune")
		for _, source in pairs(sources) do
			if not (slowImmune and source.multiplier < 1) then
				multiplier *= source.multiplier
			end
		end
	end

	return multiplier
end

-- Antes forzaba 1.0: terminar de interactuar con una tarea, o expirar una
-- ralentización, anulaba un aturdimiento activo y los buffs de Trunks/Neuro.
function StatsModule.ResetSpeedMultiplier(character)
	local stats = StatsModule.GetStats(character)
	if not stats then return false end

	local speedMult = stats:FindFirstChild("SpeedMultiplier")
	local walkSpeed = stats:FindFirstChild("WalkSpeed")
	if not (speedMult and walkSpeed) then return false end

	local multiplier = baselineSpeedMultiplier(character, stats)
	speedMult.Value = multiplier

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = walkSpeed.Value * multiplier
	end

	return true
end

function StatsModule.RestoreHealth(character)
	local stats = StatsModule.GetStats(character)
	if not stats then return false end

	local health = stats:FindFirstChild("Health")
	local maxHealth = stats:FindFirstChild("MaxHealth")
	if not (health and maxHealth) then return false end

	health.Value = maxHealth.Value

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = maxHealth.Value
	end

	return true
end

function StatsModule.IncreaseMaxHealthPercent(character, percent)
	local stats = StatsModule.GetStats(character)
	if not stats then return false end

	local maxHealth = stats:FindFirstChild("MaxHealth")
	if not maxHealth then return false end

	local newMax = math.floor(maxHealth.Value * (1 + percent))
	maxHealth.Value = newMax

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = newMax
		humanoid.Health = newMax
	end

	return true
end

function StatsModule.SetState(character, newState)
	local stats = StatsModule.GetStats(character)
	if not stats then return false end

	local state = stats:FindFirstChild("State")
	local isAlive = stats:FindFirstChild("IsAlive")
	local isDowned = stats:FindFirstChild("IsDowned")
	if not state then return false end

	-- Inmunidad total a aturdimientos (p. ej. Shed.mov en su ultimate)
	if newState == StatsModule.CharacterState.Stunned and character:GetAttribute("StunImmune") then
		return false
	end

	state.Value = newState

	if newState == StatsModule.CharacterState.Dead then
		if isAlive then isAlive.Value = false end
		if isDowned then isDowned.Value = false end
		character:SetAttribute("IsDowned", false)

		-- Estadísticas de partida: la baja de un Toonflow se acredita UNA vez al Devilish
		local roleValue = stats:FindFirstChild("Role")
		if roleValue and roleValue.Value == StatsModule.Role.Toonflow and not character:GetAttribute("DeathRecorded") then
			character:SetAttribute("DeathRecorded", true)
			MatchStats.addDevilishEvent("kills")
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = 0
		end
	elseif newState == StatsModule.CharacterState.Stunned then
		StatsModule.SetSpeedMultiplier(character, 0.0)
	elseif newState == StatsModule.CharacterState.Normal then
		StatsModule.ResetSpeedMultiplier(character)
		if isDowned then isDowned.Value = false end
		character:SetAttribute("IsDowned", false)
	end

	return true
end

-- Aturde a un personaje durante `duration` segundos.
-- Las habilidades aplicaban el aturdimiento escribiendo Humanoid.WalkSpeed = 0 y restaurando
-- "la velocidad de antes". Si dos aturdimientos se solapaban, el segundo guardaba 0 como velocidad
-- original y el personaje se quedaba INMÓVIL PARA SIEMPRE. Aquí el estado Stunned manda (el
-- multiplicador base lo respeta) y solo el aturdimiento más reciente lo levanta (token StunId).
-- No pisa Derribado/Muerto ni afecta a quien ya escapó. Devuelve true si aplicó el aturdimiento.
function StatsModule.Stun(character, duration, source)
	local stats = StatsModule.GetStats(character)
	if not stats or character:GetAttribute("Escaped") then return false end
	if character:GetAttribute("StunImmune") then return false end
	if typeof(duration) ~= "number" or duration ~= duration or duration <= 0 then return false end

	local state = stats:FindFirstChild("State")
	local isAlive = stats:FindFirstChild("IsAlive")
	if not (state and isAlive) or not isAlive.Value then return false end
	if state.Value == StatsModule.CharacterState.Downed or state.Value == StatsModule.CharacterState.Dead then
		return false
	end

	-- Estadísticas de partida: stun dado al Devilish por un jugador (`source`, opcional)
	local targetRole = stats:FindFirstChild("Role")
	if source and targetRole and targetRole.Value == StatsModule.Role.Devilish then
		MatchStats.add(source, "stuns", 1)
	end

	local stunId = (character:GetAttribute("StunId") or 0) + 1
	character:SetAttribute("StunId", stunId)
	StatsModule.SetState(character, StatsModule.CharacterState.Stunned)

	task.delay(duration, function()
		if not character.Parent or character:GetAttribute("StunId") ~= stunId then return end
		local currentStats = StatsModule.GetStats(character)
		local currentState = currentStats and currentStats:FindFirstChild("State")
		if currentState and currentState.Value == StatsModule.CharacterState.Stunned then
			StatsModule.SetState(character, StatsModule.CharacterState.Normal)
		end
	end)

	return true
end

-- Aplica un multiplicador de velocidad con NOMBRE (bonos y ralentizaciones que se combinan entre
-- sí). `duration` opcional: sin ella dura hasta RemoveSpeedMultiplier. Volver a aplicar el mismo
-- nombre lo refresca (y el temporizador anterior ya no lo quita: token). Con SlowImmune las
-- ralentizaciones (< 1) se rechazan. Un aturdimiento activo sigue mandando (velocidad 0).
function StatsModule.ApplySpeedMultiplier(character, sourceName, multiplier, duration)
	if typeof(multiplier) ~= "number" or multiplier ~= multiplier or multiplier < 0 then return false end
	if not StatsModule.GetStats(character) then return false end
	if multiplier < 1 and character:GetAttribute("SlowImmune") then return false end

	local sources = speedSources[character]
	if not sources then
		sources = {}
		speedSources[character] = sources
	end

	local token = (sources[sourceName] and sources[sourceName].token or 0) + 1
	sources[sourceName] = { multiplier = multiplier, token = token }
	StatsModule.ResetSpeedMultiplier(character)

	if typeof(duration) == "number" and duration > 0 then
		task.delay(duration, function()
			local current = sources[sourceName]
			if current and current.token == token then
				sources[sourceName] = nil
				if character.Parent then
					StatsModule.ResetSpeedMultiplier(character)
				end
			end
		end)
	end

	return true
end

function StatsModule.RemoveSpeedMultiplier(character, sourceName)
	local sources = speedSources[character]
	if sources and sources[sourceName] then
		sources[sourceName] = nil
		StatsModule.ResetSpeedMultiplier(character)
		return true
	end
	return false
end

-- Quita todas las ralentizaciones activas (fuentes con multiplicador < 1)
function StatsModule.ClearSlows(character)
	local sources = speedSources[character]
	if not sources then return end
	for name, source in pairs(sources) do
		if source.multiplier < 1 then
			sources[name] = nil
		end
	end
	StatsModule.ResetSpeedMultiplier(character)
end

function StatsModule.AddAbsorption(character, amount)
	local stats = StatsModule.GetStats(character)
	if not stats then return false end

	local absorption = stats:FindFirstChild("Absorption")
	local absorptionMax = stats:FindFirstChild("AbsorptionMax")
	if not (absorption and absorptionMax) then return false end

	absorption.Value = math.clamp(absorption.Value + amount, 0, absorptionMax.Value)
	return true
end

function StatsModule.ConsumeAbsorption(character, amount)
	local stats = StatsModule.GetStats(character)
	if not stats then return false end

	local absorption = stats:FindFirstChild("Absorption")
	if not absorption or absorption.Value < amount then return false end

	absorption.Value = absorption.Value - amount
	return true
end

-- == FAME SYSTEM HELPERS (Neuro pasiva) ==

function StatsModule.GetFame(character)
	if not character then return 0 end
	return character:GetAttribute("Fame") or 0
end

function StatsModule.AddFame(character, amount)
	if not character then return false end
	local current = character:GetAttribute("Fame") or 0
	local newFame = math.clamp(current + amount, 0, 100)
	character:SetAttribute("Fame", newFame)

	local wasAbove = current >= FAME_SPEED_THRESHOLD
	local isAbove = newFame >= FAME_SPEED_THRESHOLD
	if isAbove ~= wasAbove then
		StatsModule.ResetSpeedMultiplier(character) -- recalcula con el Fame ya actualizado
	end

	return true
end

function StatsModule.SetFame(character, value)
	if not character then return false end
	local clamped = math.clamp(value, 0, 100)
	local current = character:GetAttribute("Fame") or 0
	character:SetAttribute("Fame", clamped)

	local wasAbove = current >= FAME_SPEED_THRESHOLD
	local isAbove = clamped >= FAME_SPEED_THRESHOLD
	if isAbove ~= wasAbove then
		StatsModule.ResetSpeedMultiplier(character) -- recalcula con el Fame ya actualizado
	end

	return true
end

-- == SCELLS SYSTEM HELPERS (Trunks pasiva) ==

function StatsModule.GetSCells(character)
	if not character then return 0 end
	local stats = StatsModule.GetStats(character)
	if not stats then return 0 end
	local sCells = stats:FindFirstChild("SCells")
	return sCells and sCells.Value or 0
end

function StatsModule.AddSCells(character, amount)
	if not character then return false end
	local stats = StatsModule.GetStats(character)
	if not stats then return false end
	local sCells = stats:FindFirstChild("SCells")
	local sCellsMax = stats:FindFirstChild("SCellsMax")
	if not (sCells and sCellsMax) then return false end
	sCells.Value = math.clamp(sCells.Value + amount, 0, sCellsMax.Value)
	return true
end

function StatsModule.ConsumeSCells(character, amount)
	if not character then return false end
	local stats = StatsModule.GetStats(character)
	if not stats then return false end
	local sCells = stats:FindFirstChild("SCells")
	if not sCells or sCells.Value < amount then return false end
	sCells.Value = sCells.Value - amount
	return true
end

function StatsModule.SetSCells(character, value)
	if not character then return false end
	local stats = StatsModule.GetStats(character)
	if not stats then return false end
	local sCells = stats:FindFirstChild("SCells")
	local sCellsMax = stats:FindFirstChild("SCellsMax")
	if not (sCells and sCellsMax) then return false end
	sCells.Value = math.clamp(value, 0, sCellsMax.Value)
	return true
end

function StatsModule.IsSuperSaiyan(character)
	if not character then return false end
	local stats = StatsModule.GetStats(character)
	if not stats then return false end
	local ss = stats:FindFirstChild("IsSuperSaiyan")
	return ss and ss.Value or false
end

function StatsModule.SetSuperSaiyan(character, enabled)
	if not character then return false end
	local stats = StatsModule.GetStats(character)
	if not stats then return false end
	local ss = stats:FindFirstChild("IsSuperSaiyan")
	if not ss then return false end

	ss.Value = enabled
	StatsModule.ResetSpeedMultiplier(character) -- aplica 1.35 si está activo, 1.0 si no (y respeta aturdimiento)

	return true
end

return StatsModule