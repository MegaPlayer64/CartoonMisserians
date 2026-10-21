--[[
	CharacterSelectionClient (LocalScript)
	Ubicacion: StarterGui.LobbyGUI.CharacterSelectionClient

	Construye el menu de seleccion de personajes dentro de LobbyGUI.
	El panel esta OCULTO por defecto y se abre al hacer clic en el boton
	"Inventory" (LobbyGUI.LeftListButtons.Inventory.Picture).
	Se puede cerrar con un boton de cierre o haciendo clic fuera del panel.

	Al hacer clic en un boton de personaje:
	  1. Guarda la seleccion localmente
	  2. Envia la solicitud al servidor via SelectCharacterRemote
	  3. Actualiza la UI resaltando el personaje seleccionado

	Dependencias:
	  - ReplicatedStorage.Framework.CharacterDatabase
	  - ReplicatedStorage.Framework.Remotes.SelectCharacterRemote (RemoteEvent)
	  - StarterGui.LobbyGUI (ScreenGui)
	  - LobbyGUI.LeftListButtons.Inventory.Picture (ImageButton)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local CharacterDatabase = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("CharacterDatabase"))

local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local SelectCharacterRemote = Remotes:WaitForChild("SelectCharacterRemote")

local PlayerGui = player:WaitForChild("PlayerGui")
local LobbyGUI = PlayerGui:WaitForChild("LobbyGUI")

-- == ESTADO LOCAL DE SELECCION ==
local localSelection = {
	Toonflow = CharacterDatabase.DefaultToonflow,
	Devilish = CharacterDatabase.DefaultDevilish,
}

-- Leer atributos iniciales del jugador (pueden haber sido seteados por el servidor)
local attrToonflow = player:GetAttribute("SelectedToonflow")
local attrDevilish = player:GetAttribute("SelectedDevilish")
if attrToonflow then localSelection.Toonflow = attrToonflow end
if attrDevilish then localSelection.Devilish = attrDevilish end

-- Referencias a los botones creados para poder actualizar el resaltado
local toonButtons = {}
local devilishButtons = {}

-- Referencia al panel (se crea mas adelante)
local selectionPanel = nil

--[[
	Crea un boton de personaje con icono de color placeholder y texto.
	Retorna el TextButton creado y su UIStroke.
]]
local function createCharacterButton(parent, characterData, isSelected)
	local button = Instance.new("TextButton")
	button.Name = "Btn_" .. characterData.Name
	button.Size = UDim2.new(1, -10, 0, 70)
	button.Position = UDim2.new(0, 5, 0, 0)
	button.BackgroundColor3 = isSelected and Color3.fromRGB(60, 120, 60) or Color3.fromRGB(40, 40, 40)
	button.BackgroundTransparency = 0.1
	button.Text = ""
	button.AutoButtonColor = true
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = isSelected and 3 or 1
	stroke.Color = isSelected and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(80, 80, 80)
	stroke.Parent = button

	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 50, 0, 50)
	icon.Position = UDim2.new(0, 10, 0.5, -25)
	icon.BackgroundColor3 = characterData.Color
	icon.Parent = button

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 6)
	iconCorner.Parent = icon

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "CharName"
	nameLabel.Size = UDim2.new(1, -80, 0, 25)
	nameLabel.Position = UDim2.new(0, 70, 0, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = characterData.DisplayName
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 16
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = button

	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "CharDesc"
	descLabel.Size = UDim2.new(1, -80, 0, 30)
	descLabel.Position = UDim2.new(0, 70, 0, 33)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = characterData.Description
	descLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 12
	descLabel.TextWrapped = true
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.TextTruncate = Enum.TextTruncate.AtEnd
	descLabel.Parent = button

	return button, stroke
end

--[[
	Actualiza el resaltado visual de los botones de una categoria.
]]
local function updateButtonHighlight(buttons, selectedName)
	for name, data in pairs(buttons) do
		local isSelected = (name == selectedName)
		data.button.BackgroundColor3 = isSelected and Color3.fromRGB(60, 120, 60) or Color3.fromRGB(40, 40, 40)
		data.stroke.Thickness = isSelected and 3 or 1
		data.stroke.Color = isSelected and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(80, 80, 80)
	end
end

--[[
	Maneja el clic en un boton de personaje.
]]
local function onCharacterClicked(characterType, characterName)
	localSelection[characterType] = characterName
	SelectCharacterRemote:FireServer(characterType, characterName)

	-- El resaltado es optimista. Si el servidor descarta la petición (p. ej. por clics muy rápidos)
	-- se resincroniza con el atributo real para que la UI no muestre una selección que no existe.
	task.delay(1, function()
		local attrName = (characterType == CharacterDatabase.CharacterType.Toonflow) and "SelectedToonflow" or "SelectedDevilish"
		local actual = player:GetAttribute(attrName)
		if actual and actual ~= localSelection[characterType] then
			localSelection[characterType] = actual
			updateButtonHighlight((characterType == CharacterDatabase.CharacterType.Toonflow) and toonButtons or devilishButtons, actual)
		end
	end)

	if characterType == CharacterDatabase.CharacterType.Toonflow then
		updateButtonHighlight(toonButtons, characterName)
	else
		updateButtonHighlight(devilishButtons, characterName)
	end

	print("[CharacterSelectionClient] Seleccionado " .. characterType .. ": " .. characterName)
end

--[[
	Construye la seccion de Toonflows dentro del panel de seleccion.
]]
local function buildToonSection(parent)
	local title = Instance.new("TextLabel")
	title.Name = "ToonTitle"
	title.Size = UDim2.new(1, 0, 0, 30)
	title.BackgroundTransparency = 1
	title.Text = "TOONFLOWS"
	title.TextColor3 = Color3.fromRGB(100, 200, 255)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.Parent = parent

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ToonList"
	scrollFrame.Size = UDim2.new(1, 0, 1, -35)
	scrollFrame.Position = UDim2.new(0, 0, 0, 35)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 150, 255)
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = scrollFrame

	for _, toonData in ipairs(CharacterDatabase.Toonflows) do
		local isSelected = (localSelection.Toonflow == toonData.Name)
		local btn, stroke = createCharacterButton(scrollFrame, toonData, isSelected)
		toonButtons[toonData.Name] = { button = btn, stroke = stroke }

		btn.MouseButton1Click:Connect(function()
			onCharacterClicked(CharacterDatabase.CharacterType.Toonflow, toonData.Name)
		end)
	end
end

--[[
	Construye la seccion de Devilishes dentro del panel de seleccion.
]]
local function buildDevilishSection(parent)
	local title = Instance.new("TextLabel")
	title.Name = "DevilishTitle"
	title.Size = UDim2.new(1, 0, 0, 30)
	title.BackgroundTransparency = 1
	title.Text = "DEVILISHES"
	title.TextColor3 = Color3.fromRGB(255, 80, 80)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.Parent = parent

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "DevilishList"
	scrollFrame.Size = UDim2.new(1, 0, 1, -35)
	scrollFrame.Position = UDim2.new(0, 0, 0, 35)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(255, 80, 80)
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = scrollFrame

	for _, devilishData in ipairs(CharacterDatabase.Devilishes) do
		local isSelected = (localSelection.Devilish == devilishData.Name)
		local btn, stroke = createCharacterButton(scrollFrame, devilishData, isSelected)
		devilishButtons[devilishData.Name] = { button = btn, stroke = stroke }

		btn.MouseButton1Click:Connect(function()
			onCharacterClicked(CharacterDatabase.CharacterType.Devilish, devilishData.Name)
		end)
	end
end

--[[
	Construye el panel principal de seleccion de personajes dentro de LobbyGUI.
	El panel empieza OCULTO (Visible = false).
]]
local function buildSelectionPanel()
	local existing = LobbyGUI:FindFirstChild("CharacterSelectionPanel")
	if existing then
		existing:Destroy()
	end

	-- Fondo oscurecido que cubre toda la pantalla (cierra al hacer clic)
	local backdrop = Instance.new("Frame")
	backdrop.Name = "CharacterSelectionPanel"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.Position = UDim2.new(0, 0, 0, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.Visible = false
	backdrop.ZIndex = 10
	backdrop.Parent = LobbyGUI

	selectionPanel = backdrop

	-- Panel principal centrado
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	-- Antes: 500x400 px fijos; en un móvil apaisado (~390 px de alto) el panel se salía de la
	-- pantalla y no se podía llegar al botón de cierre.
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.new(0.94, 0, 0.9, 0)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	local panelLimit = Instance.new("UISizeConstraint")
	panelLimit.MaxSize = Vector2.new(500, 400)
	panelLimit.Parent = panel
	panel.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	panel.BackgroundTransparency = 0.05
	panel.ZIndex = 11
	panel.Parent = backdrop

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Thickness = 2
	panelStroke.Color = Color3.fromRGB(80, 80, 100)
	panelStroke.Parent = panel

	-- Titulo del panel
	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, -50, 0, 40)
	header.Position = UDim2.new(0, 0, 0, 0)
	header.BackgroundTransparency = 1
	header.Text = "SELECCION DE PERSONAJES"
	header.TextColor3 = Color3.fromRGB(255, 255, 255)
	header.Font = Enum.Font.GothamBold
	header.TextSize = 20
	header.ZIndex = 12
	header.Parent = panel

	-- Boton de cierre (X) en la esquina superior derecha
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -40, 0, 4)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
	closeBtn.BackgroundTransparency = 0.1
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 18
	closeBtn.ZIndex = 12
	closeBtn.Parent = panel

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		backdrop.Visible = false
	end)

	-- Aseguramos que el panel interno absorba los clics para que no traspasen al backdrop
	panel.Active = true 

	-- Cerrar al hacer clic en el backdrop
	backdrop.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			backdrop.Visible = false
		end
	end)

	-- Separador Toons (izquierda)
	local toonSection = Instance.new("Frame")
	toonSection.Name = "ToonSection"
	toonSection.Size = UDim2.new(0.5, -5, 1, -50)
	toonSection.Position = UDim2.new(0, 5, 0, 45)
	toonSection.BackgroundTransparency = 1
	toonSection.ZIndex = 11
	toonSection.Parent = panel

	buildToonSection(toonSection)

	-- Separador Devilishes (derecha)
	local devilishSection = Instance.new("Frame")
	devilishSection.Name = "DevilishSection"
	devilishSection.Size = UDim2.new(0.5, -5, 1, -50)
	devilishSection.Position = UDim2.new(0.5, 0, 0, 45)
	devilishSection.BackgroundTransparency = 1
	devilishSection.ZIndex = 11
	devilishSection.Parent = panel

	buildDevilishSection(devilishSection)

	-- Linea divisoria central
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(0, 2, 1, -50)
	divider.Position = UDim2.new(0.5, -1, 0, 45)
	divider.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	divider.BorderSizePixel = 0
	divider.ZIndex = 11
	divider.Parent = panel
end

-- == CONSTRUIR LA UI ==
buildSelectionPanel()

-- == CONECTAR EL BOTON INVENTORY ==
-- Buscar el boton Inventory en LeftListButtons y conectar su clic
-- para abrir/cerrar el panel de seleccion
local function connectInventoryButton()
	local leftList = LobbyGUI:FindFirstChild("LeftListButtons")
	if not leftList then
		warn("[CharacterSelectionClient] No se encontro LeftListButtons en LobbyGUI")
		return
	end

	local inventoryFrame = leftList:FindFirstChild("Inventory")
	if not inventoryFrame then
		warn("[CharacterSelectionClient] No se encontro Inventory en LeftListButtons")
		return
	end

	-- El boton clickeable es el ImageButton dentro de Inventory
	local pictureBtn = inventoryFrame:FindFirstChild("Picture")
	if not pictureBtn or not pictureBtn:IsA("ImageButton") then
		-- Si no hay ImageButton, conectar el Frame entero como boton
		-- Crear un TextButton transparente sobre el Frame para capturar clics
		local clickCatcher = Instance.new("TextButton")
		clickCatcher.Name = "ClickCatcher"
		clickCatcher.Size = UDim2.new(1, 0, 1, 0)
		clickCatcher.BackgroundTransparency = 1
		clickCatcher.Text = ""
		clickCatcher.Parent = inventoryFrame

		clickCatcher.MouseButton1Click:Connect(function()
			if selectionPanel then
				selectionPanel.Visible = not selectionPanel.Visible
			end
		end)
		return
	end

	pictureBtn.MouseButton1Click:Connect(function()
		if selectionPanel then
			selectionPanel.Visible = not selectionPanel.Visible
		end
	end)

	-- Tambien permitir clic en el TextLabel del Inventory
	local textLabel = inventoryFrame:FindFirstChild("Text")
	if textLabel and textLabel:IsA("TextLabel") then
		-- Hacer el TextLabel clickable
		textLabel.Active = true
		-- No se puede conectar MouseButton1Click en TextLabel, asi que
		-- el ImageButton es suficiente como area de clic
	end
end

connectInventoryButton()

-- Si el lobby se oculta (empieza la partida) el panel se cierra; antes reaparecía abierto al volver.
LobbyGUI:GetPropertyChangedSignal("Enabled"):Connect(function()
	if not LobbyGUI.Enabled and selectionPanel then
		selectionPanel.Visible = false
	end
end)

-- == ESCUCHAR CAMBIOS DE ATRIBUTOS DESDE EL SERVIDOR ==
player:GetAttributeChangedSignal("SelectedToonflow"):Connect(function()
	local newToon = player:GetAttribute("SelectedToonflow")
	if newToon and newToon ~= localSelection.Toonflow then
		localSelection.Toonflow = newToon
		updateButtonHighlight(toonButtons, newToon)
	end
end)

player:GetAttributeChangedSignal("SelectedDevilish"):Connect(function()
	local newDevilish = player:GetAttribute("SelectedDevilish")
	if newDevilish and newDevilish ~= localSelection.Devilish then
		localSelection.Devilish = newDevilish
		updateButtonHighlight(devilishButtons, newDevilish)
	end
end)

print("[CharacterSelectionClient] Sistema de seleccion de personajes inicializado (GUI en LobbyGUI).")