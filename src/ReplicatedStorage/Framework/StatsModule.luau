--[[
	StatsModule (ModuleScript)
	Ubicacion: ReplicatedStorage.Framework.StatsModule
	
	Gestiona las estadisticas, estados, dano, curacion, remates (Downed/Bleedout)
	y sistemas especiales (Fame de Neuro y SCells de Trunks).
]]

local StatsModule = {}

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

		-- SCELLS SYSTEM (Trunks pasiva)
		if charName == "Trunks" then
			createValue("SCells", "NumberValue", 0)
			createValue("SCellsMax", "IntValue", 20)
			createValue("IsSuperSaiyan", "BoolValue", false)
		end
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

function StatsModule.ApplyDamage(character, damage, ignoreDowned)
	local stats = StatsModule.GetStats(character)
	if not stats then return false end

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
				task.delay(defaultBleed, function()
					if character and character.Parent then
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

function StatsModule.ApplyHeal(character, healAmount)
	local stats = StatsModule.GetStats(character)
	if not stats then return false end

	local health = stats:FindFirstChild("Health")
	local maxHealth = stats:FindFirstChild("MaxHealth")
	local isAlive = stats:FindFirstChild("IsAlive")

	if not (health and maxHealth and isAlive) or not isAlive.Value then return false end

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

function StatsModule.ResetSpeedMultiplier(character)
	local stats = StatsModule.GetStats(character)
	if not stats then return false end

	local speedMult = stats:FindFirstChild("SpeedMultiplier")
	local walkSpeed = stats:FindFirstChild("WalkSpeed")
	if not (speedMult and walkSpeed) then return false end

	speedMult.Value = 1.0

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = walkSpeed.Value
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

	state.Value = newState

	if newState == StatsModule.CharacterState.Dead then
		if isAlive then isAlive.Value = false end
		if isDowned then isDowned.Value = false end
		character:SetAttribute("IsDowned", false)

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

	local wasAbove = current >= 45
	local isAbove = newFame >= 45
	if isAbove and not wasAbove then
		StatsModule.SetSpeedMultiplier(character, 1.25)
	elseif not isAbove and wasAbove then
		StatsModule.ResetSpeedMultiplier(character)
	end

	return true
end

function StatsModule.SetFame(character, value)
	if not character then return false end
	local clamped = math.clamp(value, 0, 100)
	local current = character:GetAttribute("Fame") or 0
	character:SetAttribute("Fame", clamped)

	local wasAbove = current >= 45
	local isAbove = clamped >= 45
	if isAbove and not wasAbove then
		StatsModule.SetSpeedMultiplier(character, 1.25)
	elseif not isAbove and wasAbove then
		StatsModule.ResetSpeedMultiplier(character)
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

	if enabled then
		StatsModule.SetSpeedMultiplier(character, 1.35)
	else
		StatsModule.ResetSpeedMultiplier(character)
	end

	return true
end

return StatsModule