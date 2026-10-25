local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StatsModule = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("StatsModule"))

local ShedMovAbilities = {}

-- Auxiliar: Obtiene el Humanoid y RootPart de un modelo de personaje válido
local function getValidCharacter(model: Instance?)
	if not model or not model:IsA("Model") then return nil, nil end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hum and hrp and hum.Health > 0 and not model:GetAttribute("Escaped") then
		return hum, hrp
	end
	return nil, nil
end

--------------------------------------------------------------------------------
-- HABILIDAD 1: CARGA DE MOTOSIERRA (Cooldown: 24s)
--------------------------------------------------------------------------------
function ShedMovAbilities.CargaMotosierra(caster: Model, config: table): (boolean, string?)
	local _, casterHRP = getValidCharacter(caster)
	if not casterHRP then return false, "CasterInvalido" end

	-- Crear fuerza de empuje (LinearVelocity)
	local attachment = Instance.new("Attachment")
	attachment.Name = "ChainsawAttachment"
	attachment.Parent = casterHRP

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "ChainsawSprintForce"
	linearVelocity.MaxForce = 100000
	linearVelocity.VectorVelocity = casterHRP.CFrame.LookVector * config.DashSpeed
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.Attachment0 = attachment
	linearVelocity.Parent = casterHRP

	Debris:AddItem(attachment, config.DashDuration)
	Debris:AddItem(linearVelocity, config.DashDuration)

	local hitToonflow = false
	local startTime = os.clock()

	-- Parámetros de detección de impacto
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {caster}

	-- Hilo de detección de impacto durante el sprint
	task.spawn(function()
		while (os.clock() - startTime) < config.DashDuration and not hitToonflow do
			local parts = workspace:GetPartBoundsInRadius(casterHRP.Position, 4.5, overlapParams)
			for _, part in ipairs(parts) do
				local targetModel = part.Parent
				if targetModel and targetModel:GetAttribute("Role") == "Toonflow" then
					local targetHum, targetHRP = getValidCharacter(targetModel)
					if targetHum and targetHRP then
						hitToonflow = true
						
						-- Detener la carga de inmediato
						if linearVelocity then linearVelocity:Destroy() end
						if attachment then attachment:Destroy() end

						-- Aplicar Daño Base
						targetHum:TakeDamage(config.Damage)

						-- Aplicar Debuff de Sangrado (tick de daño continuo)
						task.spawn(function()
							local bleedTicks = config.BleedDuration
							for _ = 1, bleedTicks do
								task.wait(1)
								if targetHum and targetHum.Health > 0 then
									targetHum:TakeDamage(config.BleedDamage)
								end
							end
						end)

						break
					end
				end
			end
			task.wait(0.05)
		end

		-- Si no golpeó a nadie (Whiffing), se aplica el aturdimiento de recuperación
		if not hitToonflow then
			if linearVelocity then linearVelocity:Destroy() end
			if attachment then attachment:Destroy() end
			StatsModule.Stun(caster, config.RecoveryStun)
		end
	end)

	return true
end

--------------------------------------------------------------------------------
-- HABILIDAD 2: ¡FUERA DE MI COBERTIZO! (Cooldown: 30s)
--------------------------------------------------------------------------------
function ShedMovAbilities.FueraDeMiCobertizo(caster: Model, config: table): (boolean, string?)
	local _, casterHRP = getValidCharacter(caster)
	if not casterHRP then return false, "CasterInvalido" end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {caster}

	local partsNear = workspace:GetPartBoundsInRadius(casterHRP.Position, config.Radius, overlapParams)
	local affectedCharacters = {}

	for _, part in ipairs(partsNear) do
		local targetModel = part.Parent
		if targetModel and targetModel:GetAttribute("Role") == "Toonflow" and not affectedCharacters[targetModel] then
			local targetHum, _ = getValidCharacter(targetModel)
			if targetHum then
				affectedCharacters[targetModel] = true

				-- 1. Aplicar Lentitud (Slow I - 50%)
				StatsModule.ApplySpeedMultiplier(targetModel, "ShedSlow", config.SlowMultiplier, config.SlowDuration)

				-- 2. Cancelar interacciones activas (Tareas o Reanimaciones)
				targetModel:SetAttribute("IsDoingTask", false)
				targetModel:SetAttribute("IsReviving", false)

				-- 3. Revelar posición / Aura
				targetModel:SetAttribute("Revealed", true)
				
				-- Crear Highlight visual de revelado
				local highlight = Instance.new("Highlight")
				highlight.Name = "ShedRevealHighlight"
				highlight.FillColor = Color3.fromRGB(255, 0, 0)
				highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
				highlight.FillTransparency = 0.5
				highlight.Parent = targetModel
				Debris:AddItem(highlight, config.RevealDuration)

				task.delay(config.RevealDuration, function()
					if targetModel then
						targetModel:SetAttribute("Revealed", false)
					end
				end)
			end
		end
	end

	return true
end

--------------------------------------------------------------------------------
-- HABILIDAD 3 (ULTIMATE): BIENVENIDA A PONYVILLE (Cooldown: 90s)
--------------------------------------------------------------------------------
function ShedMovAbilities.BienvenidaAPonyville(caster: Model, config: table): (boolean, string?)
	local casterHum, _ = getValidCharacter(caster)
	if not casterHum then return false, "CasterInvalido" end

	-- 1. Inmunidad a Stuns y Debuffs
	caster:SetAttribute("StunImmune", true)

	-- 2. Incremento de velocidad de movimiento (+20%)
	StatsModule.ApplySpeedMultiplier(caster, "WelcomeToPonyvilleSpeed", 1 + config.SpeedBuff, config.Duration)

	-- 3. Buff de velocidad de ataque (+50%)
	caster:SetAttribute("AttackSpeedMultiplier", 1.5)

	-- Retirar los efectos al finalizar los 15 segundos
	task.delay(config.Duration, function()
		if caster then
			caster:SetAttribute("StunImmune", false)
			caster:SetAttribute("AttackSpeedMultiplier", 1.0)
		end
	end)

	return true
end

return ShedMovAbilities