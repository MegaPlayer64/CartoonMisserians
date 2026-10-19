--[[
	TaskManager (ModuleScript)
	Ubicación: ServerScriptService.ServerModules.TaskManager

	Gestiona las tareas interactivas distribuidas en el mapa.
	Cada tarea usa un ProximityPrompt con la tecla 'E' (mantener presionada).
	Mientras el Toonflow interactúa, se aplica el estado 'Vulnerable'
	(SpeedMultiplier = 0). Al completar todas las tareas, notifica al MatchManager
	para abrir la salida.

	Dependencias:
	  - ReplicatedStorage.Framework.MatchConfig
	  - ServerScriptService.ServerModules.StatsModule
	  - ReplicatedStorage.Framework.Remotes.TaskProgress (RemoteEvent)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchConfig = require(ReplicatedStorage.Framework.MatchConfig)
local StatsModule = require(game:GetService("ServerScriptService").ServerModules.StatsModule)

local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local TaskProgressRemote = Remotes:WaitForChild("TaskProgress")

local TaskManager = {}

-- == ESTADO INTERNO ==
local activePrompts = {}      -- [Part] = ProximityPrompt
local completedTasks = {}
local completedCount = 0
local totalTasks = 0
local callbacks = {}

--[[
	Detiene el sistema de tareas y limpia los prompts creados.
]]
function TaskManager.Stop()
	for _, prompt in pairs(activePrompts) do
		if prompt and prompt.Parent then
			prompt:Destroy()
		end
	end
	activePrompts = {}
	completedTasks = {}
	completedCount = 0
	totalTasks = 0
	callbacks = {}
end

-- Bug 8: resetAllTasks() - Reset all tasks to incomplete without destroying prompts
function TaskManager.ResetAllTasks()
	for part, prompt in pairs(activePrompts) do
		if prompt and prompt.Parent then
			prompt.Enabled = true
		end
		-- Reset part appearance
		if part:IsA("BasePart") then
			part.Color = Color3.fromRGB(200, 200, 200)
			part.Material = Enum.Material.Plastic
		end
	end
	completedTasks = {}
	completedCount = 0
	if totalTasks > 0 then
		TaskProgressRemote:FireAllClients({
			completed = 0,
			total = totalTasks,
		})
	end
end

--[[
	Inicia el sistema de tareas para el mapa actual.

	Parámetros:
	  currentMap -> Model del mapa en juego
	  cb -> tabla de callbacks:
	    onTaskCompleted(completed, total)
	    onAllCompleted(completed, total)
]]
function TaskManager.Start(currentMap, cb)
	TaskManager.Stop()
	callbacks = cb or {}

	local tasksFolder = currentMap and currentMap:FindFirstChild("Tasks")
	if not tasksFolder then
		warn("[TaskManager] No se encontró carpeta 'Tasks' en el mapa " .. (currentMap and currentMap.Name or "nil"))
		return
	end

	-- Recolectar las partes de tarea
	local taskParts = {}
	for _, child in ipairs(tasksFolder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(taskParts, child)
		end
	end

	totalTasks = #taskParts
	if totalTasks == 0 then
		warn("[TaskManager] No hay partes de tarea en la carpeta 'Tasks'")
		return
	end

	for _, part in ipairs(taskParts) do
		local prompt = part:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.Name = "TaskPrompt"
			prompt.Parent = part
		end

		prompt.HoldDuration = MatchConfig.TaskHoldDuration
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.ActionText = "Completar tarea"
		prompt.ObjectText = part.Name
		prompt.Enabled = true

		activePrompts[part] = prompt

		-- Estado Vulnerable mientras se mantiene presionada la tecla E
		prompt.PromptButtonHoldBegan:Connect(function(player)
			local character = player and player.Character
			if character then
				StatsModule.SetSpeedMultiplier(character, 0)
			end
		end)

		prompt.PromptButtonHoldEnded:Connect(function(player)
			local character = player and player.Character
			if character then
				StatsModule.ResetSpeedMultiplier(character)
			end
		end)

		-- Tarea completada
		prompt.Triggered:Connect(function(player)
			local character = player and player.Character
			if character then
				StatsModule.ResetSpeedMultiplier(character)
			end

			-- Bug 7: Only Toonflows can complete tasks (not Devilish)
			local stats = StatsModule.GetStats(character)
			if stats then
				local role = stats:FindFirstChild("Role")
				if role and role.Value == StatsModule.Role.Devilish then
					return
				end
			end
			if character:GetAttribute("Role") == "Devilish" or character:GetAttribute("IsDevilish") then
				return
			end

			if completedTasks[part] then return end
			completedTasks[part] = true
			completedCount = completedCount + 1

			-- 1. Ocultar y desactivar el ProximityPrompt
			prompt.Enabled = false

			-- 2. Cambiar color de la parte a verde (completada)
			part.Color = Color3.fromRGB(85, 255, 127)
			part.Material = Enum.Material.Neon -- Efecto brillante para resaltar que está lista

			TaskProgressRemote:FireAllClients({
				completed = completedCount,
				total = totalTasks,
			})

			if callbacks.onTaskCompleted then
				callbacks.onTaskCompleted(completedCount, totalTasks, player)
			end

			if completedCount >= totalTasks and callbacks.onAllCompleted then
				callbacks.onAllCompleted(completedCount, totalTasks)
			end
		end)
	end

	TaskProgressRemote:FireAllClients({
		completed = 0,
		total = totalTasks,
	})
end

return TaskManager