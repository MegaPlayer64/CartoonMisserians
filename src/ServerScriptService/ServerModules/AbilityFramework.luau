--[[
	AbilityFramework (ModuleScript)
	Ubicacion: ServerScriptService.ServerModules.AbilityFramework

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
		local StatsModule = require(game:GetService("ServerScriptService").ServerModules.StatsModule)
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
	Ejecuta una habilidad. CONTRATO de abilityDef.Execute:
	  - nil / true  -> se ejecutó (se consume cooldown y recurso)
	  - false, motivo -> NO se ejecutó (p. ej. falta el HumanoidRootPart): se REEMBOLSA
	  - error (pcall) -> NO se ejecutó: se REEMBOLSA

	Antes el recurso, la carga y el cooldown se gastaban ANTES de ejecutar y no se
	devolvían si la habilidad fallaba: el jugador perdía la habilidad por un error del
	servidor, y además el cliente no recibía ningún aviso.
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

	local StatsModule = require(game:GetService("ServerScriptService").ServerModules.StatsModule)

	-- Consumir recurso si aplica (anotando lo realmente pagado, para poder reembolsarlo)
	local paidAbsorption = 0
	local paidHealth = 0
	if abilityDef.CostType and abilityDef.CostAmount > 0 then
		if abilityDef.CostType == "Absorption" then
			if StatsModule.ConsumeAbsorption(character, abilityDef.CostAmount) then
				paidAbsorption = abilityDef.CostAmount
			end
		elseif abilityDef.CostType == "Health" then
			if StatsModule.ApplyDamage(character, abilityDef.CostAmount, true) then
				paidHealth = abilityDef.CostAmount
			end
		end
	end

	-- Marcar como usado (guardando el estado previo por si hay que revertir)
	local previousCharges = abilityState.charges
	local previousLastUsed = abilityState.lastUsed
	local previousCasting = abilityState.casting

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

	local success, result, reason = pcall(abilityDef.Execute, params)
	local executed = success and result ~= false

	if not executed then
		-- REVERTIR: la habilidad no llegó a ejecutarse con éxito
		abilityState.charges = previousCharges
		abilityState.lastUsed = previousLastUsed
		abilityState.casting = previousCasting
		if paidAbsorption > 0 then
			StatsModule.AddAbsorption(character, paidAbsorption)
		end
		if paidHealth > 0 then
			StatsModule.ApplyHeal(character, paidHealth)
		end

		if not success then
			warn("[AbilityFramework] Error ejecutando " .. abilityName .. ": " .. tostring(result))
			return false, "ExecutionError"
		end
		return false, reason or "NotExecuted"
	end

	-- Si tiene CastTime, restaurar el estado de canalizacion despues
	if abilityDef.CastTime > 0 then
		task.delay(abilityDef.CastTime, function()
			if abilityState then
				abilityState.casting = false
			end
		end)
	end

	-- Restaurar una carga despues del cooldown (solo si se ejecutó)
	local effectiveCooldown = abilityDef.Cooldown
	if playerState.cooldownModifiers and playerState.cooldownModifiers[abilityName] then
		effectiveCooldown = effectiveCooldown * playerState.cooldownModifiers[abilityName]
	end
	task.delay(effectiveCooldown, function()
		if AbilityFramework.PlayerCooldowns[player] and abilityState then
			abilityState.charges = math.min(abilityState.charges + 1, abilityDef.MaxCharges)
		end
	end)

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