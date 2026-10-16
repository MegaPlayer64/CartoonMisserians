--[[
	AbilityServer (Script)
	Ubicación: ServerScriptService.AbilityServer

	Maneja las solicitudes de uso de habilidades desde el cliente.
	Las habilidades se ejecutan libremente permitiendo fallar el ataque (Whiff).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityFramework = require(ReplicatedStorage.Framework.AbilityFramework)
local StatsModule = require(ReplicatedStorage.Framework.StatsModule)
local AbilityTemplates = require(ReplicatedStorage.Framework.AbilityTemplates)

-- Registro de habilidades
local BrothercatAbilities = require(ReplicatedStorage.Framework.BrothercatAbilities)
local TobyAbilities = require(ReplicatedStorage.Framework.TobyAbilities)
local TakoritaAbilities = require(ReplicatedStorage.Framework.TakoritaAbilities)
local NeuroAbilities = require(ReplicatedStorage.Framework.NeuroAbilities)
local TrunksAbilities = require(ReplicatedStorage.Framework.TrunksAbilities)
local StanAbilities = require(ReplicatedStorage.Framework.StanAbilities)
local MariposaurioAbilities = require(ReplicatedStorage.Framework.MariposaurioAbilities)
local DeerphinaAbilities = require(ReplicatedStorage.Framework.DeerphinaAbilities)
local MissCircleAbilities = require(ReplicatedStorage.Framework.MissCircleAbilities)

local Remotes = ReplicatedStorage.Framework.Remotes
local UseAbilityRemote = Remotes:WaitForChild("UseAbility")
local AbilityResultRemote = Remotes:WaitForChild("AbilityResult")

UseAbilityRemote.OnServerEvent:Connect(function(player, abilityName, targetData)
	-- 1. Validar parámetro básico
	if typeof(abilityName) ~= "string" then return end

	-- 2. Validar Personaje
	if not player or not player.Character then return end
	local character = player.Character

	-- 3. Validar Registro de la Habilidad
	local abilityDef = AbilityFramework.Registry[abilityName]
	if not abilityDef then
		warn(`[AbilityServer] '{abilityName}' no está registrada en AbilityFramework.Registry!`)
		return
	end

	-- 4. Validar Stats
	local stats = StatsModule.GetStats(character)
	if not stats then return end

	-- 5. Validar si está vivo
	local isAlive = stats:FindFirstChild("IsAlive")
	if not isAlive or not isAlive.Value then return end

	-- 6. Validar Estado (Aturdido/Derribado)
	local state = stats:FindFirstChild("State")
	if state and state.Value ~= StatsModule.CharacterState.Normal then return end

	-- 7. Verificación de Cooldown / Cargas / Recursos
	local canUse, reason = AbilityFramework.CanUse(player, abilityName, character)
	if not canUse then
		AbilityResultRemote:FireClient(player, "AbilityFailed", {
			abilityName = abilityName,
			reason = reason,
		})
		return
	end

	-- 8. Custom Check (Si aplica)
	if abilityDef.CustomCheck then
		local customPass, customReason = abilityDef.CustomCheck(player, character)
		if not customPass then
			AbilityResultRemote:FireClient(player, "AbilityFailed", {
				abilityName = abilityName,
				reason = customReason,
			})
			return
		end
	end

	-- 9. EJECUTAR SIEMPRE (Sin validación de rango)
	local success, result = AbilityFramework.Execute(player, abilityName, character, targetData)

	if success then
		AbilityResultRemote:FireClient(player, "AbilitySuccess", {
			abilityName = abilityName,
			result = result,
			cooldown = abilityDef.Cooldown or 5,
		})

		-- Sincronizar Cooldown
		local cooldownInfo = AbilityFramework.GetCooldownInfo(player, abilityName)
		if cooldownInfo then
			local abilitySyncRemote = Remotes:FindFirstChild("AbilitySync")
			if abilitySyncRemote then
				abilitySyncRemote:FireClient(player, abilityName, cooldownInfo)
			end
		end
	end
end)