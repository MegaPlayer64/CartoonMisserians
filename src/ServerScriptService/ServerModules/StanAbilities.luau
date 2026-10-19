--[[
	StanAbilities (ModuleScript)
	Ubicacion: ServerScriptService.ServerModules.StanAbilities

	Define las 4 habilidades del personaje DEVILISH "Stan.oma.png":
	  Slot1 "RayoCorrupto"    -> Rayo que daña 30 + lanza Pop-ups corruptos al Toonflow. CD: 18s
	  Slot2 "BetterCallStan"  -> Invoca 2 clones que persiguen y envenenan. CD: 40s
	  Slot3 "CorrupcionGrave" -> Rastro de veneno ampliado + reduce velocidad. CD: 30s
	  Slot4 "CambioArma"      -> Alterna entre M1 melee y M1 láser (Taser). CD: 10s

	PASIVA: "Corrupcion Inminente"
	  - Cada 20s deja rastros de veneno por 5s al moverse.

	M1 ADAPTATIVO:
	  - Modo melee: golpe directo 22 dmg, 30% prob de Burn 1s.
	  - Modo láser: raycast 15 dmg + efecto aleatorio 1s (Slowness/Burn/Corruption).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local AbilityFramework = require(game:GetService("ServerScriptService").ServerModules.AbilityFramework)
local StatsModule = require(game:GetService("ServerScriptService").ServerModules.StatsModule)
local VFXModule = require(ReplicatedStorage.Framework.VFXModule)

local Remotes = ReplicatedStorage.Framework.Remotes
local PopupRemote = Remotes:FindFirstChild("TriggerPopups")

local BotController
local function getBotController()
	if not BotController then
		local module = ServerScriptService:FindFirstChild("BotController")
		if module then
			BotController = require(module)
		end
	end
	return BotController
end

local StanAbilities = {}

-- == COLOR TEMA DE STAN ==
local STAN_COLOR = Color3.fromRGB(80, 0, 100)

---------------------------------------------------------
-- HELPER: APLICAR ESTADO ALTERADO INLINE
---------------------------------------------------------
local function applyStatusEffect(targetChar, effectName, duration)
	if not (targetChar and targetChar.Parent) then return end
	duration = duration or 3

	if effectName == "Poison" then
		task.spawn(function()
			local elapsed = 0
			local tickRate = 0.5
			local damagePerTick = 2
			while elapsed < duration and targetChar and targetChar.Parent do
				task.wait(tickRate)
				elapsed = elapsed + tickRate
				StatsModule.ApplyDamage(targetChar, damagePerTick)
			end
		end)
	elseif effectName == "Burn" then
		task.spawn(function()
			local elapsed = 0
			local tickRate = 0.5
			local damagePerTick = 3
			while elapsed < duration and targetChar and targetChar.Parent do
				task.wait(tickRate)
				elapsed = elapsed + tickRate
				StatsModule.ApplyDamage(targetChar, damagePerTick)
			end
		end)
	elseif effectName == "Slowness" then
		StatsModule.SetSpeedMultiplier(targetChar, 0.5)
		task.delay(duration, function()
			if targetChar and targetChar.Parent then
				StatsModule.ResetSpeedMultiplier(targetChar)
			end
		end)
	elseif effectName == "Corruption" then
		local hl = Instance.new("Highlight")
		hl.Name = "CorruptionEffect"
		hl.FillColor = STAN_COLOR
		hl.OutlineColor = Color3.fromRGB(120, 0, 150)
		hl.FillTransparency = 0.4
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = targetChar
		Debris:AddItem(hl, duration)
	end
end

---------------------------------------------------------
-- HELPER: REVELAR AURA
---------------------------------------------------------
local function revealAura(targetChar, devilishChar, duration)
	if targetChar and targetChar.Parent then
		VFXModule.SpawnRevealVFX(targetChar, duration)
	end
end

---------------------------------------------------------
-- PASIVA: CORRUPCION INMINENTE
---------------------------------------------------------
function StanAbilities.StartPassiveTrail(character)
	task.spawn(function()
		while character and character.Parent do
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then break end

			task.wait(20) -- Cada 20 segundos

			local startTime = tick()
			while tick() - startTime < 5 do -- Dura 5 segundos soltando rastro
				if not (character and character.Parent) then break end
				local hrp = character:FindFirstChild("HumanoidRootPart")
				if hrp then
					StanAbilities.SpawnTrailPart(hrp.CFrame - Vector3.new(0, 2.5, 0), Vector3.new(3, 0.2, 3), 3)
				end
				task.wait(0.4)
			end
		end
	end)
end

function StanAbilities.SpawnTrailPart(cframe, size, poisonDuration)
	local part = Instance.new("Part")
	part.Name = "CorruptionTrail"
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(40, 0, 50)
	part.Transparency = 0.3
	part.Parent = workspace

	part.Touched:Connect(function(otherPart)
		local toonChar = otherPart.Parent
		if not toonChar then return end
		local stats = StatsModule.GetStats(toonChar)
		if stats then
			local role = stats:FindFirstChild("Role")
			if role and role.Value == StatsModule.Role.Toonflow then
				applyStatusEffect(toonChar, "Poison", poisonDuration or 3)
			end
		end
	end)

	Debris:AddItem(part, 6)
end

---------------------------------------------------------
-- M1 ADAPTATIVO (Cuerpo a Cuerpo / Taser Laser)
---------------------------------------------------------
function StanAbilities.ExecuteM1(character, targetCFrame)
	local isLaserMode = character:GetAttribute("LaserModeActive") or false

	if isLaserMode then
		task.wait(1) -- 1 segundo de carga/retraso

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local rayOrigin = hrp.Position
		local rayDirection = hrp.CFrame.LookVector * 60
		local raycastParams = RaycastParams.new()
		raycastParams.FilterDescendantsInstances = {character}
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude

		local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		if result and result.Instance then
			local hitChar = result.Instance.Parent
			local hum = hitChar and hitChar:FindFirstChildOfClass("Humanoid")
			if hum then
				local origin = hrp.Position + Vector3.new(0, 1, 0)
				VFXModule.SpawnProjectileVFX(origin, result.Position, STAN_COLOR)
				StatsModule.ApplyDamage(hitChar, 15)

				local effects = {"Slowness", "Burn", "Corruption"}
				local randomEffect = effects[math.random(1, #effects)]
				applyStatusEffect(hitChar, randomEffect, 1)
			end
		end
	else
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		for _, target in ipairs(workspace:GetChildren()) do
			if target ~= character and target:FindFirstChildOfClass("Humanoid") then
				local targetHrp = target:FindFirstChild("HumanoidRootPart")
				if targetHrp then
					local dist = (targetHrp.Position - hrp.Position).Magnitude
					if dist <= 7 then
						VFXModule.SpawnMeleeHitVFX(targetHrp.Position, STAN_COLOR)
						StatsModule.ApplyDamage(target, 22)
						if math.random() <= 0.3 then
							applyStatusEffect(target, "Burn", 1)
						end
					end
				end
			end
		end
	end
end

---------------------------------------------------------
-- HABILIDAD 1: RAYO CORRUPTO
---------------------------------------------------------
AbilityFramework.Register({
	Name = "RayoCorrupto",
	Description = "Stan dispara un rayo corrupto. 30 dmg + lanza Pop-ups en la pantalla del Toonflow por 5s.",
	MaxCharges = 1,
	Cooldown = 18,
	CostType = nil,
	CostAmount = 0,
	CastTime = 1,
	Range = 80,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		local targetData = params.TargetData
		if not (character and player) then return false, "NoCharacter" end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		task.wait(1)

		if not (character and character.Parent) then return end

		local targetPosition
		if typeof(targetData) == "Vector3" then
			targetPosition = targetData
		else
			targetPosition = hrp.Position + hrp.CFrame.LookVector * 80
		end

		local direction = (targetPosition - hrp.Position).Unit
		local raycastParams = RaycastParams.new()
		raycastParams.FilterDescendantsInstances = {character}
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude

		local result = workspace:Raycast(hrp.Position, direction * 80, raycastParams)

		local endPoint = result and result.Position or (hrp.Position + direction * 80)
		local origin = hrp.Position + Vector3.new(0, 1, 0)
		VFXModule.SpawnProjectileVFX(origin, endPoint, STAN_COLOR)
		VFXModule.PlaySound3D(hrp, VFXModule.Sounds.Plasma, 0.6)

		if result and result.Instance then
			local toonChar = result.Instance.Parent
			local hum = toonChar and toonChar:FindFirstChildOfClass("Humanoid")
			local targetPlayer = Players:GetPlayerFromCharacter(toonChar)

			if hum and targetPlayer then
				StatsModule.ApplyDamage(toonChar, 30)
				VFXModule.SpawnMeleeHitVFX(result.Position, STAN_COLOR)

				if PopupRemote then
					PopupRemote:FireClient(targetPlayer, 5)
				end

				print("[Stan] RayoCorrupto impacto a " .. toonChar.Name .. " (30 dmg + Pop-ups 5s)")
			end
		end
	end,
})

---------------------------------------------------------
-- HABILIDAD 2: BETTER CALL STAN
---------------------------------------------------------
AbilityFramework.Register({
	Name = "BetterCallStan",
	Description = "Stan invoca 2 clones que persiguen y envenenan Toonflows. CD: 40s",
	MaxCharges = 1,
	Cooldown = 40,
	CostType = nil,
	CostAmount = 0,
	CastTime = 0,
	Range = 0,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		if not (character and player) then return false, "NoCharacter" end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		local bc = getBotController()
		if not bc then
			warn("[Stan] BotController no encontrado, no se pueden invocar clones.")
			return
		end

		VFXModule.PlaySound3D(hrp, VFXModule.Sounds.Buff, 0.7)

		for i = 1, 2 do
			local offset = Vector3.new((i == 1 and 4 or -4), 0, 2)
			local cloneCFrame = hrp.CFrame * CFrame.new(offset)

			local cloneBot = bc.SpawnBot(StatsModule.Role.Devilish, cloneCFrame, "StanClone_" .. i)
			if cloneBot then
				cloneBot:SetAttribute("IsClone", true)

				local hl = Instance.new("Highlight")
				hl.Name = "CloneHighlight"
				hl.FillColor = STAN_COLOR
				hl.OutlineColor = Color3.fromRGB(120, 0, 150)
				hl.FillTransparency = 0.3
				hl.OutlineTransparency = 0
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				hl.Parent = cloneBot

				local cloneHrp = cloneBot:FindFirstChild("HumanoidRootPart")
				if cloneHrp then
					local hitDebounce = false
					cloneHrp.Touched:Connect(function(hit)
						if hitDebounce then return end
						local toonChar = hit.Parent
						if not toonChar then return end
						local stats = StatsModule.GetStats(toonChar)
						if stats then
							local role = stats:FindFirstChild("Role")
							if role and role.Value == StatsModule.Role.Toonflow then
								hitDebounce = true
								StatsModule.ApplyDamage(toonChar, 17)
								applyStatusEffect(toonChar, "Poison", 5)
								revealAura(toonChar, character, 4)

								local hitHrp = toonChar:FindFirstChild("HumanoidRootPart")
								if hitHrp then
									VFXModule.SpawnMeleeHitVFX(hitHrp.Position, STAN_COLOR)
								end

								task.wait(0.1)
								cloneBot.Parent = nil
							end
						end
					end)
				end

				Debris:AddItem(cloneBot, 15)
			end
		end

		print("[Stan] BetterCallStan: 2 clones invocados por " .. player.Name)
	end,
})

---------------------------------------------------------
-- HABILIDAD 3: CORRUPCION GRAVE DE CARTUCHO (TRAMPA)
---------------------------------------------------------
AbilityFramework.Register({
	Name = "CorrupcionGrave",
	Description = "Stan reduce su velocidad y deja un rastro de veneno ampliado por 8s. CD: 30s",
	MaxCharges = 1,
	Cooldown = 30,
	CostType = nil,
	CostAmount = 0,
	CastTime = 0,
	Range = 0,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		if not (character and player) then return false, "NoCharacter" end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		StatsModule.SetSpeedMultiplier(character, 0.5)

		VFXModule.PlaySound3D(hrp, VFXModule.Sounds.Buff, 0.6)
		local hl = Instance.new("Highlight")
		hl.Name = "CorrupcionGraveVFX"
		hl.FillColor = STAN_COLOR
		hl.OutlineColor = Color3.fromRGB(120, 0, 150)
		hl.FillTransparency = 0.3
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = character
		Debris:AddItem(hl, 8)

		local duration = 8
		local elapsed = 0

		task.spawn(function()
			while elapsed < duration and character and character.Parent do
				local currentHrp = character:FindFirstChild("HumanoidRootPart")
				if currentHrp then
					StanAbilities.SpawnTrailPart(currentHrp.CFrame - Vector3.new(0, 2, 0), Vector3.new(6, 0.2, 6), 5)
				end
				task.wait(0.3)
				elapsed = elapsed + 0.3
			end

			if character and character.Parent then
				StatsModule.ResetSpeedMultiplier(character)
			end
		end)

		print("[Stan] CorrupcionGrave activada por " .. player.Name .. " (8s de rastro de veneno)")
	end,
})

---------------------------------------------------------
-- HABILIDAD 4: CAMBIO (MODO ARMA LASER)
---------------------------------------------------------
AbilityFramework.Register({
	Name = "CambioArma",
	Description = "Stan alterna entre M1 melee y M1 laser (Taser). CD: 10s",
	MaxCharges = 1,
	Cooldown = 10,
	CostType = nil,
	CostAmount = 0,
	CastTime = 0,
	Range = 0,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		if not (character and player) then return false, "NoCharacter" end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		local currentMode = character:GetAttribute("LaserModeActive") or false
		local newMode = not currentMode
		character:SetAttribute("LaserModeActive", newMode)

		VFXModule.PlaySound3D(hrp, VFXModule.Sounds.Buff, 0.5)
		local hl = Instance.new("Highlight")
		hl.Name = "CambioArmaVFX"
		hl.FillColor = newMode and Color3.fromRGB(255, 0, 0) or STAN_COLOR
		hl.OutlineColor = Color3.fromRGB(255, 255, 255)
		hl.FillTransparency = 0.3
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = character
		Debris:AddItem(hl, 1.5)

		print("[Stan] CambioArma: modo " .. (newMode and "LASER" or "MELEE") .. " activado por " .. player.Name)
	end,
})

return StanAbilities