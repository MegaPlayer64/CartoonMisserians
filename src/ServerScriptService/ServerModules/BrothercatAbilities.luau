--[[
	BrothercatAbilities (ModuleScript)
	Ubicacion: ServerScriptService.ServerModules.BrothercatAbilities

	Define las 3 habilidades del personaje TOONFLOW "Brothercat" (Zack Anderson):
	  1. "HeredadoDeMama"   -> Buff de velocidad x3 por 3s (Cooldown: 37s)
	  2. "Gamechild"        -> Curacion instantanea de 33 HP (Cooldown: 27s)
	  3. "UltimaOpcion"     -> Proyectil que aplica empuje + lentitud a Devilish (Cooldown: 45s)

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

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local BrothercatAbilities = {}

-- == HABILIDAD 1: HEREDADO DE MAMA (Buff de velocidad x3 por 3s) ==
-- Tipo: Buff / Booster
-- Rol: Toonflow (Brothercat)
-- Cooldown: 37 segundos
-- Efecto: Multiplicador de velocidad x3 durante 3 segundos
-- Placeholder Visual: Highlight amarillo/verde + rastro de particulas
AbilityFramework.Register({
	Name = "HeredadoDeMama",
	Description = "Zack canaliza la herencia de Mama: velocidad x3 durante 3 segundos.",
	MaxCharges = 1,
	Cooldown = 37,
	CostType = nil,
	CostAmount = 0,
	CastTime = 0,
	Range = 0,

	Execute = function(params)
		local character = params.Character
		if not character then return end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		-- == PLACEHOLDER VISUAL: Highlight amarillo/verde + rastro de particulas ==
		VFXModule.SpawnSpeedBuffVFX(character, 3)
		VFXModule.SpawnTrailVFX(character, 3)

		-- Aplicar multiplicador de velocidad x3
		StatsModule.SetSpeedMultiplier(character, 3.0)

		-- Restaurar despues de 3 segundos
		task.delay(3, function()
			if character and character.Parent then
				StatsModule.ResetSpeedMultiplier(character)
			end
		end)

		print("[Brothercat] HeredadoDeMama activado por " .. (params.Player and params.Player.Name or "?"))
	end,
})

-- == HABILIDAD 2: GAMECHILD (Curacion instantanea de 33 HP) ==
-- Tipo: Heal
-- Rol: Toonflow (Brothercat)
-- Cooldown: 27 segundos
-- Efecto: Cura 33 HP instantaneamente
-- Placeholder Visual: Aura/cilindro verde brillante que se desvanece en 1s
AbilityFramework.Register({
	Name = "Gamechild",
	Description = "El poder de Gamechild restaura 33 HP instantaneamente.",
	MaxCharges = 1,
	Cooldown = 27,
	CostType = nil,
	CostAmount = 0,
	CastTime = 0,
	Range = 0,

	Execute = function(params)
		local character = params.Character
		if not character then return end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		-- == PLACEHOLDER VISUAL: Cilindro/aura verde brillante por 1 segundo ==
		VFXModule.SpawnHealAuraVFX(character, 1)

		-- Curar 33 HP
		StatsModule.ApplyHeal(character, 33)

		print("[Brothercat] Gamechild activado por " .. (params.Player and params.Player.Name or "?"))
	end,
})

-- == HABILIDAD 3: ULTIMA OPCION (Proyectil con empuje + lentitud) ==
-- Tipo: Projectile / Skillshot
-- Rol: Toonflow (Brothercat)
-- Cooldown: 45 segundos
-- Mecanica: Lanza la consola Gamechild hacia la direccion del raton
--   - Al impactar a un Devilish: empuje + SpeedMultiplier 0.5 por 3s
--   - Si falla (no impacta a Devilish en 2s): SpeedMultiplier 0.5 al caster por 2s
-- Placeholder Visual: Cubo verde temporal que se desplaza via Tweening
AbilityFramework.Register({
	Name = "UltimaOpcion",
	Description = "Lanza la consola Gamechild como proyectil. Empuja y ralentiza al Devilish impactado. Si fallas, quedas vulnerable.",
	MaxCharges = 1,
	Cooldown = 45,
	CostType = nil,
	CostAmount = 0,
	CastTime = 0,
	Range = 80,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		local targetData = params.TargetData
		if not (character and player) then return end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		-- Calcular direccion del disparo
		local targetPosition
		if typeof(targetData) == "Vector3" then
			targetPosition = targetData
		else
			-- Si no hay targetData, disparar hacia adelante
			targetPosition = hrp.Position + hrp.CFrame.LookVector * 60
		end

		local direction = (targetPosition - hrp.Position)
		local maxRange = params.AbilityDef.Range
		if direction.Magnitude > maxRange then
			direction = direction.Unit * maxRange
		else
			direction = direction
		end
		local endPoint = hrp.Position + direction

		-- == PLACEHOLDER VISUAL: Cubo verde temporal que se desplaza via Tweening ==
		local projectile = Instance.new("Part")
		projectile.Name = "UltimaOpcion_Projectile"
		projectile.Shape = Enum.PartType.Block
		projectile.Size = Vector3.new(2, 2, 2)
		projectile.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 2, 0))
		projectile.Anchored = true
		projectile.CanCollide = false
		projectile.CanQuery = false
		projectile.Material = Enum.Material.Neon
		projectile.Color = Color3.fromRGB(50, 255, 100)
		projectile.Parent = workspace

		-- Sonido del proyectil
		VFXModule.PlaySound3D(projectile, VFXModule.Sounds.Projectile, 0.5)

		-- Tween del proyectil hacia el punto objetivo
		local travelTime = 0.4
		local travelTween = TweenService:Create(projectile, TweenInfo.new(travelTime, Enum.EasingStyle.Linear), {
			CFrame = CFrame.new(endPoint),
		})

		local hitDevilish = false

		travelTween:Play()

		-- Detectar impacto durante el viaje del proyectil
		local connection
		connection = travelTween.Completed:Connect(function()
			-- Raycast en el punto final para detectar impacto
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = {character, projectile}

			-- Hacer un raycast corto en la zona de impacto
			local impactRay = workspace:Raycast(
				endPoint - direction.Unit * 2,
				direction.Unit * 4,
				rayParams
			)

			-- Tambien verificar si hay personajes cerca del punto de impacto
			local hitCharacter = nil

			if impactRay and impactRay.Instance then
				hitCharacter = impactRay.Instance.Parent
			end

			-- Si no se encontro por raycast, buscar personajes cercanos (radio 5 studs)
			if not hitCharacter then
				-- Consulta espacial acotada (antes: workspace:GetDescendants() completo en cada miss).
				local nearParams = OverlapParams.new()
				nearParams.FilterType = Enum.RaycastFilterType.Exclude
				nearParams.FilterDescendantsInstances = { character, projectile }
				for _, part in ipairs(workspace:GetPartBoundsInRadius(endPoint, 8, nearParams)) do
					local partChar = part.Parent
					local partHrp = partChar and partChar:FindFirstChild("HumanoidRootPart")
					if partHrp and (partHrp.Position - endPoint).Magnitude < 5 then
						hitCharacter = partChar
						break
					end
				end
			end

			-- Verificar si el impacto es un Devilish
			if hitCharacter then
				local hitStats = StatsModule.GetStats(hitCharacter)
				if hitStats then
					local hitRole = hitStats:FindFirstChild("Role")
					if hitRole and hitRole.Value == StatsModule.Role.Devilish then
						hitDevilish = true

						local hitHrp = hitCharacter:FindFirstChild("HumanoidRootPart")
						local hitHumanoid = hitCharacter:FindFirstChildOfClass("Humanoid")

						-- == APLICAR EMPUJE (AssemblyLinearVelocity) ==
						if hitHrp then
							local pushDirection = direction.Unit
							hitHrp.AssemblyLinearVelocity = pushDirection * 60 + Vector3.new(0, 30, 0)
						end

						-- == APLICAR LENTITUD (SpeedMultiplier = 0.5 por 3s) ==
						StatsModule.SetSpeedMultiplier(hitCharacter, 0.5)
						task.delay(3, function()
							if hitCharacter and hitCharacter.Parent then
								StatsModule.ResetSpeedMultiplier(hitCharacter)
							end
						end)

						-- VFX de impacto
						VFXModule.SpawnProjectileVFX(hrp.Position, endPoint, Color3.fromRGB(50, 255, 100))

						print("[Brothercat] UltimaOpcion impacto a Devilish: " .. hitCharacter.Name)
					end
				end
			end

			-- Destruir el proyectil visual
			local fadeTween = TweenService:Create(projectile, TweenInfo.new(0.3), {
				Transparency = 1,
				Size = Vector3.new(0.5, 0.5, 0.5),
			})
			fadeTween:Play()
			fadeTween.Completed:Connect(function()
				projectile:Destroy()
			end)
			Debris:AddItem(projectile, 1)

			-- == SISTEMA DE FALLO: Si no impacto a ningun Devilish ==
			task.delay(2, function()
				if not hitDevilish and character and character.Parent then
					-- Aplicar estado de vulnerabilidad al caster (SpeedMultiplier 0.5 por 2s)
					StatsModule.SetSpeedMultiplier(character, 0.5)

					-- VFX de castigo
					VFXModule.SpawnStunVFX(hrp.Position, 0.5)

					task.delay(2, function()
						if character and character.Parent then
							StatsModule.ResetSpeedMultiplier(character)
						end
					end)

					print("[Brothercat] UltimaOpcion FALLO. Zack queda vulnerable.")
				end
			end)
		end)

		-- Fallback: destruir el proyectil despues de 3 segundos
		Debris:AddItem(projectile, 3)

		print("[Brothercat] UltimaOpcion disparado por " .. player.Name)
	end,
})

return BrothercatAbilities