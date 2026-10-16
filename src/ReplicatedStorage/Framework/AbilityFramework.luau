--[[
	AbilityFramework (ModuleScript)
	Ubicacion: ReplicatedStorage.Framework.AbilityFramework

	Framework base para gestionar habilidades con Cooldowns, Cargas (Charges)
	y Costos de Recursos (Absorption, Health, etc.).

	Cada habilidad se define como una tabla con la siguiente estructura:

	{
		Name        = string,
		Description = string,
		MaxCharges  = number,         -- Cargas maximas (1 = sin recarga multiple)
		Cooldown    = number,         -- Segundos entre usos
		CostType    = string|nil,    -- "Absorption" | "Health" | nil
		CostAmount  = number,         -- Cantidad del recurso a consumir
		CastTime    = number,         -- 0 = instantaneo, >0 = canalizado
		Range       = number,         -- Rango efectivo en studs (para validacion)
		Execute     = function(params) end,  -- Logica de ejecucion (server-side)
	}

	El framework maneja el registro, verificacion y ejecucion de habilidades.
]]

local AbilityFramework = {}

-- Tabla de habilidades registradas: [abilityName] = abilityDefinition
AbilityFramework.Registry = {}

-- Tabla de estado de cooldowns por jugador: [Player] = { [abilityName] = { charges = n, lastUsed = tick } }
AbilityFramework.PlayerCooldowns = {}

--[[
	Registra una nueva habilidad en el framework.
]]
function AbilityFramework.Register(abilityDef)
	assert(abilityDef.Name, "AbilityFramework.Register: Name es requerido")
	assert(abilityDef.Execute, "AbilityFramework.Register: Execute function es requerida")

	-- Valores por defecto
	abilityDef.MaxCharges = abilityDef.MaxCharges or 1
	abilityDef.Cooldown = abilityDef.Cooldown or 5
	abilityDef.CostType = abilityDef.CostType or nil
	abilityDef.CostAmount = abilityDef.CostAmount or 0
	abilityDef.CastTime = abilityDef.CastTime or 0
	abilityDef.Range = abilityDef.Range or 0

	AbilityFramework.Registry[abilityDef.Name] = abilityDef
	return abilityDef
end

--[[
	Inicializa el estado de cooldowns para un jugador.
	Se llama cuando el jugador entra en partida o se le asigna un rol.
]]
function AbilityFramework.InitPlayer(player)
	AbilityFramework.PlayerCooldowns[player] = {}
	for name, abilityDef in pairs(AbilityFramework.Registry) do
		AbilityFramework.PlayerCooldowns[player][name] = {
			charges = abilityDef.MaxCharges,
			lastUsed = 0,
			casting = false,
		}
	end
end

--[[
	Limpia el estado de un jugador al salir o terminar la partida.
]]
function AbilityFramework.ClearPlayer(player)
	AbilityFramework.PlayerCooldowns[player] = nil
end

--[[
	Verifica si un jugador puede usar una habilidad:
	- Debe estar registrada
	- Debe tener cargas disponibles
	- El cooldown debe haber terminado
	- Debe tener el recurso suficiente (si aplica)

	Retorna: canUse (bool), reason (string)
]]
function AbilityFramework.CanUse(player, abilityName, character)
	local abilityDef = AbilityFramework.Registry[abilityName]
	if not abilityDef then
		return false, "AbilityNotFound"
	end

	local playerState = AbilityFramework.PlayerCooldowns[player]
	if not playerState then
		return false, "PlayerNotInitialized"
	end

	local abilityState = playerState[abilityName]
	if not abilityState then
		return false, "AbilityStateNotFound"
	end

	-- Verificar si esta canalizando otra habilidad
	if abilityState.casting then
		return false, "AlreadyCasting"
	end

	-- Verificar cargas disponibles
	if abilityState.charges <= 0 then
		return false, "NoCharges"
	end

	-- Verificar cooldown (solo si no hay sistema de cargas multiples)
	if abilityDef.MaxCharges == 1 then
		local effectiveCooldown = abilityDef.Cooldown
		-- Aplicar modificador de cooldown si existe (ej. Super Saiyan)
		if playerState.cooldownModifiers and playerState.cooldownModifiers[abilityName] then
			effectiveCooldown = effectiveCooldown * playerState.cooldownModifiers[abilityName]
		end
		local elapsed = tick() - abilityState.lastUsed
		if elapsed < effectiveCooldown then
			return false, "OnCooldown"
		end
	end

	-- Verificar costo de recurso
	if abilityDef.CostType and abilityDef.CostAmount > 0 and character then
		local StatsModule = require(game.ReplicatedStorage.Framework.StatsModule)
		local stats = StatsModule.GetStats(character)
		if not stats then
			return false, "NoStats"
		end

		if abilityDef.CostType == "Absorption" then
			local absorption = stats:FindFirstChild("Absorption")
			if not absorption or absorption.Value < abilityDef.CostAmount then
				return false, "InsufficientAbsorption"
			end
		elseif abilityDef.CostType == "Health" then
			local health = stats:FindFirstChild("Health")
			if not health or health.Value <= abilityDef.CostAmount then
				return false, "InsufficientHealth"
			end
		end
	end

	return true, "OK"
end

--[[
	Ejecuta una habilidad en el servidor. Esta funcion asume que CanUse ya fue verificada.

	Parametros:
		player     -> Player que usa la habilidad
		abilityName -> Nombre de la habilidad
		character  -> Character del player
		targetData -> Datos del objetivo (Vector3, CFrame, Part, etc.)

	Retorna: success (bool), result (string)
]]
function AbilityFramework.Execute(player, abilityName, character, targetData)
	local abilityDef = AbilityFramework.Registry[abilityName]
	if not abilityDef then
		return false, "AbilityNotFound"
	end

	local playerState = AbilityFramework.PlayerCooldowns[player]
	if not playerState then
		return false, "PlayerNotInitialized"
	end

	local abilityState = playerState[abilityName]
	if not abilityState then
		return false, "AbilityStateNotFound"
	end

	-- Consumir recurso si aplica
	if abilityDef.CostType and abilityDef.CostAmount > 0 then
		local StatsModule = require(game.ReplicatedStorage.Framework.StatsModule)
		if abilityDef.CostType == "Absorption" then
			StatsModule.ConsumeAbsorption(character, abilityDef.CostAmount)
		elseif abilityDef.CostType == "Health" then
			StatsModule.ApplyDamage(character, abilityDef.CostAmount, true)
		end
	end

	-- Marcar como usado
	abilityState.charges = abilityState.charges - 1
	abilityState.lastUsed = tick()

	-- Si tiene CastTime > 0, marcar como canalizando
	if abilityDef.CastTime > 0 then
		abilityState.casting = true
	end

	-- Ejecutar la logica de la habilidad
	local params = {
		Player = player,
		Character = character,
		TargetData = targetData,
		AbilityDef = abilityDef,
	}

	-- Ejecutar en una coroutine para no bloquear el hilo principal
	local success, err = pcall(abilityDef.Execute, params)

	-- Si tiene CastTime, restaurar cargas y estado de canalizacion despues
	if abilityDef.CastTime > 0 then
		task.delay(abilityDef.CastTime, function()
			if abilityState then
				abilityState.casting = false
			end
		end)
	end

	-- Restaurar una carga despues del cooldown
	local effectiveCooldown = abilityDef.Cooldown
	if playerState.cooldownModifiers and playerState.cooldownModifiers[abilityName] then
		effectiveCooldown = effectiveCooldown * playerState.cooldownModifiers[abilityName]
	end
	task.delay(effectiveCooldown, function()
		if AbilityFramework.PlayerCooldowns[player] and abilityState then
			abilityState.charges = math.min(abilityState.charges + 1, abilityDef.MaxCharges)
		end
	end)

	if not success then
		warn("[AbilityFramework] Error ejecutando " .. abilityName .. ": " .. tostring(err))
		return false, "ExecutionError"
	end

	return true, "Executed"
end

--[[
	Obtiene el estado de cooldown de una habilidad para un jugador.
	Util para sincronizar con el cliente y mostrar UI.
]]
function AbilityFramework.GetCooldownInfo(player, abilityName)
	local playerState = AbilityFramework.PlayerCooldowns[player]
	if not playerState then return nil end

	local abilityState = playerState[abilityName]
	if not abilityState then return nil end

	local abilityDef = AbilityFramework.Registry[abilityName]
	if not abilityDef then return nil end

	local effectiveCooldown = abilityDef.Cooldown
	if playerState.cooldownModifiers and playerState.cooldownModifiers[abilityName] then
		effectiveCooldown = effectiveCooldown * playerState.cooldownModifiers[abilityName]
	end
	local remaining = math.max(0, effectiveCooldown - (tick() - abilityState.lastUsed))

	return {
		charges = abilityState.charges,
		maxCharges = abilityDef.MaxCharges,
		cooldownRemaining = remaining,
		isCasting = abilityState.casting,
	}
end

-- == COOLDOWN MODIFIERS ==
-- Permite modificar el cooldown de habilidades especificas por jugador.
-- Usado por Trunks Super Saiyan para reducir 25% el CD de ZSword y KiBlasts.

function AbilityFramework.SetCooldownModifier(player, abilityName, multiplier)
	local playerState = AbilityFramework.PlayerCooldowns[player]
	if not playerState then return false end
	if not playerState.cooldownModifiers then
		playerState.cooldownModifiers = {}
	end
	playerState.cooldownModifiers[abilityName] = multiplier
	return true
end

function AbilityFramework.ClearCooldownModifier(player, abilityName)
	local playerState = AbilityFramework.PlayerCooldowns[player]
	if not playerState or not playerState.cooldownModifiers then return false end
	playerState.cooldownModifiers[abilityName] = nil
	return true
end

function AbilityFramework.GetCooldownModifier(player, abilityName)
	local playerState = AbilityFramework.PlayerCooldowns[player]
	if not playerState or not playerState.cooldownModifiers then return nil end
	return playerState.cooldownModifiers[abilityName]
end

return AbilityFramework