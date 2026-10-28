--[[
	DeerphinaAbilities (ModuleScript)
	Ubicación: ServerScriptService.ServerModules.DeerphinaAbilities

	Mapeo oficial del rework de Deerphina para AbilityFramework.

	CONTRATO con AbilityFramework.Execute: devolver `false, motivo` = la habilidad NO se ejecutó
	y se reembolsan cooldown, carga y recursos. Se usa en las habilidades que necesitan un objetivo
	o recursos (RegaloDeAmigos, GalletasParaCiervos). Los ataques de área/golpe (Koshintantan,
	ChistesDeCiervos) conservan el "whiffing": fallar al aire sí consume cooldown.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local AbilityFramework = require(game:GetService("ServerScriptService").ServerModules.AbilityFramework)
local StatsModule = require(game:GetService("ServerScriptService").ServerModules.StatsModule)
local VFXModule = require(ReplicatedStorage.Framework.VFXModule)

local DeerphinaAbilities = {}

local COOKIE_CHARGES = 4
local DASH_SPEED = 55
local DASH_DURATION = 1.2
local DRAG_DISTANCE = 3
local WALL_STUN_SECONDS = 2
local HORN_STUN_SECONDS = 3
local COOKIE_HEAL = 30
local COOKIE_CHANNEL_SECONDS = 1.5

-- Las cargas viven en el personaje; MatchManager las reinicia al empezar cada partida
local function ensureCookieCharges(character)
	if character:GetAttribute("CookieCharges") == nil then
		character:SetAttribute("CookieCharges", COOKIE_CHARGES)
	end
end

local function getRole(character)
	local stats = StatsModule.GetStats(character)
	local role = stats and stats:FindFirstChild("Role")
	return role and role.Value
end

-- Vivo, con Stats de partida y que no haya escapado (los escapados son invulnerables)
local function isValidTarget(character, role)
	if character:GetAttribute("Escaped") then return false end
	local stats = StatsModule.GetStats(character)
	if not stats then return false end
	local roleValue = stats:FindFirstChild("Role")
	local isAlive = stats:FindFirstChild("IsAlive")
	return roleValue ~= nil and roleValue.Value == role and isAlive ~= nil and isAlive.Value
end

-- El objetivo más cercano dentro de un cono frontal (antes: el PRIMERO de workspace:GetChildren()).
local function findClosestInCone(character, hrp, role, maxDistance, minDot)
	local best, bestDistance = nil, math.huge
	local forward = hrp.CFrame.LookVector

	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") and model ~= character and isValidTarget(model, role) then
			local targetHrp = model:FindFirstChild("HumanoidRootPart")
			if targetHrp then
				local toTarget = targetHrp.Position - hrp.Position
				local distance = toTarget.Magnitude
				if distance <= maxDistance and distance < bestDistance then
					if distance < 0.01 or forward:Dot(toTarget.Unit) > minDot then
						best, bestDistance = model, distance
					end
				end
			end
		end
	end

	return best
end

-- == HABILIDAD 1: KOSHINTANTAN (Embestida y Arrastre) ==
AbilityFramework.Register({
	Name = "Koshintantan",
	Description = "Realiza una embestida hacia la dirección de la cámara. Si impacta al Devilish, lo empuja hasta chocar con una pared.",
	Cooldown = 49,
	CastTime = 0.2,

	Execute = function(params)
		local character = params.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if not (hrp and hum) then return false, "NoRootPart" end

		ensureCookieCharges(character)

		-- Dirección: hacia el punto apuntado (TargetData ya viene saneado por AbilityServer);
		-- sin objetivo, hacia donde mira el personaje.
		local direction = hrp.CFrame.LookVector
		local aim = params.TargetData
		if typeof(aim) == "Vector3" then
			local flat = Vector3.new(aim.X - hrp.Position.X, 0, aim.Z - hrp.Position.Z)
			if flat.Magnitude > 0.1 then
				direction = flat.Unit
			end
		end

		local attachment = Instance.new("Attachment")
		attachment.Parent = hrp
		local lv = Instance.new("LinearVelocity")
		lv.MaxForce = 100000
		lv.VectorVelocity = direction * DASH_SPEED
		lv.Attachment0 = attachment
		lv.Parent = hrp

		-- Red de seguridad: pase lo que pase, la fuerza se elimina. Antes, si el bucle fallaba, la
		-- LinearVelocity se quedaba empujando a Deerphina para siempre.
		Debris:AddItem(lv, DASH_DURATION + 0.5)
		Debris:AddItem(attachment, DASH_DURATION + 0.5)

		local hitDevilish = nil
		local startTime = os.clock()

		local touchConn
		touchConn = hrp.Touched:Connect(function(otherPart)
			if hitDevilish then return end
			-- Ancestro Model (no Parent): el golpe puede ser a un accesorio o a una parte anidada
			local targetModel = otherPart:FindFirstAncestorOfClass("Model")
			if targetModel and targetModel ~= character and isValidTarget(targetModel, "Devilish") then
				hitDevilish = targetModel
				touchConn:Disconnect()
			end
		end)

		task.spawn(function()
			local ok, err = pcall(function()
				while os.clock() - startTime < DASH_DURATION do
					if not (hrp.Parent and hum.Health > 0) then break end

					if hitDevilish then
						local targetHrp = hitDevilish:FindFirstChild("HumanoidRootPart")
						if not targetHrp or not isValidTarget(hitDevilish, "Devilish") then break end

						-- Mantener al Devilish pegado al frente, conservando su orientación
						targetHrp.CFrame = CFrame.new(hrp.Position + direction * DRAG_DISTANCE) * targetHrp.CFrame.Rotation

						-- Detectar pared frente a la embestida.
						-- (Antes: rayParams.FilterExclude, que NO existe en RaycastParams: lanzaba un
						-- error justo al impactar y dejaba la fuerza activa.)
						local rayParams = RaycastParams.new()
						rayParams.FilterType = Enum.RaycastFilterType.Exclude
						rayParams.FilterDescendantsInstances = { character, hitDevilish }
						local rayResult = workspace:Raycast(hrp.Position, direction * (DRAG_DISTANCE + 1), rayParams)

						if rayResult and rayResult.Instance and rayResult.Instance.CanCollide then
							-- Chocó contra la pared: daño leve y aturdimiento (por StatsModule, no WalkSpeed)
							if StatsModule.ApplyDamage(hitDevilish, 15) then
								StatsModule.Stun(hitDevilish, WALL_STUN_SECONDS, params.Player)
								VFXModule.SpawnMeleeHitVFX(targetHrp.Position, Color3.fromRGB(255, 200, 50))
							end
							break
						end
					end
					task.wait()
				end
			end)

			-- Limpieza SIEMPRE, también si el bucle lanzó un error
			if touchConn then touchConn:Disconnect() end
			lv:Destroy()
			attachment:Destroy()
			if not ok then
				warn("[Deerphina] Error en Koshintantan: " .. tostring(err))
			end
		end)
	end,
})

-- == HABILIDAD 2: CHISTES DE CIERVOS (Batazo con Cuerno + Stun 3s) ==
AbilityFramework.Register({
	Name = "ChistesDeCiervos",
	Description = "Da un batazo con sus cuernos. Si golpea al Devilish, lo aturde por 3 segundos.",
	Cooldown = 32,
	CastTime = 0.1,
	Range = 7,

	Execute = function(params)
		local character = params.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		ensureCookieCharges(character)

		-- Batazo: puede fallar al aire (whiffing), y entonces sí consume el cooldown.
		local target = findClosestInCone(character, hrp, "Devilish", 8, 0.3)
		if target then
			local targetHrp = target:FindFirstChild("HumanoidRootPart")
			if StatsModule.ApplyDamage(target, 10) then
				StatsModule.Stun(target, HORN_STUN_SECONDS, params.Player)
				if targetHrp then
					VFXModule.SpawnMeleeHitVFX(targetHrp.Position, Color3.fromRGB(255, 200, 50))
				end
			end
		end
	end,
})

-- == HABILIDAD 3: GALLETAS PARA CIERVOS (Autocuración 30 HP, 4 Cargas) ==
AbilityFramework.Register({
	Name = "GalletasParaCiervos",
	Description = "Come una galleta para curarse 30 de vida. Se interrumpe si recibe daño.",
	Cooldown = 32,

	Execute = function(params)
		local character = params.Character
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return false, "NotAlive" end

		ensureCookieCharges(character)
		local charges = character:GetAttribute("CookieCharges") or 0

		-- Sin galletas o con la vida llena NO se gasta nada (antes se gastaban cooldown y galleta)
		if charges <= 0 then return false, "NoCookies" end
		if hum.Health >= hum.MaxHealth then return false, "FullHealth" end

		character:SetAttribute("CookieCharges", charges - 1)

		local initialHealth = hum.Health
		local interrupted = false
		local conn = hum.HealthChanged:Connect(function(newHealth)
			if newHealth < initialHealth then
				interrupted = true
			end
		end)

		-- La canalización va en otro hilo: antes Execute esperaba 1,5 s y la respuesta al cliente
		-- (y su cooldown) llegaba con ese retraso.
		task.spawn(function()
			task.wait(COOKIE_CHANNEL_SECONDS)
			conn:Disconnect()

			if interrupted or not character.Parent then return end
			local stats = StatsModule.GetStats(character)
			local state = stats and stats:FindFirstChild("State")
			if state and state.Value ~= StatsModule.CharacterState.Normal then return end -- aturdido/derribado

			StatsModule.ApplyHeal(character, COOKIE_HEAL)
		end)
	end,
})

-- == HABILIDAD 4: REGALO DE AMIGOS (Regalar Galleta a Aliado) ==
AbilityFramework.Register({
	Name = "RegaloDeAmigos",
	Description = "Regala una de sus galletas a un Toonflow aliado cercano a cambio de una de sus cargas.",
	Cooldown = 20,
	Range = 8,

	Execute = function(params)
		local character = params.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		ensureCookieCharges(character)
		local charges = character:GetAttribute("CookieCharges") or 0
		if charges <= 0 then return false, "NoCookies" end

		-- Aliado = Toonflow vivo, con Stats de partida y que no haya escapado.
		-- (Antes también valían humanoides SIN Stats: NPC, jugadores muertos, etc.)
		local ally = findClosestInCone(character, hrp, "Toonflow", 8, 0.3)
		if not ally then return false, "NoTarget" end

		local allyHum = ally:FindFirstChildOfClass("Humanoid")
		if not allyHum or allyHum.Health >= allyHum.MaxHealth then
			return false, "TargetFullHealth" -- no se regala una galleta que no cura
		end

		if StatsModule.ApplyHeal(ally, COOKIE_HEAL, params.Player) then
			character:SetAttribute("CookieCharges", charges - 1)
			local allyHrp = ally:FindFirstChild("HumanoidRootPart")
			if allyHrp then
				VFXModule.SpawnMeleeHitVFX(allyHrp.Position, Color3.fromRGB(100, 255, 100))
			end
		else
			return false, "HealFailed"
		end
	end,
})

return DeerphinaAbilities
