--[[
	TobyAbilities (ModuleScript)
	Ubicacion: ServerScriptService.ServerModules.TobyAbilities

	Define las 3 habilidades + pasiva del personaje TOONFLOW "Toby Williams":
	  PASIVA: "Amistacion" -> Curacion de 30 HP al conectar Bara Normal + Bara Fantasma seguidas
	  1. "YaLevantate"      -> Patineta trampa que stunea al Devilish (Cooldown: 39s)
	  2. "BaraNormal"       -> Melee con palo: lentitud 0.5x por 5s + empuje (Cooldown: 10s)
	  2b."BaraFantasma"     -> Melee fantasmal: stun 3s o auto-lentitud 0.2x por 2s (Cooldown: 37s)
	  3. "RayosLaserToby"   -> Canalizacion 3s + rayo con lentitud 0.5x + ceguera 3s (Cooldown: 40s)

	Dependencias:
	  - ServerScriptService.ServerModules.AbilityFramework
	  - ServerScriptService.ServerModules.StatsModule
	  - ReplicatedStorage.Framework.VFXModule
]]

local AbilityFramework = require(game:GetService("ServerScriptService").ServerModules.AbilityFramework)
local StatsModule = require(game:GetService("ServerScriptService").ServerModules.StatsModule)
local VFXModule = require(game.ReplicatedStorage.Framework.VFXModule)

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

-- == ESTADO DE LA PASIVA "AMISTACION" ==
local amistacionState = {}

local function registerAmistacionHit(player, character, hitType)
	if not (player and character) then return end

	local state = amistacionState[player]
	if not state then
		state = { lastHit = nil }
		amistacionState[player] = state
	end

	if hitType == "BaraNormal" then
		state.lastHit = "BaraNormal"
		print("[Toby] Amistacion: Bara Normal conectada.")
	elseif hitType == "BaraFantasma" then
		if state.lastHit == "BaraNormal" then
			print("[Toby] AMISTACION activada! Curando 30 HP.")
			StatsModule.ApplyHeal(character, 30)
			VFXModule.SpawnAmistacionVFX(character, 2)
			state.lastHit = nil
		else
			state.lastHit = "BaraFantasma"
			print("[Toby] Amistacion: Bara Fantasma conectada (esperando Bara Normal).")
		end
	end
end

local function resetAmistacion(player)
	if amistacionState[player] then
		amistacionState[player].lastHit = nil
		print("[Toby] Amistacion reseteada por fallo.")
	end
end

local TobyAbilities = {}
TobyAbilities.RegisterAmistacionHit = registerAmistacionHit
TobyAbilities.ResetAmistacion = resetAmistacion

-- == HABILIDAD 1: YA LEVANTATE (Patineta Trampa) ==
AbilityFramework.Register({
	Name = "YaLevantate",
	Description = "Toby lanza una patineta trampa. Si el Devilish la pisa, queda stuneado 2.5s.",
	MaxCharges = 1,
	Cooldown = 39,
	CostType = nil,
	CostAmount = 0,
	CastTime = 0,
	Range = 30,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		local targetData = params.TargetData
		if not (character and player) then return false, "NoCharacter" end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		local placePosition
		if typeof(targetData) == "Vector3" then
			local maxRange = params.AbilityDef.Range
			local distance = (targetData - hrp.Position).Magnitude
			if distance > maxRange then
				placePosition = hrp.Position + hrp.CFrame.LookVector * maxRange
			else
				placePosition = targetData
			end
		else
			placePosition = hrp.Position + hrp.CFrame.LookVector * 15
		end

		local skateboard = Instance.new("Part")
		skateboard.Name = "YaLevantate_Trap"
		skateboard.Size = Vector3.new(6, 0.5, 2)
		skateboard.CFrame = CFrame.new(placePosition + Vector3.new(0, 0.5, 0))
		skateboard.Anchored = true
		skateboard.CanCollide = false
		skateboard.CanQuery = false
		skateboard.Material = Enum.Material.SmoothPlastic
		skateboard.Color = Color3.fromRGB(50, 150, 255)
		skateboard.Transparency = 0.3
		skateboard.Parent = workspace

		task.delay(0.5, function()
			if skateboard and skateboard.Parent then
				TweenService:Create(skateboard, TweenInfo.new(0.5), { Transparency = 0.7 }):Play()
			end
		end)

		local particleAtt = Instance.new("Attachment")
		particleAtt.Name = "ParticleAtt"
		particleAtt.Parent = skateboard

		local particles = Instance.new("ParticleEmitter")
		particles.Name = "TrapParticles"
		particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		particles.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 255, 100)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 150, 255)),
		})
		particles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 0),
		})
		particles.Lifetime = NumberRange.new(0.5)
		particles.Rate = 15
		particles.Speed = NumberRange.new(0.5, 1)
		particles.SpreadAngle = Vector2.new(180, 180)
		particles.Parent = particleAtt

		VFXModule.PlaySound3D(skateboard, VFXModule.Sounds.Buff, 0.4)

		local detectionRadius = 5
		local trapTriggered = false
		local trapDestroyed = false

		task.spawn(function()
			while skateboard and skateboard.Parent and not trapTriggered and not trapDestroyed do
				task.wait(0.2)

				for _, otherPlayer in ipairs(game:GetService("Players"):GetPlayers()) do
					local otherChar = otherPlayer.Character
					if otherChar and otherChar ~= character then
						local otherHrp = otherChar:FindFirstChild("HumanoidRootPart")
						local otherStats = StatsModule.GetStats(otherChar)
						if otherHrp and otherStats then
							local otherRole = otherStats:FindFirstChild("Role")
							if otherRole and otherRole.Value == StatsModule.Role.Devilish then
								local distance = (otherHrp.Position - skateboard.Position).Magnitude
								if distance <= detectionRadius then
									trapTriggered = true
									break
								end
							end
						end
					end
				end
			end
		end)

		skateboard.Touched:Connect(function(hitPart)
			if trapTriggered or trapDestroyed then return end

			local hitChar = hitPart.Parent
			if not hitChar or hitChar == character then return end

			local hitStats = StatsModule.GetStats(hitChar)
			if hitStats then
				local hitRole = hitStats:FindFirstChild("Role")
				if hitRole and hitRole.Value == StatsModule.Role.Devilish then
					trapTriggered = true
				end
			end
		end)

		task.spawn(function()
			while skateboard and skateboard.Parent and not trapTriggered and not trapDestroyed do
				task.wait(0.1)
			end

			if trapTriggered and skateboard and skateboard.Parent then
				local closestDevilish = nil
				local closestDistance = math.huge

				for _, otherPlayer in ipairs(game:GetService("Players"):GetPlayers()) do
					local otherChar = otherPlayer.Character
					if otherChar and otherChar ~= character then
						local otherHrp = otherChar:FindFirstChild("HumanoidRootPart")
						local otherStats = StatsModule.GetStats(otherChar)
						if otherHrp and otherStats then
							local otherRole = otherStats:FindFirstChild("Role")
							if otherRole and otherRole.Value == StatsModule.Role.Devilish then
								local dist = (otherHrp.Position - skateboard.Position).Magnitude
								if dist < closestDistance then
									closestDistance = dist
									closestDevilish = otherChar
								end
							end
						end
					end
				end

				if closestDevilish then
					StatsModule.SetState(closestDevilish, StatsModule.CharacterState.Stunned)
					VFXModule.SpawnStunVFX(skateboard.Position, 0.5)

					print("[Toby] YaLevantate activada! Devilish stuneado por 2.5s.")

					task.delay(2.5, function()
						if closestDevilish and closestDevilish.Parent then
							StatsModule.SetState(closestDevilish, StatsModule.CharacterState.Normal)
						end
					end)
				end

				skateboard:Destroy()
			end
		end)

		Debris:AddItem(skateboard, 30)
		print("[Toby] YaLevantate colocada por " .. player.Name)
	end,
})

-- == HABILIDAD 2: BARA NORMAL (Melee con palo) ==
AbilityFramework.Register({
	Name = "BaraNormal",
	Description = "Toby golpea con su palo: lentitud 0.5x por 5s + empuje al Devilish.",
	MaxCharges = 1,
	Cooldown = 10,
	CostType = nil,
	CostAmount = 0,
	CastTime = 0,
	Range = 8,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		local targetData = params.TargetData
		if not (character and player) then return false, "NoCharacter" end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		local direction = (typeof(targetData) == "Vector3") and (targetData - hrp.Position).Unit or hrp.CFrame.LookVector
		local maxRange = params.AbilityDef.Range

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {character}

		local rayResult = workspace:Raycast(hrp.Position, direction * maxRange, rayParams)
		local swingEnd = hrp.Position + direction * maxRange
		VFXModule.SpawnMeleeSwingVFX(hrp.Position, swingEnd, Color3.fromRGB(100, 200, 255))

		local hitDevilish = false

		if rayResult and rayResult.Instance then
			local hitChar = rayResult.Instance.Parent
			if hitChar then
				local hitStats = StatsModule.GetStats(hitChar)
				if hitStats then
					local hitRole = hitStats:FindFirstChild("Role")
					if hitRole and hitRole.Value == StatsModule.Role.Devilish then
						hitDevilish = true

						local hitHrp = hitChar:FindFirstChild("HumanoidRootPart")
						StatsModule.SetSpeedMultiplier(hitChar, 0.5)
						task.delay(5, function()
							if hitChar and hitChar.Parent then
								StatsModule.ResetSpeedMultiplier(hitChar)
							end
						end)

						if hitHrp then
							hitHrp.AssemblyLinearVelocity = direction * 40 + Vector3.new(0, 15, 0)
						end

						VFXModule.SpawnMeleeHitVFX(rayResult.Position, Color3.fromRGB(100, 200, 255))
						registerAmistacionHit(player, character, "BaraNormal")

						print("[Toby] BaraNormal impacto a Devilish: " .. hitChar.Name)
					end
				end
			end
		end

		if not hitDevilish then
			resetAmistacion(player)
		end

		print("[Toby] BaraNormal usada por " .. player.Name)
	end,
})

-- == HABILIDAD 2b: BARA FANTASMA (Melee fantasmal) ==
AbilityFramework.Register({
	Name = "BaraFantasma",
	Description = "Toby golpea fantasmalmente: stunea 3s al Devilish. Si fallas, lentitud 0.2x por 2s.",
	MaxCharges = 1,
	Cooldown = 37,
	CostType = nil,
	CostAmount = 0,
	CastTime = 0,
	Range = 10,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		local targetData = params.TargetData
		if not (character and player) then return false, "NoCharacter" end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		local direction = (typeof(targetData) == "Vector3") and (targetData - hrp.Position).Unit or hrp.CFrame.LookVector
		local maxRange = params.AbilityDef.Range

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {character}

		local rayResult = workspace:Raycast(hrp.Position, direction * maxRange, rayParams)
		local swingEnd = hrp.Position + direction * maxRange
		VFXModule.SpawnMeleeSwingVFX(hrp.Position, swingEnd, Color3.fromRGB(150, 100, 255))

		local hitDevilish = false

		if rayResult and rayResult.Instance then
			local hitChar = rayResult.Instance.Parent
			if hitChar then
				local hitStats = StatsModule.GetStats(hitChar)
				if hitStats then
					local hitRole = hitStats:FindFirstChild("Role")
					if hitRole and hitRole.Value == StatsModule.Role.Devilish then
						hitDevilish = true

						StatsModule.SetState(hitChar, StatsModule.CharacterState.Stunned)
						task.delay(3, function()
							if hitChar and hitChar.Parent then
								StatsModule.SetState(hitChar, StatsModule.CharacterState.Normal)
							end
						end)

						VFXModule.SpawnMeleeHitVFX(rayResult.Position, Color3.fromRGB(150, 100, 255))
						registerAmistacionHit(player, character, "BaraFantasma")

						print("[Toby] BaraFantasma impacto a Devilish: " .. hitChar.Name)
					end
				end
			end
		end

		if not hitDevilish then
			StatsModule.SetSpeedMultiplier(character, 0.2)
			VFXModule.SpawnStunVFX(hrp.Position, 0.5)

			task.delay(2, function()
				if character and character.Parent then
					StatsModule.ResetSpeedMultiplier(character)
				end
			end)

			resetAmistacion(player)
			print("[Toby] BaraFantasma FALLO. Toby recibe lentitud 0.2x por 2s.")
		end

		print("[Toby] BaraFantasma usada por " .. player.Name)
	end,
})

-- == HABILIDAD 3: RAYOS LASER (Canalizacion + Rayo) ==
AbilityFramework.Register({
	Name = "RayosLaserToby",
	Description = "Toby canaliza 3s y dispara un rayo: lentitud 0.5x por 5s + ceguera 3s al Devilish.",
	MaxCharges = 1,
	Cooldown = 40,
	CostType = nil,
	CostAmount = 0,
	CastTime = 3,
	Range = 80,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		local targetData = params.TargetData
		if not (character and player) then return false, "NoCharacter" end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		StatsModule.SetSpeedMultiplier(character, 0.3)
		VFXModule.SpawnChannelVFX(character, 3)

		task.delay(3, function()
			if not (character and character.Parent) then return end

			StatsModule.ResetSpeedMultiplier(character)

			local direction = (typeof(targetData) == "Vector3") and (targetData - hrp.Position).Unit or hrp.CFrame.LookVector
			local maxRange = params.AbilityDef.Range

			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = {character}

			local rayResult = workspace:Raycast(hrp.Position, direction * maxRange, rayParams)
			local origin = hrp.Position
			local endPoint = rayResult and rayResult.Position or (origin + direction * maxRange)

			VFXModule.SpawnProjectileVFX(origin, endPoint, Color3.fromRGB(50, 100, 255))
			VFXModule.SpawnProjectileVFX(origin, endPoint, Color3.fromRGB(255, 50, 50))

			if rayResult and rayResult.Instance then
				local hitChar = rayResult.Instance.Parent
				if hitChar then
					local hitStats = StatsModule.GetStats(hitChar)
					if hitStats then
						local hitRole = hitStats:FindFirstChild("Role")
						if hitRole and hitRole.Value == StatsModule.Role.Devilish then
							StatsModule.SetSpeedMultiplier(hitChar, 0.5)
							task.delay(5, function()
								if hitChar and hitChar.Parent then
									StatsModule.ResetSpeedMultiplier(hitChar)
								end
							end)

							local blindRemote = game.ReplicatedStorage.Framework.Remotes:FindFirstChild("BlindEffect")
							if blindRemote then
								local hitPlayer = game:GetService("Players"):GetPlayerFromCharacter(hitChar)
								if hitPlayer then
									blindRemote:FireClient(hitPlayer, 3)
								end
							end

							print("[Toby] RayosLaserToby impacto a Devilish: " .. hitChar.Name)
						end
					end
				end
			end

			print("[Toby] RayosLaserToby disparado por " .. player.Name)
		end)
	end,
})

return TobyAbilities