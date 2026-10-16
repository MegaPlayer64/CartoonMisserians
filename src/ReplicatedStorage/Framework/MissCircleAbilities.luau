--[[
	MissCircleAbilities (ModuleScript)
	Ubicación: ReplicatedStorage.Framework.MissCircleAbilities

	Define las 4 habilidades de la DEVILISH inicial "Miss Circle":
	  1. "LinearThrust"     -> Estocada con el compás. Dash frontal, 20 daño + lentitud leve (2s). CD: 15s
	  2. "PunishmentRadius" -> Traza un círculo de tiza de 20s en el piso. Expone y alenta a quienes entren. CD: 45s
	  3. "FailingGrade"     -> Revela la ubicación exacta (Aura) del Toonflow más cercano por 4s. CD: 25s
	  4. "DetentionTime"    -> Modo iracundo por 10s (+25% WalkSpeed + mayor rango M1 + ojos brillantes). CD: 60s
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local AbilityFramework = require(ReplicatedStorage.Framework.AbilityFramework)
local StatsModule = require(ReplicatedStorage.Framework.StatsModule)

local MissCircleAbilities = {}

-- Auxiliar: Obtener todos los Toonflows vivos en partida
local function getActiveToonflows()
	local toons = {}
	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") then
			local hum = model:FindFirstChildOfClass("Humanoid")
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health > 0 and hrp then
				local isDevilish = model:GetAttribute("IsDevilish") or model:GetAttribute("Role") == "Devilish"
				local stats = StatsModule.GetStats(model)
				if stats then
					local role = stats:FindFirstChild("Role")
					if role and role.Value == StatsModule.Role.Devilish then
						isDevilish = true
					end
				end

				if not isDevilish then
					table.insert(toons, { character = model, hrp = hrp, humanoid = hum })
				end
			end
		end
	end
	return toons
end

-- == HABILIDAD 1: ESTOCADA EN LÍNEA ==
AbilityFramework.Register({
	Name = "LinearThrust",
	Description = "Miss Circle se abalanza con la punta de su compás. Inflige 20 de daño y aplica lentitud leve.",
	MaxCharges = 1,
	Cooldown = 15,
	CastTime = 0,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		local targetData = params.TargetData
		if not (character and player) then return end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local dashDirection = (typeof(targetData) == "Vector3") and (targetData - hrp.Position).Unit or hrp.CFrame.LookVector
		dashDirection = Vector3.new(dashDirection.X, 0, dashDirection.Z).Unit

		-- Impulso físico de embestida
		local attachment = Instance.new("Attachment")
		attachment.Parent = hrp

		local linearVelocity = Instance.new("LinearVelocity")
		linearVelocity.MaxForce = 100000
		linearVelocity.VectorVelocity = dashDirection * 55
		linearVelocity.Attachment0 = attachment
		linearVelocity.Parent = hrp

		Debris:AddItem(linearVelocity, 0.3)
		Debris:AddItem(attachment, 0.3)

		-- Detección de impacto
		local hitBox = Instance.new("Part")
		hitBox.Name = "Thrust_Hitbox"
		hitBox.Size = Vector3.new(8, 7, 12)
		hitBox.CFrame = hrp.CFrame * CFrame.new(0, 0, -4)
		hitBox.CanCollide = false
		hitBox.Anchored = true
		hitBox.Transparency = 1
		hitBox.Parent = workspace

		local overlapParams = OverlapParams.new()
		overlapParams.FilterDescendantsInstances = {character}
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude

		local parts = workspace:GetPartsInPart(hitBox, overlapParams)
		local hitSet = {}

		for _, part in ipairs(parts) do
			local targetChar = part.Parent
			if targetChar and not hitSet[targetChar] then
				local hum = targetChar:FindFirstChildOfClass("Humanoid")
				local targetHrp = targetChar:FindFirstChild("HumanoidRootPart")

				if hum and hum.Health > 0 and targetHrp then
					local isToon = true
					local stats = StatsModule.GetStats(targetChar)
					if stats and stats:FindFirstChild("Role") and stats.Role.Value == StatsModule.Role.Devilish then
						isToon = false
					end

					if isToon then
						hitSet[targetChar] = true
						StatsModule.ApplyDamage(targetChar, 20)

						-- Aplicar lentitud del 25% por 2.5 segundos
						local originalSpeed = hum.WalkSpeed
						hum.WalkSpeed = math.max(6, originalSpeed * 0.75)
						task.delay(2.5, function()
							if hum and hum.Parent then
								hum.WalkSpeed = originalSpeed
							end
						end)
					end
				end
			end
		end

		hitBox:Destroy()
	end,
})

-- == HABILIDAD 2: RADIO DEL CASTIGO ==
AbilityFramework.Register({
	Name = "PunishmentRadius",
	Description = "Traza un área circular de tiza en el suelo. Los Toonflows que la crucen sufren gran lentitud y son expuestos.",
	MaxCharges = 1,
	Cooldown = 45,
	CastTime = 0,

	Execute = function(params)
		local character = params.Character
		if not character then return end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		-- Crear el área circular visual en el suelo
		local circleRadius = 14
		local circlePart = Instance.new("Part")
		circlePart.Name = "PunishmentCircle"
		circlePart.Shape = Enum.PartType.Cylinder
		circlePart.Size = Vector3.new(0.5, circleRadius * 2, circleRadius * 2)
		circlePart.CFrame = CFrame.new(hrp.Position - Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		circlePart.Anchored = true
		circlePart.CanCollide = false
		circlePart.Material = Enum.Material.Neon
		circlePart.Color = Color3.fromRGB(240, 240, 255)
		circlePart.Transparency = 0.4
		circlePart.Parent = workspace

		-- Bucle de detección durante 20 segundos
		task.spawn(function()
			local duration = 20
			local elapsed = 0

			while elapsed < duration and circlePart and circlePart.Parent do
				task.wait(0.25)
				elapsed += 0.25

				local centerPos = circlePart.Position
				for _, toon in ipairs(getActiveToonflows()) do
					local dist = (Vector3.new(toon.hrp.Position.X, centerPos.Y, toon.hrp.Position.Z) - centerPos).Magnitude
					if dist <= circleRadius then
						-- Exponer ubicación (Aura)
						if not toon.character:FindFirstChild("Circle_Exposed") then
							local highlight = Instance.new("Highlight")
							highlight.Name = "Circle_Exposed"
							highlight.FillColor = Color3.fromRGB(255, 50, 50)
							highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
							highlight.FillTransparency = 0.5
							highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
							highlight.Parent = toon.character
							Debris:AddItem(highlight, 1)
						end

						-- Gran lentitud mientras esté adentro
						toon.humanoid.WalkSpeed = 9
						task.delay(0.5, function()
							if toon.humanoid and toon.humanoid.Parent and toon.humanoid.WalkSpeed == 9 then
								toon.humanoid.WalkSpeed = 16
							end
						end)
					end
				end
			end

			if circlePart then circlePart:Destroy() end
		end)
	end,
})

-- == HABILIDAD 3: BOLETÍN DE CALIFICACIONES ==
AbilityFramework.Register({
	Name = "FailingGrade",
	Description = "Muestra la ubicación exacta del Toonflow más cercano atravesando paredes por 4 segundos.",
	MaxCharges = 1,
	Cooldown = 25,
	CastTime = 0,

	Execute = function(params)
		local character = params.Character
		if not character then return end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local closestToon = nil
		local minDistance = math.huge

		for _, toon in ipairs(getActiveToonflows()) do
			local dist = (toon.hrp.Position - hrp.Position).Magnitude
			if dist < minDistance then
				minDistance = dist
				closestToon = toon.character
			end
		end

		if closestToon then
			local highlight = Instance.new("Highlight")
			highlight.Name = "FailingGrade_Aura"
			highlight.FillColor = Color3.fromRGB(255, 0, 0)
			highlight.OutlineColor = Color3.fromRGB(255, 255, 0)
			highlight.FillTransparency = 0.3
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.Parent = closestToon

			Debris:AddItem(highlight, 4)
			print("[MissCircle] Boletín entregado a: " .. closestToon.Name)
		end
	end,
})

-- == HABILIDAD 4: HORA DE DETENCIÓN ==
AbilityFramework.Register({
	Name = "DetentionTime",
	Description = "Modo Iracundo: +25% velocidad y mayor alcance de M1 por 10 segundos.",
	MaxCharges = 1,
	Cooldown = 60,
	CastTime = 0,

	Execute = function(params)
		local character = params.Character
		if not character then return end

		local hum = character:FindFirstChildOfClass("Humanoid")
		local hrp = character:FindFirstChild("HumanoidRootPart")

		if hum then
			local baseSpeed = hum.WalkSpeed
			hum.WalkSpeed = baseSpeed * 1.25 -- +25% velocidad

			-- Aumentar atributo de rango de M1
			character:SetAttribute("AttackRange", 11)
			character:SetAttribute("IsEnraged", true)

			-- Aura iracunda
			local highlight = Instance.new("Highlight")
			highlight.Name = "Detention_Aura"
			highlight.FillColor = Color3.fromRGB(180, 0, 0)
			highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
			highlight.FillTransparency = 0.6
			highlight.Parent = character

			task.delay(10, function()
				if character and character.Parent then
					character:SetAttribute("AttackRange", 8)
					character:SetAttribute("IsEnraged", false)

					if hum and hum.Parent then
						hum.WalkSpeed = baseSpeed
					end

					local aura = character:FindFirstChild("Detention_Aura")
					if aura then aura:Destroy() end
				end
			end)
		end
	end,
})

return MissCircleAbilities