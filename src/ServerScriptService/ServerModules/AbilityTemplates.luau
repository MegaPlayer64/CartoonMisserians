--[[
	AbilityTemplates (ModuleScript)
	Ubicacion: ServerScriptService.ServerModules.AbilityTemplates

	Define 3 plantillas de habilidades usando el AbilityFramework.
	Estas habilidades se registran automaticamente al requerir este modulo.

	1. "HeredadoDeMama"    -> Buff de velocidad temporal (Toon)
	2. "Gamechild"         -> Curacion instantanea (Toon)
	3. "RayosLaser"        -> Projectil skillshot (Devilish)
]]

local AbilityFramework = require(game:GetService("ServerScriptService").ServerModules.AbilityFramework)
local StatsModule = require(game:GetService("ServerScriptService").ServerModules.StatsModule)
local VFXModule = require(game.ReplicatedStorage.Framework.VFXModule)

-- == HABILIDAD 1: HEREDADO DE MAMA (Buff de velocidad temporal) ==
-- Tipo: Buff/Booster
---- Rol: Toonflow
-- Efecto: Aumenta la velocidad del Toonflow por un tiempo limitado.
AbilityFramework.Register({
	Name = "HeredadoDeMama",
	Description = "Recibe la bendicion de Mama: velocidad aumentada por 5 segundos.",
	MaxCharges = 2,
	Cooldown = 15,
	CostType = nil,        -- Sin costo de recurso
	CostAmount = 0,
	CastTime = 0,          -- Instantaneo
	Range = 0,             -- Auto-cast (afecta al usuario)

	Execute = function(params)
		local character = params.Character
		if not character then return end

		-- == EFECTO VISUAL: Highlight verde/amarillo por la duracion del buff ==
		VFXModule.SpawnSpeedBuffVFX(character, 5)

		-- Aplicar multiplicador de velocidad x1.8
		StatsModule.SetSpeedMultiplier(character, 1.8)

		-- Restaurar despues de 5 segundos
		task.delay(5, function()
			if character and character.Parent then
				StatsModule.ResetSpeedMultiplier(character)
			end
		end)

		print("[Ability] HeredadoDeMama activado por " .. (params.Player and params.Player.Name or "?"))
	end,
})

-- == HABILIDAD 2: GAMECHILD (Curacion instantanea) ==
-- Tipo: Heal
---- Rol: Toonflow
-- Efecto: Cura 40 HP instantaneamente. No puede superar MaxHealth.
AbilityFramework.Register({
	Name = "Gamechild",
	Description = "El poder de Gamechild restaura 40 HP instantaneamente.",
	MaxCharges = 1,
	Cooldown = 30,
	CostType = nil,
	CostAmount = 0,
	CastTime = 0,          -- Instantaneo (se podria cambiar a canalizado)
	Range = 0,

	Execute = function(params)
		local character = params.Character
		if not character then return end

		-- == EFECTO VISUAL: Anillo esferico verde que se expande y desvanece ==
		VFXModule.SpawnHealVFX(character, 1.5)

		-- Curar 40 HP
		StatsModule.ApplyHeal(character, 40)

		print("[Ability] Gamechild activado por " .. (params.Player and params.Player.Name or "?"))
	end,
})

-- == HABILIDAD 3: RAYOS LASER (Projectil / Skillshot) ==
-- Tipo: Projectile / Skillshot
-- Rol: Devilish
-- Efecto: Dispara un rayo laser que dana al primer Toonflow en su trayectoria.
-- Costo: 30 de Absorcion.
AbilityFramework.Register({
	Name = "RayosLaser",
	Description = "Dispara un rayo laser que causa 50 de dano al primer Toonflow impactado.",
	MaxCharges = 1,
	Cooldown = 8,
	CostType = "Absorption",
	CostAmount = 30,
	CastTime = 0,
	Range = 60,             -- Alcance maximo del rayo en studs

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		local targetData = params.TargetData
		if not (character and player) then return end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		-- targetData debe ser un Vector3 que indica la direccion del disparo
		local direction
		if typeof(targetData) == "Vector3" then
			direction = (targetData - hrp.Position).Unit
		else
			-- Si no hay direccion, disparar hacia adelante
			direction = hrp.CFrame.LookVector
		end

		-- Validar distancia del objetivo
		local maxRange = params.AbilityDef.Range

		-- Crear el rayo usando Raycasting
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {character}

		local rayResult = workspace:Raycast(hrp.Position, direction * maxRange, rayParams)

		-- Crear efecto visual del rayo (server-side, se replica a todos)
		local origin = hrp.Position
		local endPoint = rayResult and rayResult.Position or (origin + direction * maxRange)

		-- Enviar datos de depuracion de hitbox a todos los clientes
		local debugRemote = game.ReplicatedStorage.Framework.Remotes:FindFirstChild("DebugHitbox")
		if debugRemote then
			debugRemote:FireAllClients({
				type = "Ray",
				position = origin,
				endPoint = endPoint,
				duration = 0.3,
			})
		end

		-- == EFECTO VISUAL: Cilindro brillante con desvanecimiento suave ==
		-- VFXModule se encarga de crear el cilindro, el sonido y la limpieza.
		VFXModule.SpawnProjectileVFX(origin, endPoint, Color3.fromRGB(255, 50, 50))

		-- Si el rayo impacto algo, verificar si es un Toonflow
		if rayResult and rayResult.Instance then
			local hitPart = rayResult.Instance
			local hitCharacter = hitPart.Parent

			if hitCharacter then
				local hitStats = StatsModule.GetStats(hitCharacter)
				if hitStats then
					local hitRole = hitStats:FindFirstChild("Role")
					if hitRole and hitRole.Value == StatsModule.Role.Toonflow then
						-- Aplicar 50 de dano al Toonflow impactado
						StatsModule.ApplyDamage(hitCharacter, 50)
						print("[Ability] RayosLaser impacto a " .. hitCharacter.Name)
					end
				end
			end
		end

		print("[Ability] RayosLaser disparado por " .. player.Name)
	end,
})

return AbilityFramework