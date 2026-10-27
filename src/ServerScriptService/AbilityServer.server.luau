--[[
	AbilityServer (Script)
	Ubicación: ServerScriptService.AbilityServer

	Maneja las solicitudes de uso de habilidades desde el cliente.
	Las habilidades se ejecutan libremente permitiendo fallar el ataque (Whiff):
	no se exige un objetivo dentro de rango, pero el punto de mira SIEMPRE se
	sanea (sanitizeTargetData) antes de llegar a las habilidades.

	Orden de validación (todo argumento del cliente es hostil):
	  rate limit → tipo → registro → dueño de la habilidad → vivo/estado →
	  cooldown/recursos → CustomCheck → saneo del objetivo → ejecución
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityFramework = require(game:GetService("ServerScriptService").ServerModules.AbilityFramework)
local StatsModule = require(game:GetService("ServerScriptService").ServerModules.StatsModule)
local AbilityTemplates = require(game:GetService("ServerScriptService").ServerModules.AbilityTemplates)
local RateLimiter = require(game:GetService("ServerScriptService").ServerModules.RateLimiter)
local AbilityOwnership = require(game:GetService("ServerScriptService").ServerModules.AbilityOwnership)

-- Registro de habilidades
local BrothercatAbilities = require(game:GetService("ServerScriptService").ServerModules.BrothercatAbilities)
local TobyAbilities = require(game:GetService("ServerScriptService").ServerModules.TobyAbilities)
local TakoritaAbilities = require(game:GetService("ServerScriptService").ServerModules.TakoritaAbilities)
local NeuroAbilities = require(game:GetService("ServerScriptService").ServerModules.NeuroAbilities)
local TrunksAbilities = require(game:GetService("ServerScriptService").ServerModules.TrunksAbilities)
local StanAbilities = require(game:GetService("ServerScriptService").ServerModules.StanAbilities)
local MariposaurioAbilities = require(game:GetService("ServerScriptService").ServerModules.MariposaurioAbilities)
local DeerphinaAbilities = require(game:GetService("ServerScriptService").ServerModules.DeerphinaAbilities)
local MissCircleAbilities = require(game:GetService("ServerScriptService").ServerModules.MissCircleAbilities)
local ShedMovAbilities = require(game:GetService("ServerScriptService").ServerModules.ShedMovAbilities)

local Remotes = ReplicatedStorage.Framework.Remotes
local UseAbilityRemote = Remotes:WaitForChild("UseAbility")
local AbilityResultRemote = Remotes:WaitForChild("AbilityResult")

-- == LÍMITES ==
local RATE_PER_SEC = 10
local RATE_BURST = 15
local MAX_ABILITY_NAME_LENGTH = 64

local MAX_AIM_DISTANCE = 300 -- studs; más lejos se recorta
local MIN_AIM_HORIZONTAL = 0.5 -- studs; evita (target - pos).Unit de un vector casi nulo
local MAX_COORD = 100000

--[[
	Devuelve un Vector3 finito y acotado, o nil.
	nil = "sin objetivo": las habilidades ya caen a hrp.CFrame.LookVector, así que
	el whiffing sigue funcionando. Esto bloquea NaN, ±inf, vectores nulos (cuyo
	.Unit da NaN y acaba en LinearVelocity/CFrame) y objetivos absurdamente lejanos.
]]
local function sanitizeTargetData(targetData: any, hrp: BasePart): Vector3?
	if typeof(targetData) ~= "Vector3" then
		return nil
	end

	local x, y, z = targetData.X, targetData.Y, targetData.Z
	if x ~= x or y ~= y or z ~= z then
		return nil -- NaN
	end
	if math.abs(x) > MAX_COORD or math.abs(y) > MAX_COORD or math.abs(z) > MAX_COORD then
		return nil -- ±inf o fuera del mundo
	end

	local offset = targetData - hrp.Position
	if Vector3.new(offset.X, 0, offset.Z).Magnitude < MIN_AIM_HORIZONTAL then
		return nil -- apuntando a los pies o justo encima: sin dirección horizontal
	end
	if offset.Magnitude > MAX_AIM_DISTANCE then
		return hrp.Position + offset.Unit * MAX_AIM_DISTANCE
	end

	return targetData
end

UseAbilityRemote.OnServerEvent:Connect(function(player, abilityName, targetData)
	-- 0. Rate limit (primera línea)
	if not RateLimiter.allow(player, "UseAbility", RATE_PER_SEC, RATE_BURST) then return end

	-- 1. Validar parámetro básico
	if typeof(abilityName) ~= "string" or #abilityName == 0 or #abilityName > MAX_ABILITY_NAME_LENGTH then return end

	-- 2. Validar Personaje
	if not player or not player.Character then return end
	local character = player.Character
	-- Un Toonflow que ya escapó está en la zona segura: no actúa.
	if character:GetAttribute("Escaped") then return end

	-- 3. Validar Registro de la Habilidad (silencioso: abilityName es input del cliente)
	local abilityDef = AbilityFramework.Registry[abilityName]
	if not abilityDef then return end

	-- 4. Validar que la habilidad pertenece al personaje en uso
	if not AbilityOwnership.canUse(character:GetAttribute("CharacterName"), abilityName) then return end

	-- 5. Validar Stats
	local stats = StatsModule.GetStats(character)
	if not stats then return end

	-- 6. Validar si está vivo
	local isAlive = stats:FindFirstChild("IsAlive")
	if not isAlive or not isAlive.Value then return end

	-- 7. Validar Estado (Aturdido/Derribado)
	local state = stats:FindFirstChild("State")
	if state and state.Value ~= StatsModule.CharacterState.Normal then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then return end

	-- 8. Verificación de Cooldown / Cargas / Recursos
	local canUse, reason = AbilityFramework.CanUse(player, abilityName, character)
	if not canUse then
		AbilityResultRemote:FireClient(player, "AbilityFailed", {
			abilityName = abilityName,
			reason = reason,
		})
		return
	end

	-- 9. Custom Check (Si aplica)
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

	-- 10. EJECUTAR (sin exigir rango, pero con el objetivo saneado)
	local safeTarget = sanitizeTargetData(targetData, hrp)
	local success, result = AbilityFramework.Execute(player, abilityName, character, safeTarget)

	if not success then
		-- El cooldown y el recurso ya fueron reembolsados por AbilityFramework.Execute;
		-- avisamos al cliente (antes quedaba mostrando un cooldown que no existe).
		AbilityResultRemote:FireClient(player, "AbilityFailed", {
			abilityName = abilityName,
			reason = result,
		})
	end

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
