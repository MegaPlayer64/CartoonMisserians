--[[
	NeuroAbilities (ModuleScript)
	Ubicacion: ServerScriptService.ServerModules.NeuroAbilities

	Define las 3 habilidades del personaje DEVILISH "Neuro" (Lincoln Loud alterado):
	  1. "CallOfStardoom"  -> Eleva/hover 2s, revela Toonflows cercanos, embiste. 20/30 dmg + 10/20 AoE. CD: 21s
	  2. "LightsAndAction"  -> Proyectil plasma hacia cursor. 35/40 dmg + BlindEffect 3s. CD: 35s
	  3. "LastShow"         -> Requiere Fame >= 25. Carga/dash arrastra Toonflow. 24-40 dmg. CD: 60s

	PASIVA: "Fame Audience"
	  - M1 Exitoso: +10 Fame | M1 Fallido: -2 Fame
	  - Fame >= 45: SpeedMultiplier 1.25 | Baja de 45: restaura 1.0
	  - Fame >= 50: habilidades con valores potenciados

	Las animaciones definitivas se vincularan cuando los Rigs esten listos.
	Por ahora se usan placeholders visuales/sonoros via VFXModule.

	Dependencias:
	  - ServerScriptService.ServerModules.AbilityFramework
	  - ServerScriptService.ServerModules.StatsModule
	  - ReplicatedStorage.Framework.VFXModule
]]

local AbilityFramework = require(game:GetService("ServerScriptService").ServerModules.AbilityFramework)
local StatsModule = require(game:GetService("ServerScriptService").ServerModules.StatsModule)
local VFXModule = require(game.ReplicatedStorage.Framework.VFXModule)

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local NeuroAbilities = {}

-- == HABILIDAD 1: CALL OF STARDOOM (Hover + Reveal + Dash) ==
-- Tipo: Mobility / Reveal / Dash Attack
-- Rol: Devilish (Neuro)
-- Cooldown: 21 segundos
-- Mecanica:
--   1. Neuro se eleva/hover durante 2s (revela siluetas de Toonflows cercanos)
--   2. Embiste en la direccion elegida (hacia cursor)
--   3. Impacto: 20 dmg (30 si Fame>=50) + 10 AoE (20 si Fame>=50)
--   4. Exito: +15 Fame | Fallo (no impacta a nadie): -15 Fame
AbilityFramework.Register({
	Name = "CallOfStardoom",
	Description = "Neuro se eleva, revela Toonflows cercanos 2s y embiste. 20/30 dmg + 10/20 AoE. +15 Fame / -15 Fame.",
	MaxCharges = 1,
	Cooldown = 21,
	CostType = nil,
	CostAmount = 0,
	CastTime = 2,
	Range = 35,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		local targetData = params.TargetData
		if not (character and player) then return false, "NoCharacter" end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		local fame = StatsModule.GetFame(character)
		local isEmpowered = fame >= 50
		local directDamage = isEmpowered and 30 or 20
		local aoeDamage = isEmpowered and 20 or 10
		local revealDuration = 2
		local revealRadius = 40

		-- VFX: Hover + anillo de energia
		VFXModule.SpawnStardoomVFX(character, revealDuration)

		-- == REVELAR TOONFLOWS CERCANOS ==
		local revealedTargets = {}
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			local otherChar = otherPlayer.Character
			if otherChar and otherChar ~= character then
				local otherHrp = otherChar:FindFirstChild("HumanoidRootPart")
				local otherStats = StatsModule.GetStats(otherChar)
				if otherHrp and otherStats then
					local otherRole = otherStats:FindFirstChild("Role")
					local otherAlive = otherStats:FindFirstChild("IsAlive")
					if otherRole and otherRole.Value == StatsModule.Role.Toonflow
						and otherAlive and otherAlive.Value then
						local distance = (otherHrp.Position - hrp.Position).Magnitude
						if distance <= revealRadius then
							VFXModule.SpawnRevealVFX(otherChar, revealDuration)
							table.insert(revealedTargets, otherChar)
						end
					end
				end
			end
		end

		-- == ESPERAR 2s DE HOVER/REVEAL ==
		task.delay(revealDuration, function()
			if not (character and character.Parent) then return end

			-- Determinar direccion del dash (hacia cursor o forward)
			local dashDirection
			if typeof(targetData) == "Vector3" then
				dashDirection = (targetData - hrp.Position).Unit
			else
				dashDirection = hrp.CFrame.LookVector
			end

			local dashDistance = params.AbilityDef.Range
			local dashDestination = hrp.Position + dashDirection * dashDistance

			-- == EMBESTIDA (DASH) ==
			-- Mover a Neuro rapidamente hacia la direccion
			local dashStartPos = hrp.Position
			local dashElapsed = 0
			local dashDuration = 0.3
			local hitSomeone = false

			-- Trail visual del dash
			local trailAtt0 = Instance.new("Attachment")
			trailAtt0.Position = Vector3.new(-1, 0, 0)
			trailAtt0.Parent = hrp
			local trailAtt1 = Instance.new("Attachment")
			trailAtt1.Position = Vector3.new(1, 0, 0)
			trailAtt1.Parent = hrp

			local trail = Instance.new("Trail")
			trail.Attachment0 = trailAtt0
			trail.Attachment1 = trailAtt1
			trail.Lifetime = 0.3
			trail.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 150, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
			})
			trail.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
			trail.Parent = hrp

			task.spawn(function()
				while dashElapsed < dashDuration do
					task.wait()
					dashElapsed = dashElapsed + task.wait()

					if not (character and character.Parent and hrp and hrp.Parent) then break end

					local progress = dashElapsed / dashDuration
					local newPos = dashStartPos:Lerp(dashDestination, progress)
					hrp.CFrame = CFrame.new(newPos) * CFrame.Angles(0, math.atan2(-dashDirection.X, -dashDirection.Z), 0)

					-- Verificar colision con Toonflows durante el dash
					for _, otherPlayer in ipairs(Players:GetPlayers()) do
						local otherChar = otherPlayer.Character
						if otherChar and otherChar ~= character then
							local otherHrp = otherChar:FindFirstChild("HumanoidRootPart")
							local otherStats = StatsModule.GetStats(otherChar)
							if otherHrp and otherStats then
								local otherRole = otherStats:FindFirstChild("Role")
								local otherAlive = otherStats:FindFirstChild("IsAlive")
								if otherRole and otherRole.Value == StatsModule.Role.Toonflow
									and otherAlive and otherAlive.Value then
									local distance = (otherHrp.Position - hrp.Position).Magnitude
									if distance <= 5 then
										-- Impacto directo
										StatsModule.ApplyDamage(otherChar, directDamage)
										VFXModule.SpawnMeleeHitVFX(otherHrp.Position, Color3.fromRGB(200, 150, 255))
										hitSomeone = true

										-- AoE alrededor del impacto
										for _, aoePlayer in ipairs(Players:GetPlayers()) do
											local aoeChar = aoePlayer.Character
											if aoeChar and aoeChar ~= character and aoeChar ~= otherChar then
												local aoeHrp = aoeChar:FindFirstChild("HumanoidRootPart")
												local aoeStats = StatsModule.GetStats(aoeChar)
												if aoeHrp and aoeStats then
													local aoeRole = aoeStats:FindFirstChild("Role")
													local aoeAlive = aoeStats:FindFirstChild("IsAlive")
													if aoeRole and aoeRole.Value == StatsModule.Role.Toonflow
														and aoeAlive and aoeAlive.Value then
														local aoeDist = (aoeHrp.Position - otherHrp.Position).Magnitude
														if aoeDist <= 10 then
															StatsModule.ApplyDamage(aoeChar, aoeDamage)
														end
													end
												end
											end
										end
									end
								end
							end
						end
					end
				end

				-- Limpiar trail
				trail.Enabled = false
				Debris:AddItem(trailAtt0, 1)
				Debris:AddItem(trailAtt1, 1)
				Debris:AddItem(trail, 1)

				-- == FAME ADJUSTMENT ==
				if hitSomeone then
					StatsModule.AddFame(character, 15)
					print("[Neuro] CallOfStardoom impacto! +15 Fame")
				else
					StatsModule.AddFame(character, -15)
					print("[Neuro] CallOfStardoom fallo. -15 Fame")
				end
			end)
		end)

		print("[Neuro] CallOfStardoom activado por " .. player.Name .. " (Fame: " .. fame .. ", Empowered: " .. tostring(isEmpowered) .. ")")
	end,
})

-- == HABILIDAD 2: LIGHTS AND ACTION (Proyectil plasma + Blind) ==
-- Tipo: Skillshot Projectile
-- Rol: Devilish (Neuro)
-- Cooldown: 35 segundos
-- Mecanica:
--   1. Neuro dispara un proyectil de plasma hacia la posicion del cursor
--   2. Impacto: 35 dmg (40 si Fame>=50)
--   3. Exito: +20 Fame y dispara BlindEffect 3s al Toonflow impactado
--   4. Fallo (no impacta): -30 Fame
AbilityFramework.Register({
	Name = "LightsAndAction",
	Description = "Neuro dispara plasma hacia el cursor. 35/40 dmg + BlindEffect 3s. +20 Fame / -30 Fame.",
	MaxCharges = 1,
	Cooldown = 35,
	CostType = nil,
	CostAmount = 0,
	CastTime = 0,
	Range = 60,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		local targetData = params.TargetData
		if not (character and player) then return false, "NoCharacter" end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		local fame = StatsModule.GetFame(character)
		local isEmpowered = fame >= 50
		local damage = isEmpowered and 40 or 35

		-- Determinar posicion objetivo (cursor o forward)
		local targetPosition
		if typeof(targetData) == "Vector3" then
			targetPosition = targetData
		else
			targetPosition = hrp.Position + hrp.CFrame.LookVector * 60
		end

		local origin = hrp.Position + hrp.CFrame.UpVector * 2

		-- VFX: Proyectil de plasma
		VFXModule.SpawnPlasmaProjectileVFX(origin, targetPosition)

		-- == DETECCION DE IMPACTO ==
		-- Verificar Toonflows cercanos al punto de impacto
		task.delay(0.5, function()
			if not (character and character.Parent) then return end

			local hitRadius = 6
			local hitSomeone = false

			for _, otherPlayer in ipairs(Players:GetPlayers()) do
				local otherChar = otherPlayer.Character
				if otherChar and otherChar ~= character then
					local otherHrp = otherChar:FindFirstChild("HumanoidRootPart")
					local otherStats = StatsModule.GetStats(otherChar)
					if otherHrp and otherStats then
						local otherRole = otherStats:FindFirstChild("Role")
						local otherAlive = otherStats:FindFirstChild("IsAlive")
						if otherRole and otherRole.Value == StatsModule.Role.Toonflow
							and otherAlive and otherAlive.Value then
							local distance = (otherHrp.Position - targetPosition).Magnitude
							if distance <= hitRadius then
								-- Impacto!
								StatsModule.ApplyDamage(otherChar, damage)
								VFXModule.SpawnMeleeHitVFX(otherHrp.Position, Color3.fromRGB(200, 150, 255))
								hitSomeone = true

								-- Disparar BlindEffect al Toonflow impactado
								local blindRemote = game.ReplicatedStorage.Framework.Remotes:FindFirstChild("BlindEffect")
								if blindRemote then
									blindRemote:FireClient(otherPlayer, 3)
								end

								print("[Neuro] LightsAndAction impacto a " .. otherChar.Name .. " (" .. damage .. " dmg, Blind 3s)")
							end
						end
					end
				end
			end

			-- == FAME ADJUSTMENT ==
			if hitSomeone then
				StatsModule.AddFame(character, 20)
				print("[Neuro] LightsAndAction exito! +20 Fame")
			else
				StatsModule.AddFame(character, -30)
				print("[Neuro] LightsAndAction fallo. -30 Fame")
			end
		end)

		print("[Neuro] LightsAndAction activado por " .. player.Name .. " (Fame: " .. fame .. ", Empowered: " .. tostring(isEmpowered) .. ")")
	end,
})

-- == HABILIDAD 3: LAST SHOW (Carga + Dash arrastrando) ==
-- Tipo: Charge + Grab + Dash
-- Rol: Devilish (Neuro)
-- Cooldown: 60 segundos
-- Mecanica:
--   1. Requiere Fame >= 25 (CustomCheck en AbilityServer)
--   2. Neuro carga 1.5s (inmovil)
--   3. Dash hacia adelante, arrastra al primer Toonflow que toca
--   4. Si impacta contra pared: 30 dmg (40 si Fame>=50)
--   5. Sin pared: 24 dmg (35 si Fame>=50)
AbilityFramework.Register({
	Name = "LastShow",
	Description = "Neuro carga y embiste arrastrando a un Toonflow. Contra pared: 30/40 dmg. Sin pared: 24/35 dmg. Requiere Fame >= 25.",
	MaxCharges = 1,
	Cooldown = 60,
	CostType = nil,
	CostAmount = 0,
	CastTime = 1.5,
	Range = 50,

	-- CustomCheck: verifica Fame >= 25 antes de permitir el uso
	CustomCheck = function(player, character)
		local fame = StatsModule.GetFame(character)
		if fame < 25 then
			return false, "InsufficientFame"
		end
		return true, "OK"
	end,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		local targetData = params.TargetData
		if not (character and player) then return false, "NoCharacter" end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		local fame = StatsModule.GetFame(character)
		local isEmpowered = fame >= 50
		local wallDamage = isEmpowered and 40 or 30
		local noWallDamage = isEmpowered and 35 or 24
		local chargeDuration = 1.5

		-- Inmovilizar durante la carga
		StatsModule.SetSpeedMultiplier(character, 0.0)

		-- VFX: Carga
		VFXModule.SpawnLastShowVFX(character, chargeDuration)

		task.delay(chargeDuration, function()
			if not (character and character.Parent) then return end

			-- Restaurar velocidad
			StatsModule.ResetSpeedMultiplier(character)

			-- Determinar direccion del dash
			local dashDirection
			if typeof(targetData) == "Vector3" then
				dashDirection = (targetData - hrp.Position).Unit
			else
				dashDirection = hrp.CFrame.LookVector
			end

			local dashDistance = params.AbilityDef.Range
			local dashDestination = hrp.Position + dashDirection * dashDistance
			local dashStartPos = hrp.Position
			local dashElapsed = 0
			local dashDuration = 0.5
			local grabbedTarget = nil
			local hitWall = false

			-- Trail del dash
			local trailAtt0 = Instance.new("Attachment")
			trailAtt0.Position = Vector3.new(-1, 0, 0)
			trailAtt0.Parent = hrp
			local trailAtt1 = Instance.new("Attachment")
			trailAtt1.Position = Vector3.new(1, 0, 0)
			trailAtt1.Parent = hrp

			local trail = Instance.new("Trail")
			trail.Attachment0 = trailAtt0
			trail.Attachment1 = trailAtt1
			trail.Lifetime = 0.4
			trail.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 100, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
			})
			trail.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
			trail.Parent = hrp

			task.spawn(function()
				while dashElapsed < dashDuration do
					local step = task.wait()
					dashElapsed = dashElapsed + step

					if not (character and character.Parent and hrp and hrp.Parent) then break end

					local progress = math.min(dashElapsed / dashDuration, 1)
					local newPos = dashStartPos:Lerp(dashDestination, progress)
					hrp.CFrame = CFrame.new(newPos) * CFrame.Angles(0, math.atan2(-dashDirection.X, -dashDirection.Z), 0)

					-- Verificar colision con pared (raycast hacia adelante)
					local raycastParams = RaycastParams.new()
					raycastParams.FilterType = Enum.RaycastFilterType.Exclude
					raycastParams.FilterDescendantsInstances = {character}
					local rayResult = workspace:Raycast(hrp.Position, dashDirection * 3, raycastParams)
					if rayResult and not hitWall then
						hitWall = true
						-- Flash de impacto contra pared
						VFXModule.SpawnMeleeHitVFX(rayResult.Position, Color3.fromRGB(255, 255, 255))
					end

					-- Buscar Toonflow para arrastrar (solo el primero)
					if not grabbedTarget then
						for _, otherPlayer in ipairs(Players:GetPlayers()) do
							local otherChar = otherPlayer.Character
							if otherChar and otherChar ~= character then
								local otherHrp = otherChar:FindFirstChild("HumanoidRootPart")
								local otherStats = StatsModule.GetStats(otherChar)
								if otherHrp and otherStats then
									local otherRole = otherStats:FindFirstChild("Role")
									local otherAlive = otherStats:FindFirstChild("IsAlive")
									if otherRole and otherRole.Value == StatsModule.Role.Toonflow
										and otherAlive and otherAlive.Value then
										local distance = (otherHrp.Position - hrp.Position).Magnitude
										if distance <= 5 then
											grabbedTarget = otherChar
											break
										end
									end
								end
							end
						end
					end

					-- Arrastrar al Toonflow capturado
					if grabbedTarget and grabbedTarget.Parent then
						local grabbedHrp = grabbedTarget:FindFirstChild("HumanoidRootPart")
						if grabbedHrp then
							-- Mover al Toonflow junto con Neuro
							grabbedHrp.CFrame = CFrame.new(newPos + dashDirection * 2)
						end
					end
				end

				-- Limpiar trail
				trail.Enabled = false
				Debris:AddItem(trailAtt0, 1)
				Debris:AddItem(trailAtt1, 1)
				Debris:AddItem(trail, 1)

				-- == APLICAR DANO AL FINAL ==
				if grabbedTarget and grabbedTarget.Parent then
					local damage = hitWall and wallDamage or noWallDamage
					StatsModule.ApplyDamage(grabbedTarget, damage)
					local grabbedHrp = grabbedTarget:FindFirstChild("HumanoidRootPart")
					if grabbedHrp then
						VFXModule.SpawnMeleeHitVFX(grabbedHrp.Position, Color3.fromRGB(200, 100, 255))
					end
					print("[Neuro] LastShow: arrastro a " .. grabbedTarget.Name .. " y causo " .. damage .. " dmg (Pared: " .. tostring(hitWall) .. ")")
				else
					print("[Neuro] LastShow: no capturo a ningun Toonflow.")
				end
			end)
		end)

		print("[Neuro] LastShow cargando por " .. player.Name .. " (Fame: " .. fame .. ", Empowered: " .. tostring(isEmpowered) .. ")")
	end,
})

return NeuroAbilities