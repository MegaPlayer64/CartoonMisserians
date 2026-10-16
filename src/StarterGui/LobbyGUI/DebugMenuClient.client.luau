--[[
	DebugMenuClient (LocalScript)
	Ubicacion: StarterGui.DebugMenu (como hijo del ScreenGui DebugMenu)

	Menú de depuración con toggles para visualizar hitboxes.

	Funciones:
	  a) "Mostrar Hitboxes de Jugadores": Activa/desactiva SelectionBox
	     alrededor del BoundingBox de cada personaje en el Workspace.
	  b) "Mostrar Hitboxes de Ataques/Habilidades": Recibe el evento
	     'DebugHitbox' del servidor y genera una parte temporal con
	     SelectionBox indicando el área impactada.

	Dependencias:
	  - ReplicatedStorage.Framework.Remotes.DebugHitbox (RemoteEvent)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local DebugHitboxRemote = Remotes:WaitForChild("DebugHitbox")

-- Referencias a la UI
local gui = script.Parent
local debugPanel = gui:WaitForChild("DebugPanel")
local toggleButton = gui.LeftListButtons.Options:WaitForChild("Picture")
local toggle1 = debugPanel:WaitForChild("Toggle1")
local toggle2 = debugPanel:WaitForChild("Toggle2")
local checkbox1 = toggle1:WaitForChild("Checkbox")
local checkbox2 = toggle2:WaitForChild("Checkbox")

-- == ESTADO DE TOGGLES ==
local showPlayerHitboxes = false
local showAttackHitboxes = false

-- Tabla de SelectionBox activas para hitboxes de jugadores
local playerSelectionBoxes = {}

-- == COLORES DE TOGGLE ==
local COLOR_OFF = Color3.fromRGB(40, 40, 40)
local COLOR_ON = Color3.fromRGB(50, 200, 50)

--[[
	Actualiza el color del checkbox segun su estado.
]]
local function updateCheckboxVisual(checkbox, isOn)
	checkbox.BackgroundColor3 = isOn and COLOR_ON or COLOR_OFF
	checkbox.Text = isOn and "✓" or ""
end

--[[
	Crea o actualiza una SelectionBox alrededor del BoundingBox de un personaje.
]]
local function updatePlayerHitbox(character)
	if not showPlayerHitboxes then
		-- Si esta desactivado, limpiar
		local sb = playerSelectionBoxes[character]
		if sb then
			sb:Destroy()
			playerSelectionBoxes[character] = nil
		end
		return
	end

	-- Solo procesar personajes con Humanoid (jugadores o NPCs)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Obtener o crear la SelectionBox
	local sb = playerSelectionBoxes[character]
	if not sb then
		sb = Instance.new("SelectionBox")
		sb.LineThickness = 0.15
		sb.Color3 = Color3.fromRGB(0, 255, 100)
		sb.SurfaceTransparency = 0.5
		sb.Parent = character
		playerSelectionBoxes[character] = sb
	end

	-- Usar el HumanoidRootPart como referencia para la SelectionBox
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		sb.Adornee = hrp
	else
		sb.Adornee = character
	end
end

--[[
	Limpia todas las SelectionBox de jugadores.
]]
local function clearAllPlayerHitboxes()
	for character, sb in pairs(playerSelectionBoxes) do
		if sb then
			sb:Destroy()
		end
	end
	playerSelectionBoxes = {}
end

--[[
	Recorre todos los personajes del workspace y actualiza sus hitboxes visuales.
]]
local function refreshAllPlayerHitboxes()
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("Model") and descendant:FindFirstChildOfClass("Humanoid") then
			updatePlayerHitbox(descendant)
		end
	end
end

--[[
	Crea una visualizacion temporal de una hitbox de ataque/habilidad.
	Recibe los datos del servidor via DebugHitbox RemoteEvent.

	Datos esperados:
		type     -> "Box" | "Ray" | "Sphere"
		position -> Vector3 (centro o inicio)
		size     -> Vector3 (para Box) o nil
		endPoint -> Vector3 (para Ray) o nil
		radius   -> number (para Sphere) o nil
		duration -> number (segundos visibles, default 1.0)
]]
local function showAttackHitbox(data)
	if not showAttackHitboxes then return end
	if not data or not data.type then return end

	local duration = data.duration or 1.0

	if data.type == "Box" then
		-- Crear una Part transparente con SelectionBox
		local part = Instance.new("Part")
		part.Name = "DebugHitbox_Box"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Transparency = 1
		part.Size = data.size or Vector3.new(4, 4, 4)
		part.CFrame = data.cframe or CFrame.new(data.position or Vector3.zero)
		part.Parent = workspace

		local sb = Instance.new("SelectionBox")
		sb.Adornee = part
		sb.LineThickness = 0.2
		sb.Color3 = Color3.fromRGB(255, 50, 50)
		sb.SurfaceTransparency = 0.3
		sb.Parent = part

		task.delay(duration, function()
			part:Destroy()
		end)

	elseif data.type == "Ray" then
		-- Crear una Part delgada que representa el rayo
		local origin = data.position or Vector3.zero
		local endPoint = data.endPoint or (origin + Vector3.new(0, 0, -10))
		local distance = (origin - endPoint).Magnitude

		local part = Instance.new("Part")
		part.Name = "DebugHitbox_Ray"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Transparency = 1
		part.Size = Vector3.new(0.5, 0.5, distance)
		part.CFrame = CFrame.lookAt(origin, endPoint) * CFrame.new(0, 0, -distance / 2)
		part.Parent = workspace

		local sb = Instance.new("SelectionBox")
		sb.Adornee = part
		sb.LineThickness = 0.2
		sb.Color3 = Color3.fromRGB(255, 200, 0)
		sb.SurfaceTransparency = 0.3
		sb.Parent = part

		task.delay(duration, function()
			part:Destroy()
		end)

	elseif data.type == "Sphere" then
		-- Crear una Part esferica
		local radius = data.radius or 5

		local part = Instance.new("Part")
		part.Name = "DebugHitbox_Sphere"
		part.Shape = Enum.PartType.Ball
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Transparency = 1
		part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
		part.Position = data.position or Vector3.zero
		part.Parent = workspace

		local sb = Instance.new("SelectionBox")
		sb.Adornee = part
		sb.LineThickness = 0.2
		sb.Color3 = Color3.fromRGB(255, 100, 255)
		sb.SurfaceTransparency = 0.3
		sb.Parent = part

		task.delay(duration, function()
			part:Destroy()
		end)
	end
end

-- == MANEJO DE UI ==

-- Abrir/cerrar el panel de debug
toggleButton.MouseButton1Click:Connect(function()
	debugPanel.Visible = not debugPanel.Visible
end)

-- Toggle 1: Hitboxes de jugadores
checkbox1.MouseButton1Click:Connect(function()
	showPlayerHitboxes = not showPlayerHitboxes
	updateCheckboxVisual(checkbox1, showPlayerHitboxes)

	if showPlayerHitboxes then
		refreshAllPlayerHitboxes()
	else
		clearAllPlayerHitboxes()
	end
end)

-- Toggle 2: Hitboxes de ataques
checkbox2.MouseButton1Click:Connect(function()
	showAttackHitboxes = not showAttackHitboxes
	updateCheckboxVisual(checkbox2, showAttackHitboxes)
end)

-- == ACTUALIZACION CONTINUA DE HITBOXES DE JUGADORES ==
-- Usar Heartbeat para mantener las SelectionBox actualizadas
-- (los personajes pueden aparecer/desaparecer durante la partida)
local RunService = game:GetService("RunService")

RunService.Heartbeat:Connect(function()
	if not showPlayerHitboxes then return end

	-- Actualizar personajes existentes
	for character, sb in pairs(playerSelectionBoxes) do
		if not character.Parent or not sb.Parent then
			-- El personaje fue eliminado, limpiar
			if sb then sb:Destroy() end
			playerSelectionBoxes[character] = nil
		else
			updatePlayerHitbox(character)
		end
	end

	-- Buscar nuevos personajes que no tengan SelectionBox
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("Model") and descendant:FindFirstChildOfClass("Humanoid") then
			if not playerSelectionBoxes[descendant] then
				updatePlayerHitbox(descendant)
			end
		end
	end
end)

-- == RECEPCION DE HITBOXES DE ATAQUE DESDE EL SERVIDOR ==

DebugHitboxRemote.OnClientEvent:Connect(function(data)
	showAttackHitbox(data)
end)

-- Inicializar estado visual de los checkboxes
updateCheckboxVisual(checkbox1, showPlayerHitboxes)
updateCheckboxVisual(checkbox2, showAttackHitboxes)

print("[DebugMenuClient] Menú de depuración inicializado correctamente.")