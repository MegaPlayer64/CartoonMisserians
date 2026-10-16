--[[
	CombatClient (LocalScript)
	Ubicacion: StarterPlayer.StarterPlayerScripts.CombatClient

	Maneja el input del cliente para ataques melee del Devilish.
	Detecta clic izquierdo (o boton de movil) y envia la solicitud al servidor.

	BUG FIX v4:
	  - Se elimino el contador local lastHitCount y los eventos MeleeHit separados.
	  - El servidor envia TODOS los detalles de impacto en un solo evento MeleeSwing.
	  - Esto elimina la desincronizacion entre el contador del servidor y el cliente.

	Dependencias:
	  - ReplicatedStorage.Framework.Remotes.MeleeAttack (RemoteEvent)
	  - ReplicatedStorage.Framework.Remotes.AbilityResult (RemoteEvent)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local MeleeAttackRemote = Remotes:WaitForChild("MeleeAttack")
local AbilityResultRemote = Remotes:WaitForChild("AbilityResult")

-- Requerir VFXModule para efectos de sonido locales
local VFXModule = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("VFXModule"))

-- Flag para evitar spam de solicitudes de ataque
local canAttack = true
local attackRequestCooldown = 0.5 -- segundos minimos entre solicitudes del cliente

--[[
	Envia la solicitud de ataque melee al servidor.
	El servidor validara cooldown real, distancia y rol.
]]
local function requestMeleeAttack()
	if not canAttack then return end
	if not player.Character then return end

	-- Verificar que el personaje tenga stats y sea Devilish (validacion local preliminar)
	local stats = player.Character:FindFirstChild("Stats")
	if not stats then return end

	local role = stats:FindFirstChild("Role")
	if not role or role.Value ~= "Devilish" then return end

	local isAlive = stats:FindFirstChild("IsAlive")
	if not isAlive or not isAlive.Value then return end

	-- Enviar solicitud al servidor
	-- Los detalles de impacto vendran en el evento MeleeSwing
	MeleeAttackRemote:FireServer()

	-- Cooldown local para evitar saturar el servidor con solicitudes
	canAttack = false
	task.delay(attackRequestCooldown, function()
		canAttack = true
	end)
end

-- == DETECCION DE INPUT ==

-- Clic izquierdo del raton (PC)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		requestMeleeAttack()
	end

	-- Soporte para tactil (movil): tap en pantalla
	if input.UserInputType == Enum.UserInputType.Touch then
		requestMeleeAttack()
	end
end)

-- == RECEPCION DE RESULTADOS DEL SERVIDOR ==

-- Recibir resultados del ataque (para feedback visual/sonoro)
-- El servidor envia TODOS los detalles de impacto en un solo evento MeleeSwing,
-- eliminando la desincronizacion entre contador del servidor y cliente.
AbilityResultRemote.OnClientEvent:Connect(function(action, data)
	if action == "MeleeSwing" then
		-- El ataque se ejecuto. data.hits contiene la lista de impactos.
		local hits = (data and data.hits) or {}
		local serverHitCount = #hits

		print("[CombatClient] Ataque ejecutado - Impactos: " .. tostring(serverHitCount))

		-- Procesar cada impacto individualmente
		for i, hit in ipairs(hits) do
			print("[CombatClient] Impacto #" .. i .. " en " .. (hit.target or "?") .. " - " .. tostring(hit.damage) .. " dano (" .. tostring(hit.status) .. ")")
		end

		-- Reproducir sonido de swing localmente en el personaje
		if player.Character then
			local hrp = player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				VFXModule.PlaySound3D(hrp, VFXModule.Sounds.MeleeSwing, 0.5)
			end
		end

		-- Reproducir sonido de impacto por cada golpe exitoso
		for _, hit in ipairs(hits) do
			if hit.target and player.Character then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					VFXModule.PlaySound3D(hrp, VFXModule.Sounds.MeleeHit, 0.6)
				end
			end
		end
	end
end)

print("[CombatClient] Sistema de combate del cliente inicializado.")