--[[
	DeerphinaAbilities (ModuleScript)
	Mapeo oficial del rework de Deerphina para AbilityFramework.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local AbilityFramework = require(game:GetService("ServerScriptService").ServerModules.AbilityFramework)
local StatsModule = require(game:GetService("ServerScriptService").ServerModules.StatsModule)
local VFXModule = require(ReplicatedStorage.Framework.VFXModule)

local DeerphinaAbilities = {}

-- Initialize cookie charges on spawn
local function ensureCookieCharges(character)
	if not character:GetAttribute("CookieCharges") then
		character:SetAttribute("CookieCharges", 4)
	end
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
		if not (hrp and hum) then return end

		ensureCookieCharges(character)

		-- Crear fuerza de impulso (LinearVelocity)
		local attachment = Instance.new("Attachment", hrp)
		local lv = Instance.new("LinearVelocity")
		lv.MaxForce = 100000
		lv.VectorVelocity = hrp.CFrame.LookVector * 55 -- Velocidad de embestida
		lv.Attachment0 = attachment
		lv.Parent = hrp

		local hitDevilish = nil
		local duration = 1.2
		local startTime = os.clock()

		-- Conexión de colisión para arrastrar al Devilish
		local touchConn
		touchConn = hrp.Touched:Connect(function(otherPart)
			local targetModel = otherPart.Parent
			if targetModel and targetModel ~= character then
				local stats = StatsModule.GetStats(targetModel)
				local roleVal = stats and stats:FindFirstChild("Role")

				if roleVal and roleVal.Value == "Devilish" then
					hitDevilish = targetModel
					touchConn:Disconnect()
				end
			end
		end)

		-- Bucle de embestida con detección de pared
		task.spawn(function()
			while (os.clock() - startTime) < duration do
				-- Si atrapó al Devilish, lo mantiene pegado al frente
				if hitDevilish then
					local targetHrp = hitDevilish:FindFirstChild("HumanoidRootPart")
					if targetHrp then
						targetHrp.CFrame = hrp.CFrame * CFrame.new(0, 0, -3)
					end

					-- Detectar pared con Raycast frontal
					local rayParams = RaycastParams.new()
					rayParams.FilterExclude = {character, hitDevilish}
					local rayResult = workspace:Raycast(hrp.Position, hrp.CFrame.LookVector * 2, rayParams)

					if rayResult and rayResult.Instance and rayResult.Instance.CanCollide then
						-- Chocó contra la pared: Aplicar aturdimiento y daño leve al Devilish
						StatsModule.ApplyDamage(hitDevilish, 15)
						local targetHum = hitDevilish:FindFirstChildOfClass("Humanoid")
						if targetHum then
							local oldSpeed = targetHum.WalkSpeed
							targetHum.WalkSpeed = 0
							task.delay(2, function()
								if targetHum then targetHum.WalkSpeed = oldSpeed end
							end)
						end
						break
					end
				end
				task.wait()
			end

			-- Limpieza de físicas
			if touchConn then touchConn:Disconnect() end
			lv:Destroy()
			attachment:Destroy()
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

		local origin = hrp.Position
		local forward = hrp.CFrame.LookVector

		for _, model in ipairs(workspace:GetChildren()) do
			if model:IsA("Model") and model ~= character then
				local targetHrp = model:FindFirstChild("HumanoidRootPart")
				local targetHum = model:FindFirstChildOfClass("Humanoid")

				if targetHrp and targetHum and targetHum.Health > 0 then
					local toTarget = (targetHrp.Position - origin)
					if toTarget.Magnitude <= 8 and forward:Dot(toTarget.Unit) > 0.3 then
						local stats = StatsModule.GetStats(model)
						local roleVal = stats and stats:FindFirstChild("Role")

						if roleVal and roleVal.Value == "Devilish" then
							-- Aplicar daño y Stun de 3 segundos
							StatsModule.ApplyDamage(model, 10)

							local originalSpeed = targetHum.WalkSpeed
							targetHum.WalkSpeed = 0

							-- VFX / Animación de impacto
							VFXModule.SpawnMeleeHitVFX(targetHrp.Position, Color3.fromRGB(255, 200, 50))

							task.delay(3, function()
								if targetHum then
									targetHum.WalkSpeed = originalSpeed
								end
							end)
							break
						end
					end
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
		if not hum or hum.Health <= 0 then return end

		ensureCookieCharges(character)
		local charges = character:GetAttribute("CookieCharges") or 0

		if charges <= 0 then
			print("[Deerphina] ¡No quedan galletas!")
			return
		end

		-- Consumir 1 carga
		character:SetAttribute("CookieCharges", charges - 1)

		local initialHealth = hum.Health
		local interrupted = false

		-- Canalización de 1.5 segundos
		local conn
		conn = hum.HealthChanged:Connect(function(newHealth)
			if newHealth < initialHealth then
				interrupted = true
			end
		end)

		task.wait(1.5)
		conn:Disconnect()

		if not interrupted and hum and hum.Health > 0 then
			hum.Health = math.min(hum.MaxHealth, hum.Health + 30)
			print("[Deerphina] Galleta consumida. +30 HP. Cargas restantes: " .. (charges - 1))
		else
			print("[Deerphina] Curación interrumpida por ataque.")
		end
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

		if charges <= 0 then
			print("[Deerphina] ¡No tienes galletas para regalar!")
			return
		end

		-- Buscar aliado en frente
		local origin = hrp.Position
		local forward = hrp.CFrame.LookVector

		for _, model in ipairs(workspace:GetChildren()) do
			if model:IsA("Model") and model ~= character then
				local targetHrp = model:FindFirstChild("HumanoidRootPart")
				local targetHum = model:FindFirstChildOfClass("Humanoid")

				if targetHrp and targetHum and targetHum.Health > 0 then
					local dist = (targetHrp.Position - origin).Magnitude
					if dist <= 8 and forward:Dot((targetHrp.Position - origin).Unit) > 0.3 then
						local stats = StatsModule.GetStats(model)
						local roleVal = stats and stats:FindFirstChild("Role")

						if not roleVal or roleVal.Value == "Toonflow" then
							-- Restar carga a Deerphina y curar al aliado
							character:SetAttribute("CookieCharges", charges - 1)
							targetHum.Health = math.min(targetHum.MaxHealth, targetHum.Health + 30)

							-- VFX de curación en el aliado
							VFXModule.SpawnMeleeHitVFX(targetHrp.Position, Color3.fromRGB(100, 255, 100))
							print("[Deerphina] Regalo de galleta entregado a " .. model.Name)
							break
						end
					end
				end
			end
		end
	end,
})

return DeerphinaAbilities