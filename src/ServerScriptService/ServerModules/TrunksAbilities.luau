--[[
	TrunksAbilities (ModuleScript)
	Ubicación: ServerScriptService.ServerModules.TrunksAbilities

	Define las 3 habilidades del personaje TOONFLOW "Trunks":
	  1. "ZSword"     -> Swing melee con espada Z. 25 daño + knockback. +5 SCells. CD: 20s
	  2. "KiBlasts"    -> 3 proyectiles consecutivos. 8 daño c/u + ceguera leve. +1 SCell/impacto (max +3). CD: 20s
	  3. "SuperSaiyan" -> Transformación. Requiere 10+ SCells. Consume 1/seg. SpeedMultiplier 1.35 + 25% CD reduction.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local AbilityFramework = require(game:GetService("ServerScriptService").ServerModules.AbilityFramework)
local StatsModule = require(game:GetService("ServerScriptService").ServerModules.StatsModule)
local VFXModule = require(game.ReplicatedStorage.Framework.VFXModule)

local TrunksAbilities = {}

-- == GESTOR ROBUSTO DE S-CELLS Y STATS DE TRUNKS ==

local function ensureSCellStats(character)
	if not character then return nil, nil end

	local statsFolder = character:FindFirstChild("Stats")
	if not statsFolder then
		statsFolder = Instance.new("Folder")
		statsFolder.Name = "Stats"
		statsFolder.Parent = character
	end

	local sCellsVal = statsFolder:FindFirstChild("SCells")
	if not sCellsVal then
		sCellsVal = Instance.new("NumberValue")
		sCellsVal.Name = "SCells"
		sCellsVal.Value = 0
		sCellsVal.Parent = statsFolder
	end

	local sCellsMaxVal = statsFolder:FindFirstChild("SCellsMax")
	if not sCellsMaxVal then
		sCellsMaxVal = Instance.new("NumberValue")
		sCellsMaxVal.Name = "SCellsMax"
		sCellsMaxVal.Value = 20
		sCellsMaxVal.Parent = statsFolder
	end

	return sCellsVal, sCellsMaxVal
end

local function getSCells(character)
	if StatsModule.GetSCells then
		local val = StatsModule.GetSCells(character)
		if val then return val end
	end
	local sVal = ensureSCellStats(character)
	return sVal and sVal.Value or 0
end

local function addSCells(character, amount)
	local sVal, sMax = ensureSCellStats(character)
	if sVal and sMax then
		local newAmount = math.clamp(sVal.Value + amount, 0, sMax.Value)
		sVal.Value = newAmount
		character:SetAttribute("SCells", newAmount)
	end

	if StatsModule.AddSCells then
		pcall(function() StatsModule.AddSCells(character, amount) end)
	end
end

local function consumeSCells(character, amount)
	local sVal, sMax = ensureSCellStats(character)
	if sVal then
		local newAmount = math.clamp(sVal.Value - amount, 0, sMax.Value)
		sVal.Value = newAmount
		character:SetAttribute("SCells", newAmount)
	end

	if StatsModule.ConsumeSCells then
		pcall(function() StatsModule.ConsumeSCells(character, amount) end)
	end
end

local function isSuperSaiyanActive(character)
	if character:GetAttribute("IsSuperSaiyan") ~= nil then
		return character:GetAttribute("IsSuperSaiyan")
	end
	if StatsModule.IsSuperSaiyan then
		return StatsModule.IsSuperSaiyan(character)
	end
	return false
end

local function setSuperSaiyanActive(character, active)
	character:SetAttribute("IsSuperSaiyan", active)
	if StatsModule.SetSuperSaiyan then
		pcall(function() StatsModule.SetSuperSaiyan(character, active) end)
	end
end

-- == CONTROLADORES VISUALES DEL MODELO DE TRUNKS ==

local function setModelTransparency(instance, transparency)
	if not instance then return end
	if instance:IsA("BasePart") or instance:IsA("Decal") then
		instance.Transparency = transparency
	end
	for _, child in ipairs(instance:GetDescendants()) do
		if child:IsA("BasePart") or child:IsA("Decal") then
			child.Transparency = transparency
		end
	end
end

-- Intercambia visibilidad entre NormalHair y SuperHair según el modelo
local function setHairState(character, isSSJ)
	local normalHair = character:FindFirstChild("NormalHair") or character:FindFirstChild("Normalhair")
	local superHair = character:FindFirstChild("SuperHair") or character:FindFirstChild("Superhair")

	if normalHair then
		setModelTransparency(normalHair, isSSJ and 1 or 0)
	end

	if superHair then
		setModelTransparency(superHair, isSSJ and 0 or 1)
	end
end

-- Enciende o apaga las partículas dentro del objeto "AURA"
local function setAuraState(character, enabled)
	local auraPart = character:FindFirstChild("AURA") or character:FindFirstChild("Aura") or character:FindFirstChild("aura")
	if not auraPart then return end

	if auraPart:IsA("BasePart") then
		auraPart.Transparency = 1 -- El contenedor se mantiene invisible
	end

	for _, descendant in ipairs(auraPart:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Light") or descendant:IsA("Beam") then
			descendant.Enabled = enabled
		end
	end
end

local function setSwordState(character, visible)
	local sword = character:FindFirstChild("ZSword") or character:FindFirstChild("Espada") or character:FindFirstChild("Sword")
	if not sword then return end
	setModelTransparency(sword, visible and 0 or 1)
end

-- == DETECCIÓN FLEXIBLE DE ENEMIGOS ==
local function getValidDevilishTargets(attackerChar)
	local targets = {}

	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") and model ~= attackerChar then
			local hum = model:FindFirstChildOfClass("Humanoid")
			local hrp = model:FindFirstChild("HumanoidRootPart")

			if hum and hum.Health > 0 and hrp then
				local isDevilish = false
				local stats = StatsModule.GetStats(model)

				if stats then
					local role = stats:FindFirstChild("Role")
					if role and role.Value == StatsModule.Role.Devilish then
						isDevilish = true
					end
				end

				if model:GetAttribute("IsDevilish") or model:GetAttribute("Role") == "Devilish" or string.find(model.Name, "BOT_") then
					isDevilish = true
				end

				if isDevilish then
					table.insert(targets, { character = model, hrp = hrp, humanoid = hum })
				end
			end
		end
	end

	return targets
end

-- == HABILIDAD 1: Z SWORD ==
AbilityFramework.Register({
	Name = "ZSword",
	Description = "Swing melee con la Espada Z. 25 daño + knockback. +5 SCells.",
	MaxCharges = 1,
	Cooldown = 20,
	CostType = nil,
	CostAmount = 0,
	CastTime = 0,
	Range = 12,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		local targetData = params.TargetData
		if not (character and player) then return end

		ensureSCellStats(character)

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local damage = 25
		local swingRange = 12

		setSwordState(character, true)

		local swingDirection = (typeof(targetData) == "Vector3") and (targetData - hrp.Position).Unit or hrp.CFrame.LookVector
		local swingEndPoint = hrp.Position + swingDirection * swingRange
		local origin = hrp.Position + hrp.CFrame.UpVector * 1.5

		VFXModule.SpawnSwordSwingVFX(origin, swingEndPoint)

		local hitBox = Instance.new("Part")
		hitBox.Name = "ZSword_Hitbox"
		hitBox.Size = Vector3.new(12, 8, 12)
		hitBox.CFrame = hrp.CFrame * CFrame.new(0, 0, -5)
		hitBox.CanCollide = false
		hitBox.Anchored = true
		hitBox.Transparency = 1
		hitBox.Parent = workspace

		local overlapParams = OverlapParams.new()
		overlapParams.FilterDescendantsInstances = {character}
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude

		local parts = workspace:GetPartsInPart(hitBox, overlapParams)
		local hitSomeone = false
		local hitCharacters = {}

		for _, part in ipairs(parts) do
			local targetChar = part.Parent
			if targetChar and not hitCharacters[targetChar] then
				local hum = targetChar:FindFirstChildOfClass("Humanoid")
				local targetHrp = targetChar:FindFirstChild("HumanoidRootPart")

				if hum and hum.Health > 0 and targetHrp and targetChar ~= character then
					local isDevilish = false
					local stats = StatsModule.GetStats(targetChar)

					if stats then
						local role = stats:FindFirstChild("Role")
						if role and role.Value == StatsModule.Role.Devilish then
							isDevilish = true
						end
					end

					if targetChar:GetAttribute("IsDevilish") or targetChar:GetAttribute("Role") == "Devilish" or string.find(targetChar.Name, "BOT_") or targetChar.Name == "DummyDevilish" then
						isDevilish = true
					end

					if isDevilish then
						hitCharacters[targetChar] = true
						StatsModule.ApplyDamage(targetChar, damage)
						VFXModule.SpawnMeleeHitVFX(targetHrp.Position, Color3.fromRGB(255, 215, 0))
						targetHrp.AssemblyLinearVelocity = swingDirection * 50 + Vector3.new(0, 20, 0)
						hitSomeone = true
					end
				end
			end
		end

		hitBox:Destroy()

		if hitSomeone then
			addSCells(character, 5)
			VFXModule.SpawnSCellGainVFX(character)
			print("[Trunks] Espada Z conectada. +5 Células S otorgadas.")
		end

		task.delay(0.6, function()
			if character and character.Parent then
				setSwordState(character, false)
			end
		end)
	end,
})

-- == HABILIDAD 2: KI BLASTS ==
AbilityFramework.Register({
	Name = "KiBlasts",
	Description = "3 proyectiles de Ki consecutivos. 8 daño c/u + ceguera leve. +1 SCell/impacto (max +3).",
	MaxCharges = 1,
	Cooldown = 20,
	CostType = nil,
	CostAmount = 0,
	CastTime = 0,
	Range = 60,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		local targetData = params.TargetData
		if not (character and player) then return end

		ensureSCellStats(character)

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local damagePerHit = 8
		local totalProjectiles = 3
		local sCellsGained = 0

		local targetPosition = (typeof(targetData) == "Vector3") and targetData or (hrp.Position + hrp.CFrame.LookVector * 60)

		task.spawn(function()
			for i = 1, totalProjectiles do
				if not (character and character.Parent and hrp and hrp.Parent) then break end

				local origin = hrp.Position + hrp.CFrame.UpVector * 1.5
				local spread = (i - 2) * 2
				local adjustedTarget = targetPosition + Vector3.new(spread, 0, spread)

				VFXModule.SpawnKiBlastVFX(origin, adjustedTarget)

				local rayDirection = (adjustedTarget - origin).Unit * 60
				local raycastParams = RaycastParams.new()
				raycastParams.FilterDescendantsInstances = {character}
				raycastParams.FilterType = Enum.RaycastFilterType.Exclude

				local result = workspace:Raycast(origin, rayDirection, raycastParams)
				local hitPos = result and result.Position or adjustedTarget

				local targets = getValidDevilishTargets(character)
				local hitSomeone = false

				for _, target in ipairs(targets) do
					if (target.hrp.Position - hitPos).Magnitude <= 7 or (target.hrp.Position - origin).Magnitude <= 10 then
						StatsModule.ApplyDamage(target.character, damagePerHit)
						VFXModule.SpawnMeleeHitVFX(target.hrp.Position, Color3.fromRGB(255, 215, 0))
						hitSomeone = true

						local targetPlayer = Players:GetPlayerFromCharacter(target.character)
						if targetPlayer then
							local blindRemote = ReplicatedStorage.Framework.Remotes:FindFirstChild("BlindEffect")
							if blindRemote then blindRemote:FireClient(targetPlayer, 1.5) end
						end

						if sCellsGained < 3 then
							addSCells(character, 1)
							sCellsGained += 1
							print("[Trunks] Ráfaga de Ki conectada. +1 Célula S (" .. sCellsGained .. "/3)")
						end
						break
					end
				end

				if hitSomeone then
					VFXModule.SpawnSCellGainVFX(character)
				end

				if i < totalProjectiles then task.wait(0.25) end
			end
		end)
	end,
})

-- == HABILIDAD 3: SUPER SAIYAN ==
AbilityFramework.Register({
	Name = "SuperSaiyan",
	Description = "Transformación Super Saiyan. Requiere 10+ SCells. Consume 1/seg. SpeedMultiplier 1.35 + 25% CD reduction.",
	MaxCharges = 1,
	Cooldown = 1,
	CostType = nil,
	CostAmount = 0,
	CastTime = 0,
	Range = 0,

	CustomCheck = function(player, character)
		local isSSJ = isSuperSaiyanActive(character)
		if isSSJ then return true, "OK" end

		local currentSCells = getSCells(character)
		if currentSCells < 10 then return false, "InsufficientSCells" end
		return true, "OK"
	end,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		if not (character and player) then return end

		local isSSJ = isSuperSaiyanActive(character)
		local hum = character:FindFirstChildOfClass("Humanoid")

		if isSSJ then
			-- DESACTIVAR SUPER SAIYAN
			setSuperSaiyanActive(character, false)
			AbilityFramework.ClearCooldownModifier(player, "ZSword")
			AbilityFramework.ClearCooldownModifier(player, "KiBlasts")

			if hum then hum.WalkSpeed = 16 end
			setHairState(character, false)
			setAuraState(character, false)
			print("[Trunks] Super Saiyan desactivado.")
		else
			-- ACTIVAR SUPER SAIYAN
			setSuperSaiyanActive(character, true)
			AbilityFramework.SetCooldownModifier(player, "ZSword", 0.75)
			AbilityFramework.SetCooldownModifier(player, "KiBlasts", 0.75)

			if hum then hum.WalkSpeed = 22 end
			setHairState(character, true)
			setAuraState(character, true)

			VFXModule.SpawnSuperSaiyanVFX(character)
			print("[Trunks] Super Saiyan activado!")

			-- BUCLE DE CONSUMO POR SEGUNDO
			task.spawn(function()
				while true do
					task.wait(1)
					if not (character and character.Parent) then break end
					if not isSuperSaiyanActive(character) then break end

					local currentSCells = getSCells(character)
					if currentSCells <= 0 then
						setSuperSaiyanActive(character, false)
						AbilityFramework.ClearCooldownModifier(player, "ZSword")
						AbilityFramework.ClearCooldownModifier(player, "KiBlasts")

						if hum then hum.WalkSpeed = 16 end
						setHairState(character, false)
						setAuraState(character, false)
						print("[Trunks] S-CELLS agotadas. Super Saiyan terminado.")
						break
					end

					consumeSCells(character, 1)
				end
			end)
		end
	end,
})

return TrunksAbilities