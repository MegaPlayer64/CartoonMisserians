--[[
	CombatServer (Script)
	Ubicacion: ServerScriptService.CombatServer

	Maneja los ataques melee del Devilish recibidos desde el cliente.
	Valida distancia, cooldown y aplica dano de forma segura en el servidor.

	BUG FIX v3: El bloque completo de ejecucion del ataque se envuelve en pcall.
	El flag isAttacking se libera SIEMPRE despues del pcall, garantizando que
	un error en cualquier punto del flujo (HitboxSystem, ApplyDamage, FireClient,
	VFXModule) NUNCA bloquee al jugador permanentemente.
	La tabla de objetivos golpeados es local a cada invocacion (ver HitboxSystem).

	Dependencias:
	  - ServerScriptService.ServerModules.StatsModule
	  - ReplicatedStorage.Framework.MatchConfig
	  - ReplicatedStorage.Framework.VFXModule
	  - ServerScriptService.HitboxSystem
	  - ReplicatedStorage.Framework.Remotes.MeleeAttack (RemoteEvent)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local StatsModule = require(game:GetService("ServerScriptService").ServerModules.StatsModule)
local MatchConfig = require(ReplicatedStorage.Framework.MatchConfig)
local VFXModule = require(ReplicatedStorage.Framework.VFXModule)
local HitboxSystem = require(ServerScriptService.HitboxSystem)

local RateLimiter = require(game:GetService("ServerScriptService").ServerModules.RateLimiter)
local Remotes = ReplicatedStorage.Framework.Remotes
local MeleeAttackRemote = Remotes:WaitForChild("MeleeAttack")
local DebugHitboxRemote = Remotes:FindFirstChild("DebugHitbox")
local AbilityResultRemote = Remotes:FindFirstChild("AbilityResult")

-- == DEBOUNCE ESTRICTO POR SERVIDOR ==
-- Tabla de estado de ataque por jugador: [Player] = { isAttacking = bool, lastTick = number }
-- Esto evita que multiples eventos OnServerEvent se procesen simultaneamente
-- para el mismo jugador (doble golpe por latencia o spam de clicks).
local serverAttackState = {}

--[[
	Maneja la solicitud de ataque melee del Devilish.

	Validaciones del servidor (anti-exploit):
	  1. El jugador debe tener el rol Devilish
	  2. El personaje debe estar vivo y en estado Normal
	  3. Debe haber pasado el cooldown desde el ultimo ataque (os.clock)
	  4. No debe estar ya en medio de un ataque (flag isAttacking)
	  5. La hitbox se calcula en el servidor (no se confia en el cliente)
]]
MeleeAttackRemote.OnServerEvent:Connect(function(player)
	-- Rate limit (primera línea): el cooldown real sigue en los Stats.
	if not RateLimiter.allow(player, "MeleeAttack", 5, 6) then return end

	-- Validar que el jugador existe y tiene personaje
	if not player or not player.Character then return end

	local character = player.Character
	local stats = StatsModule.GetStats(character)
	if not stats then return end

	-- Validar que sea Devilish
	local role = stats:FindFirstChild("Role")
	if not role or role.Value ~= StatsModule.Role.Devilish then return end

	-- Verificar si es Neuro (para Fame tracking)
	local isNeuro = character:GetAttribute("CharacterName") == "Neuro"

	-- Validar que este vivo
	local isAlive = stats:FindFirstChild("IsAlive")
	if not isAlive or not isAlive.Value then return end

	-- Validar estado (no puede atacar si esta stuneado o derribado)
	local state = stats:FindFirstChild("State")
	if state and state.Value ~= StatsModule.CharacterState.Normal then return end

	-- == DEBOUNCE ESTRICTO: verificar flag isAttacking ==
	local attackState = serverAttackState[player]
	if attackState and attackState.isAttacking then
		return -- Ya esta procesando un ataque, ignorar
	end

	-- == VALIDACION DE COOLDOWN CON os.clock() ==
	local lastAttackTime = stats:FindFirstChild("LastAttackTime")
	local attackCooldown = stats:FindFirstChild("AttackCooldown")
	if not (lastAttackTime and attackCooldown) then return end

	local currentTime = os.clock()
	if currentTime - lastAttackTime.Value < attackCooldown.Value then
		return -- Todavia en cooldown
	end

	-- == MARCAR INICIO DE ATAQUE ==
	-- Inicializar estado si no existe
	if not attackState then
		attackState = { isAttacking = false, lastTick = 0 }
		serverAttackState[player] = attackState
	end
	attackState.isAttacking = true
	attackState.lastTick = currentTime

	-- Actualizar tiempo del ultimo ataque inmediatamente
	lastAttackTime.Value = currentTime

	-- Stan en modo láser (CambioArma): el M1 es el láser de StanAbilities, no el golpe cuerpo a cuerpo.
	-- Antes CambioArma solo cambiaba un atributo que nadie leía.
	if character:GetAttribute("CharacterName") == "Stan.oma.png" and character:GetAttribute("LaserModeActive") then
		task.spawn(function()
			local ok, err = pcall(function()
				require(game:GetService("ServerScriptService").ServerModules.StanAbilities).ExecuteM1(character)
			end)
			if not ok then
				warn("[CombatServer] Error en el láser de Stan: " .. tostring(err))
			end
			attackState.isAttacking = false -- liberar el debounce aunque falle
		end)
		return
	end

	-- Obtener parametros del ataque desde los stats
	local attackRange = stats:FindFirstChild("AttackRange")
	local attackDamage = stats:FindFirstChild("AttackDamage")
	if not (attackRange and attackDamage) then
		-- Si faltan stats, liberar el flag y salir
		attackState.isAttacking = false
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		attackState.isAttacking = false
		return
	end

	-- Datos de depuracion de hitbox: solo para desarrolladores (Studio / DevAuth)
	if DebugHitboxRemote then
		require(game:GetService("ServerScriptService").ServerModules.DevAuth).fireAuthorized(DebugHitboxRemote, {
			type = "Box",
			cframe = hrp.CFrame * CFrame.new(0, 0, -attackRange.Value / 2),
			size = Vector3.new(attackRange.Value * 2, attackRange.Value * 2, attackRange.Value * 2),
			duration = 0.5,
		})
	end

	-- == EJECUTAR HITBOX MELEE EN EL SERVIDOR (con pcall de proteccion) ==
	-- La tabla hitRegister dentro de PerformMeleeHit es LOCAL a esta llamada,
	-- por lo que cada ataque empieza con una tabla limpia.
	-- Todo el bloque se envuelve en pcall para garantizar que el flag
	-- isAttacking se libere SIEMPRE, incluso si hay un error.
	local execSuccess, execError = pcall(function()
		-- Tabla local para recolectar detalles de cada impacto exitoso.
		-- Se envia toda la informacion en un solo evento MeleeSwing,
		-- eliminando la desincronizacion entre el contador del servidor
		-- y el contador del cliente.
		local hitDetails = {}

		local hitCharacters = HitboxSystem.PerformMeleeHit(
			character,
			attackRange.Value,
			attackDamage.Value,
			function(hitCharacter, hitPart)
				-- Aplicar dano al personaje impactado
				local result, status = StatsModule.ApplyDamage(hitCharacter, attackDamage.Value)

				if result then
					-- Si el ataque impacto, ganar absorcion
					StatsModule.AddAbsorption(character, MatchConfig.Devilish.AbsorptionPerHit)

					-- == FAME TRACKING (Neuro pasiva) ==
					-- M1 Exitoso: +10 Fame
					if isNeuro then
						StatsModule.AddFame(character, 10)
					end

					-- Registrar detalles del impacto para enviar al cliente
					table.insert(hitDetails, {
						target = hitCharacter.Name,
						damage = attackDamage.Value,
						status = status,
					})

					-- Reproducir sonido de impacto en el personaje golpeado (server-side)
					local hitHRP = hitCharacter:FindFirstChild("HumanoidRootPart")
					if hitHRP then
						VFXModule.PlaySound3D(hitHRP, VFXModule.Sounds.MeleeHit, 0.6)
					end
				end
			end
		)

		-- == FAME TRACKING: M1 Fallido (Neuro pasiva) ==
		-- Si no impacto a nadie, -2 Fame
		if isNeuro and #hitDetails == 0 then
			StatsModule.AddFame(character, -2)
		end

		-- Notificar al cliente con TODOS los detalles del ataque en un solo evento.
		-- Esto elimina la desincronizacion: el cliente recibe hitCount y
		-- los detalles de cada impacto en el mismo mensaje.
		if AbilityResultRemote then
			AbilityResultRemote:FireClient(player, "MeleeSwing", {
				hitCount = #hitDetails,
				hits = hitDetails,
			})
		end

		-- Reproducir sonido de swing en el atacante (server-side)
		VFXModule.PlaySound3D(hrp, VFXModule.Sounds.MeleeSwing, 0.4)
	end)

	-- == LIBERAR FLAG DE ATAQUE (SIEMPRE, incluso si hubo error) ==
	-- Este es el punto CRITICO: si no se libera el flag, el jugador
	-- queda bloqueado y no puede volver a atacar (el bug de "2 golpes y nada").
	attackState.isAttacking = false

	if not execSuccess then
		warn("[CombatServer] Error durante ejecucion de ataque de " .. player.Name .. ": " .. tostring(execError))
	end
end)

-- == LIMPIEZA AL DESCONECTAR ==
-- Eliminar el estado de ataque de jugadores que se van para evitar memory leaks.
game:GetService("Players").PlayerRemoving:Connect(function(player)
	serverAttackState[player] = nil
end)

print("[CombatServer] Sistema de combate melee inicializado correctamente.")
