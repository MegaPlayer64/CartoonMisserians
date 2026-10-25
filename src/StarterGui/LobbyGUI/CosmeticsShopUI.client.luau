--[[
	CosmeticsShopUI (LocalScript)
	StarterGui.LobbyGUI.CosmeticsShopUI

	Interfaz de Tienda e Inventario para Cosmetics.
	Base modular escalable para Emotes, Personajes y Skins.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local lobbyGUI = script.Parent

local Framework = ReplicatedStorage:WaitForChild("Framework")
local CosmeticsDatabase = require(Framework:WaitForChild("CosmeticsDatabase"))
local Remotes = Framework:WaitForChild("Remotes")
local BuyCosmeticRemote = Remotes:WaitForChild("BuyCosmetic")
local EquipEmoteRemote = Remotes:WaitForChild("EquipEmote")

-- == ESTADO ==
local equippedEmotes = { "", "", "", "", "", "" }
local ownedEmotes = {}
local currentSlotPicker = nil -- emoteId que se está asignando a un slot
local isShopOpen = false
local buyInFlight = false

-- == HELPERS DE ATRIBUTOS ==

local function refreshOwned()
	local raw = player:GetAttribute("OwnedEmotes")
	ownedEmotes = {}
	if raw then
		local ok, data = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if ok and type(data) == "table" then
			for _, id in ipairs(data) do
				ownedEmotes[id] = true
				table.insert(ownedEmotes, id)
			end
		end
	end
end

local function refreshEquipped()
	local raw = player:GetAttribute("EquippedEmotes")
	if raw then
		local ok, data = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if ok and type(data) == "table" then
			for i = 1, 6 do
				equippedEmotes[i] = data[i] or ""
			end
		end
	end
end

local function ownsEmote(emoteId)
	for _, id in ipairs(ownedEmotes) do
		if id == emoteId then return true end
	end
	return false
end

local function getEquippedSlot(emoteId)
	for i = 1, 6 do
		if equippedEmotes[i] == emoteId then return i end
	end
	return nil
end

-- == CREACIÓN DE UI PRINCIPAL ==

local mainFrame = Instance.new("Frame")
mainFrame.Name = "CosmeticsShop"
mainFrame.Size = UDim2.new(0, 700, 0, 500)
mainFrame.Position = UDim2.new(0.5, -350, 0.5, -250)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
mainFrame.Visible = false
mainFrame.Parent = lobbyGUI

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = mainFrame

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(80, 80, 100)
mainStroke.Thickness = 2
mainStroke.Parent = mainFrame

-- == HEADER ==

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 50)
header.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
header.BorderSizePixel = 0
header.Parent = mainFrame

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 12)
headerCorner.Parent = header

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(0, 200, 1, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "TIENDA DE COSMETICOS"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 18
titleLabel.TextXAlignment = Enum.TextXAlignment.Center
titleLabel.Parent = header

-- Coins display
local coinsLabel = Instance.new("TextLabel")
coinsLabel.Name = "CoinsLabel"
coinsLabel.Size = UDim2.new(0, 150, 1, 0)
coinsLabel.Position = UDim2.new(1, -160, 0, 0)
coinsLabel.BackgroundTransparency = 1
coinsLabel.Text = "Coins: 0"
coinsLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
coinsLabel.Font = Enum.Font.GothamBold
coinsLabel.TextSize = 16
coinsLabel.TextXAlignment = Enum.TextXAlignment.Right
coinsLabel.Parent = header

-- Botón cerrar
local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 40, 0, 40)
closeButton.Position = UDim2.new(0, 10, 0, 5)
closeButton.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 18
closeButton.Parent = header

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = closeButton

closeButton.MouseButton1Click:Connect(function()
	toggleShop(false)
end)

-- == TABS ==

local tabContainer = Instance.new("Frame")
tabContainer.Size = UDim2.new(1, -20, 0, 40)
tabContainer.Position = UDim2.new(0, 10, 0, 60)
tabContainer.BackgroundTransparency = 1
tabContainer.Parent = mainFrame

local tabList = Instance.new("UIListLayout")
tabList.FillDirection = Enum.FillDirection.Horizontal
tabList.Padding = UDim.new(0, 8)
tabList.Parent = tabContainer

local tabs = {}
local currentTab = "Emotes"

local function createTab(name, isActive)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 150, 0, 40)
	btn.BackgroundColor3 = isActive and Color3.fromRGB(60, 60, 90) or Color3.fromRGB(35, 35, 45)
	btn.Text = name
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.Parent = tabContainer

	local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn

	btn.MouseButton1Click:Connect(function()
		currentTab = name
		for tabName, tabBtn in pairs(tabs) do
			tabBtn.BackgroundColor3 = (tabName == name) and Color3.fromRGB(60, 60, 90) or Color3.fromRGB(35, 35, 45)
		end
		refreshContent()
	end)

	tabs[name] = btn
	return btn
end

createTab("Emotes", true)
createTab("Bailes", false)
createTab("Personajes", false)
createTab("Skins", false)

-- == ÁREA DE CONTENIDO (SCROLL) ==

local contentArea = Instance.new("ScrollingFrame")
contentArea.Size = UDim2.new(1, -20, 1, -120)
contentArea.Position = UDim2.new(0, 10, 0, 110)
contentArea.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
contentArea.BorderSizePixel = 0
contentArea.ScrollBarThickness = 6
contentArea.AutomaticCanvasSize = Enum.AutomaticSize.Y
contentArea.Parent = mainFrame

local contentCorner = Instance.new("UICorner")
contentCorner.CornerRadius = UDim.new(0, 8)
contentCorner.Parent = contentArea

local contentGrid = Instance.new("UIGridLayout")
contentGrid.CellSize = UDim2.new(0, 160, 0, 200)
contentGrid.CellPadding = UDim2.new(0, 12, 0, 12)
contentGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
contentGrid.Parent = contentArea

-- == SLOT PICKER (Para equipar emotes) ==

local slotPicker = Instance.new("Frame")
slotPicker.Name = "SlotPicker"
slotPicker.Size = UDim2.new(0, 300, 0, 250)
slotPicker.Position = UDim2.new(0.5, -150, 0.5, -125)
slotPicker.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
slotPicker.Visible = false
slotPicker.Parent = lobbyGUI

local spCorner = Instance.new("UICorner")
spCorner.CornerRadius = UDim.new(0, 10)
spCorner.Parent = slotPicker

local spStroke = Instance.new("UIStroke")
spStroke.Color = Color3.fromRGB(100, 100, 140)
spStroke.Thickness = 2
spStroke.Parent = slotPicker

local spTitle = Instance.new("TextLabel")
spTitle.Size = UDim2.new(1, 0, 0, 40)
spTitle.BackgroundTransparency = 1
spTitle.Text = "SELECCIONA UN SLOT"
spTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
spTitle.Font = Enum.Font.GothamBold
spTitle.TextSize = 16
spTitle.Parent = slotPicker

local spClose = Instance.new("TextButton")
spClose.Size = UDim2.new(0, 30, 0, 30)
spClose.Position = UDim2.new(1, -35, 0, 5)
spClose.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
spClose.Text = "X"
spClose.TextColor3 = Color3.fromRGB(255, 255, 255)
spClose.Font = Enum.Font.GothamBold
spClose.TextSize = 14
spClose.Parent = slotPicker

local spCloseCorner = Instance.new("UICorner")
spCloseCorner.CornerRadius = UDim.new(0, 6)
spCloseCorner.Parent = spClose

spClose.MouseButton1Click:Connect(function()
	slotPicker.Visible = false
	currentSlotPicker = nil
end)

-- Crear 6 botones de slot en el picker
local slotButtons = {}
for i = 1, 6 do
	local row = math.floor((i - 1) / 3)
	local col = (i - 1) % 3

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 70, 0, 70)
	btn.Position = UDim2.new(0, 30 + col * 85, 0, 55 + row * 85)
	btn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	btn.Text = "Slot " .. i
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.Parent = slotPicker

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn

	slotButtons[i] = btn

	btn.MouseButton1Click:Connect(function()
		if currentSlotPicker then
			EquipEmoteRemote:FireServer(i, currentSlotPicker)
		end
		slotPicker.Visible = false
		currentSlotPicker = nil
		task.wait(0.2)
		refreshContent()
	end)
end

-- == CREACIÓN DE TARJETAS DE EMOTE ==

local function createEmoteCard(emoteData)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(0, 160, 0, 200)
	card.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	card.Parent = contentArea

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card

	-- Imagen del cosmetico (sticker usa Image, dance usa placeholder)
	local image = Instance.new("ImageLabel")
	image.Size = UDim2.new(0, 80, 0, 80)
	image.Position = UDim2.new(0.5, -40, 0, 15)
	image.BackgroundTransparency = 1
	image.Image = emoteData.Image or "rbxassetid://7734028100"
	image.Parent = card

	-- Nombre
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 25)
	nameLabel.Position = UDim2.new(0, 0, 0, 105)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = emoteData.Name
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.Parent = card

	-- Descripción
	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, -10, 0, 30)
	descLabel.Position = UDim2.new(0, 5, 0, 130)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = emoteData.Description or ""
	descLabel.TextColor3 = Color3.fromRGB(160, 160, 170)
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 11
	descLabel.TextWrapped = true
	descLabel.Parent = card

	-- Botón de acción
	local actionBtn = Instance.new("TextButton")
	actionBtn.Size = UDim2.new(1, -20, 0, 30)
	actionBtn.Position = UDim2.new(0, 10, 1, -38)
	actionBtn.Font = Enum.Font.GothamBold
	actionBtn.TextSize = 13
	actionBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	actionBtn.Parent = card

	local actionCorner = Instance.new("UICorner")
	actionCorner.CornerRadius = UDim.new(0, 6)
	actionCorner.Parent = actionBtn

	local isOwned = ownsEmote(emoteData.Id)
	local equippedSlot = getEquippedSlot(emoteData.Id)

	if isOwned then
		if equippedSlot then
			actionBtn.Text = "EQUIPADO (" .. equippedSlot .. ")"
			actionBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
			actionBtn.MouseButton1Click:Connect(function()
				-- Desequipar
				EquipEmoteRemote:FireServer(equippedSlot, "")
				task.wait(0.2)
				refreshContent()
			end)
		else
			actionBtn.Text = "EQUIPAR"
			actionBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 140)
			actionBtn.MouseButton1Click:Connect(function()
				currentSlotPicker = emoteData.Id
				slotPicker.Visible = true
				-- Actualizar vista previa de slots
				refreshEquipped()
				for i = 1, 6 do
					local equippedId = equippedEmotes[i]
					if equippedId ~= "" then
						local emoteInfo = CosmeticsDatabase.GetEmote(equippedId)
						slotButtons[i].Text = "Slot " .. i .. "\n" .. (emoteInfo and emoteInfo.Name or "?")
						slotButtons[i].BackgroundColor3 = Color3.fromRGB(80, 60, 40)
					else
						slotButtons[i].Text = "Slot " .. i
						slotButtons[i].BackgroundColor3 = Color3.fromRGB(40, 40, 55)
					end
				end
			end)
		end
	else
		actionBtn.Text = "COMPRAR $" .. emoteData.Price
		actionBtn.BackgroundColor3 = Color3.fromRGB(140, 100, 30)
		actionBtn.MouseButton1Click:Connect(function()
			if buyInFlight then return end -- evita compras duplicadas por doble clic
			buyInFlight = true
			local ok, success = pcall(function()
				return BuyCosmeticRemote:InvokeServer(emoteData.Id)
			end)
			buyInFlight = false
			if ok and success then
				refreshOwned()
				refreshContent()
			end
		end)
	end

	return card
end

-- == REFRESCAR CONTENIDO ==

function refreshContent()
	-- Limpiar contenido anterior (conservar el UIGridLayout)
	for _, child in ipairs(contentArea:GetChildren()) do
		if child ~= contentGrid then
			-- Destroy (no Parent = nil): desconecta los eventos y libera la tarjeta. Antes cada
			-- refresco (equipar, comprar, cambiar de pestaña) dejaba un catálogo entero en memoria.
			child:Destroy()
		end
	end

	if currentTab == "Emotes" then
		for _, emote in ipairs(CosmeticsDatabase.GetAllEmotes()) do
			createEmoteCard(emote)
		end
	elseif currentTab == "Bailes" then
		for _, dance in ipairs(CosmeticsDatabase.GetAllDances()) do
			createEmoteCard(dance)
		end
	elseif currentTab == "Personajes" then
		local placeholder = Instance.new("TextLabel")
		placeholder.Size = UDim2.new(1, 0, 0, 50)
		placeholder.BackgroundTransparency = 1
		placeholder.Text = "Próximamente: Personajes"
		placeholder.TextColor3 = Color3.fromRGB(150, 150, 160)
		placeholder.Font = Enum.Font.GothamBold
		placeholder.TextSize = 18
		placeholder.Parent = contentArea
	elseif currentTab == "Skins" then
		local placeholder = Instance.new("TextLabel")
		placeholder.Size = UDim2.new(1, 0, 0, 50)
		placeholder.BackgroundTransparency = 1
		placeholder.Text = "Próximamente: Skins"
		placeholder.TextColor3 = Color3.fromRGB(150, 150, 160)
		placeholder.Font = Enum.Font.GothamBold
		placeholder.TextSize = 18
		placeholder.Parent = contentArea
	end
end

-- == TOGGLE SHOP ==

function toggleShop(open, tabName)
	isShopOpen = open
	mainFrame.Visible = open
	if open then
		refreshOwned()
		refreshEquipped()
		-- Si se especifica una pestaña, cambiar a ella
		if tabName and tabs[tabName] then
			currentTab = tabName
			for tName, tBtn in pairs(tabs) do
				tBtn.BackgroundColor3 = (tName == tabName) and Color3.fromRGB(60, 60, 90) or Color3.fromRGB(35, 35, 45)
			end
		end
		refreshContent()
		updateCoinsLabel()
	end
end

function updateCoinsLabel()
	local coins = player:GetAttribute("Coins") or 0
	coinsLabel.Text = "Coins: " .. coins
end

-- == ACTUALIZAR ATRIBUTOS ==

player:GetAttributeChangedSignal("OwnedEmotes"):Connect(function()
	refreshOwned()
	if isShopOpen then refreshContent() end
end)

player:GetAttributeChangedSignal("EquippedEmotes"):Connect(function()
	refreshEquipped()
	if isShopOpen then refreshContent() end
end)

player:GetAttributeChangedSignal("Coins"):Connect(function()
	updateCoinsLabel()
end)

-- Inicializar estado	
refreshOwned()
refreshEquipped()

-- == LISTENER PARA SHOP PADS DEL LOBBY ==
-- WaitForChild: antes era FindFirstChild y, si el servidor aún no había creado el remote, los
-- pads de la tienda nunca abrían la UI.
local openShopTabRemote = Remotes:WaitForChild("OpenShopTab", 10)
if openShopTabRemote then
	openShopTabRemote.OnClientEvent:Connect(function(tabName)
		toggleShop(true, tabName)
	end)
end

print("[CosmeticsShopUI] Tienda de Cosmetics cargada.")