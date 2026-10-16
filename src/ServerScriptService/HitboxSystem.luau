--[[
	HitboxSystem (ModuleScript)
	Ubicacion: ServerScriptService.HitboxSystem

	Sistema de hitbox melee eficiente usando OverlapParams / GetPartsInPart.
	Ejecuta exclusivamente en el servidor para validacion anti-exploit.

	Funciones principales:
	- PerformMeleeHit: Ejecuta un hitbox cubico desde el atacante
	- PerformConeHit:  Ejecuta un hitbox cónico (cono frontal)
	- ValidateDistance: Verifica que el objetivo este dentro del rango permitido

	BUG FIX v2:
	  - La tabla de personajes detectados (hitRegister) es ESTRICTAMENTE
	    LOCAL a cada llamada. Se crea fresca en cada invocacion.
	  - El callback onHit se envuelve en pcall para que un error en el
	    callback (ej. Toonflow en estado Downed) NO propague ni bloquee el flujo.
	  - La hitbox temporal se destruye SIEMPRE, incluso si hay error.
	  - Retorna explícitamente {} y hitCount = 0 cuando no hay impactos.
]]

local HitboxSystem = {}

--[[
	Realiza un hitbox melee desde el personaje atacante.

	Parametros:
		attackerCharacter -> Model del atacante (Devilish)
		range             -> Rango del ataque en studs
		damage            -> Dano a aplicar (pasado al callback onHit)
		onHit             -> Callback opcional(character, hitPart) por cada objetivo

	Retorna: tabla array de personajes impactados (sin duplicados), hitCount (numero)
]]
function HitboxSystem.PerformMeleeHit(attackerCharacter, range, damage, onHit)
	local hrp = attackerCharacter:FindFirstChild("HumanoidRootPart")
	if not hrp then
		-- Sin HumanoidRootPart: retornar vacio explicitamente
		return {}, 0
	end

	-- Tabla LOCAL de personajes ya procesados en ESTE ataque.
	-- Se crea nueva en cada llamada, garantizando que no haya estado
	-- residual entre ataques que cause dobles golpes o bloqueos.
	local hitRegister = {}
	local hitCharacters = {}
	local hitCount = 0

	-- Crear una Part temporal como hitbox
	local hitbox = Instance.new("Part")
	hitbox.Name = "MeleeHitbox"
	hitbox.Size = Vector3.new(range * 2, range * 2, range * 2)
	hitbox.CFrame = hrp.CFrame * CFrame.new(0, 0, -range / 2)
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanQuery = false
	hitbox.Transparency = 1
	hitbox.Parent = workspace

	-- Garantizar que la hitbox se destruya SIEMPRE, incluso si hay error
	local function destroyHitbox()
		if hitbox and hitbox.Parent then
			hitbox:Destroy()
		end
	end

	-- Envolver toda la logica de deteccion en pcall para que un error
	-- no deje la hitbox sin destruir ni bloquee el flujo del CombatServer.
	local detectionSuccess, detectionError = pcall(function()
		-- Configurar OverlapParams para la deteccion
		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = {attackerCharacter, hitbox}

		-- Obtener todas las parts que intersectan con la hitbox
		local partsInHitbox = workspace:GetPartsInPart(hitbox, overlapParams)

		-- Procesar cada part impactada
		for _, hitPart in ipairs(partsInHitbox) do
			local hitCharacter = hitPart.Parent
			if hitCharacter and not hitRegister[hitCharacter] then
				-- Verificar que sea un personaje valido (tiene Humanoid)
				local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					-- Validar distancia real (anti-exploit)
					local hitHRP = hitCharacter:FindFirstChild("HumanoidRootPart")
					if hitHRP then
						local distance = (hrp.Position - hitHRP.Position).Magnitude
						-- Solo aplicar dano si esta dentro del rango + margen de tolerancia
						if distance <= range * 1.5 then
							-- Marcar como procesado INMEDIATAMENTE para evitar duplicados
							hitRegister[hitCharacter] = true
							table.insert(hitCharacters, hitCharacter)
							hitCount = hitCount + 1

							-- Llamar al callback dentro de pcall para que un error
							-- (ej. Toon en estado Downed) NO bloquee el ataque.
							if onHit then
								local cbSuccess, cbError = pcall(onHit, hitCharacter, hitPart)
								if not cbSuccess then
									warn("[HitboxSystem] Error en callback onHit: " .. tostring(cbError))
								end
							end
						end
					end
				end
			end
		end
	end)

	-- Destruir la hitbox SIEMPRE, sin importar si hubo error
	destroyHitbox()

	if not detectionSuccess then
		warn("[HitboxSystem] Error en deteccion: " .. tostring(detectionError))
		return hitCharacters, hitCount
	end

	-- Retornar explicitamente la tabla y el contador.
	-- Si no hubo impactos: hitCharacters = {}, hitCount = 0
	return hitCharacters, hitCount
end

--[[
	Valida que un objetivo este dentro del rango permitido desde el atacante.
	Util para validacion adicional antes de aplicar efectos.

	Parametros:
		attackerCharacter -> Model del atacante
		targetCharacter   -> Model del objetivo
		maxRange          -> Rango maximo permitido en studs

	Retorna: true si esta dentro del rango, false si no
]]
function HitboxSystem.ValidateDistance(attackerCharacter, targetCharacter, maxRange)
	local attackerHRP = attackerCharacter:FindFirstChild("HumanoidRootPart")
	local targetHRP = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")

	if not (attackerHRP and targetHRP) then
		return false
	end

	local distance = (attackerHRP.Position - targetHRP.Position).Magnitude
	return distance <= maxRange
end

--[[
	Version alternativa usando Raycasting para hitbox frontal (cono).
	Util para ataques direccionales.

	Parametros:
		attackerCharacter -> Model del atacante
		range             -> Rango del ataque
		angle             -> Angulo del cono en grados (ej. 60)
		damage            -> Dano a aplicar
		onHit             -> Callback opcional(character) por cada objetivo

	Retorna: tabla de personajes impactados
]]
function HitboxSystem.PerformConeHit(attackerCharacter, range, angle, damage, onHit)
	local hrp = attackerCharacter:FindFirstChild("HumanoidRootPart")
	if not hrp then return {}, 0 end

	local hitCharacters = {}
	local processedCharacters = {}
	local hitCount = 0
	local cosAngle = math.cos(math.rad(angle / 2))
	local forward = hrp.CFrame.LookVector

	-- Buscar todos los personajes en el workspace
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("Humanoid") and descendant.Health > 0 then
			local hitCharacter = descendant.Parent
			if hitCharacter ~= attackerCharacter and not processedCharacters[hitCharacter] then
				local hitHRP = hitCharacter:FindFirstChild("HumanoidRootPart")
				if hitHRP then
					local toTarget = (hitHRP.Position - hrp.Position)
					local distance = toTarget.Magnitude

					if distance <= range then
						local direction = toTarget.Unit
						local dot = forward:Dot(direction)

						-- Si esta dentro del cono
						if dot >= cosAngle then
							processedCharacters[hitCharacter] = true
							table.insert(hitCharacters, hitCharacter)
							hitCount = hitCount + 1

							-- pcall para proteger el callback
							if onHit then
								local success, err = pcall(onHit, hitCharacter)
								if not success then
									warn("[HitboxSystem] Error en callback onHit (Cone): " .. tostring(err))
								end
							end
						end
					end
				end
			end
		end
	end

	return hitCharacters, hitCount
end

return HitboxSystem