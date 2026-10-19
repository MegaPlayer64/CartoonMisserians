--[[
	CosmeticsServer (Script)
	ServerScriptService.CosmeticsServer

	Gestiona compras, equipamiento, persistencia básica (atributos)
	y la lógica del Sticker flotante (BillboardGui + TweenService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local CosmeticsDatabase = require(ReplicatedStorage.Framework.CosmeticsDatabase)
local RateLimiter = require(game:GetService("ServerScriptService").ServerModules.RateLimiter)
local PlayerData = require(game:GetService("ServerScriptService").ServerModules.PlayerData)

local Remotes = ReplicatedStorage.Framework.Remotes
local UseEmoteRemote = Remotes:WaitForChild("UseEmote")
local BuyCosmeticRemote = Remotes:WaitForChild("BuyCosmetic")
local EquipEmoteRemote = Remotes:WaitForChild("EquipEmote")

-- == CONFIGURACIÓN ==
local EMOTE_COOLDOWN = 7 -- segundos
local EMOTE_DISPLAY_TIME = 3 -- segundos visible

-- == ESTADO POR JUGADOR ==
local playerCooldowns = {} -- [player] = tick()
local activeDanceTracks = {} -- [player] = { track = AnimationTrack, connections = {RBXScriptConnection} }

-- Forward declaration para que PlayerRemoving pueda referenciarla
local stopDance

-- == HELPERS DE ATRIBUTOS (JSON) ==

local function getOwnedEmotes(player)
	local raw = player:GetAttribute("OwnedEmotes")
	if not raw then return {} end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	return ok and type(data) == "table" and data or {}
end

local function setOwnedEmotes(player, emoteTable)
	player:SetAttribute("OwnedEmotes", HttpService:JSONEncode(emoteTable))
end

local function getEquippedEmotes(player)
	local raw = player:GetAttribute("EquippedEmotes")
	if not raw then return { "", "", "", "", "", "" } end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not ok or type(data) ~= "table" then
		return { "", "", "", "", "", "" }
	end
	-- Asegurar 6 slots
	for i = 1, 6 do
		data[i] = data[i] or ""
	end
	return data
end

local function setEquippedEmotes(player, slotList)
	player:SetAttribute("EquippedEmotes", HttpService:JSONEncode(slotList))
end

local function ownsEmote(player, emoteId)
	local owned = getOwnedEmotes(player)
	for _, id in ipairs(owned) do
		if id == emoteId then return true end
	end
	return false
end

-- == INICIALIZACIÓN DE JUGADOR ==

-- Coins / OwnedEmotes / EquippedEmotes (valores iniciales y guardados) los
-- carga PlayerData; aquí solo el estado local del script.
local function initPlayer(player)
	playerCooldowns[player] = 0
end

Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(function(player)
	playerCooldowns[player] = nil
	if stopDance then stopDance(player) end
end)

-- Inicializar jugadores ya presentes
for _, p in ipairs(Players:GetPlayers()) do
	initPlayer(p)
end

-- == LÓGICA DE USE EMOTE (Sticker flotante) ==

local function createSticker(character, emoteId)
	local head = character:FindFirstChild("Head")
	if not head then return end

	local emoteData = CosmeticsDatabase.GetEmote(emoteId)
	if not emoteData then return end

	-- Limpiar stickers anteriores
	for _, child in ipairs(head:GetChildren()) do
		if child.Name == "EmoteSticker" then
			child.Parent = nil
		end
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "EmoteSticker"
	billboard.Size = UDim2.new(0, 0, 0, 0)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = head

	local image = Instance.new("ImageLabel")
	image.Size = UDim2.new(1, 0, 1, 0)
	image.BackgroundTransparency = 1
	image.Image = emoteData.Image
	image.Parent = billboard

	-- Pop-up animación (0 -> 80x80, Back easing)
	local popTween = TweenService:Create(
		billboard,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 80, 0, 80) }
	)
	popTween:Play()

	-- Desvanecer después de EMOTE_DISPLAY_TIME segundos
	task.delay(EMOTE_DISPLAY_TIME, function()
		local fadeTween = TweenService:Create(
			image,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ ImageTransparency = 1 }
		)
		fadeTween:Play()
		fadeTween.Completed:Wait()
		billboard.Parent = nil
	end)
end

stopDance = function(player)
	local danceData = activeDanceTracks[player]
	if danceData then
		if danceData.track then
			pcall(function() danceData.track:Stop(0.3) end)
		end
		if danceData.connections then
			for _, conn in ipairs(danceData.connections) do
				conn:Disconnect()
			end
		end
		activeDanceTracks[player] = nil
	end
end

local function playDance(player, character, danceId)
	local danceData = CosmeticsDatabase.GetDance(danceId)
	if not danceData or not danceData.AnimationId then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end

	-- Detener baile anterior si existe
	stopDance(player)

	local anim = Instance.new("Animation")
	anim.AnimationId = danceData.AnimationId

	local track
	local ok = pcall(function()
		track = animator:LoadAnimation(anim)
	end)
	if not ok or not track then return end

	track.Looped = true
	track.Priority = Enum.AnimationPriority.Idle
	track:Play()

	local connections = {}

	-- Cancelar si el personaje se mueve
	table.insert(connections, humanoid.Running:Connect(function(speed)
		if speed > 1 then
			stopDance(player)
		end
	end))

	-- Cancelar si salta
	table.insert(connections, humanoid.Jumping:Connect(function()
		stopDance(player)
	end))

	-- Cancelar si recibe daño
	table.insert(connections, humanoid.HealthChanged:Connect(function(health)
		if health < humanoid.MaxHealth then
			stopDance(player)
		end
	end))

	-- Cancelar si el personaje se elimina
	table.insert(connections, character.AncestryChanged:Connect(function()
		stopDance(player)
	end))

	activeDanceTracks[player] = { track = track, connections = connections }
end

UseEmoteRemote.OnServerEvent:Connect(function(player, emoteId)
	if not RateLimiter.allow(player, "UseEmote", 3, 5) then return end
	if typeof(emoteId) ~= "string" or emoteId == "" then return end

	-- Verificar cooldown
	local lastUse = playerCooldowns[player] or 0
	local now = tick()
	if now - lastUse < EMOTE_COOLDOWN then return end

	-- Verificar que el cosmetico esta equipado
	local equipped = getEquippedEmotes(player)
	local isEquipped = false
	for _, id in ipairs(equipped) do
		if id == emoteId then
			isEquipped = true
			break
		end
	end
	if not isEquipped then return end

	-- Determinar si es Emote (sticker) o Dance (animacion)
	local itemType = CosmeticsDatabase.GetItemType(emoteId)
	if not itemType then return end

	playerCooldowns[player] = now

	local character = player.Character
	if not character then return end

	if itemType == "Dance" then
		playDance(player, character, emoteId)
	else
		createSticker(character, emoteId)
	end
end)

-- == LÓGICA DE BUY COSMETIC (RemoteFunction) ==

BuyCosmeticRemote.OnServerInvoke = function(player, cosmeticId)
	if not RateLimiter.allow(player, "BuyCosmetic", 2, 4) then
		return false, "Demasiadas solicitudes."
	end
	if not PlayerData.isLoaded(player) then
		return false, "Tus datos aún se están cargando."
	end
	if typeof(cosmeticId) ~= "string" or cosmeticId == "" then
		return false, "ID inválido."
	end

	local cosmeticData = CosmeticsDatabase.GetCosmetic(cosmeticId)
	if not cosmeticData then
		return false, "Cosmético no existe."
	end

	-- Verificar si ya lo posee
	if ownsEmote(player, cosmeticId) then
		return false, "Ya posees este cosmético."
	end

	-- Verificar coins
	local coins = player:GetAttribute("Coins") or 0
	local price = cosmeticData.Price
	if typeof(price) ~= "number" or price ~= price or price < 0 then
		return false, "Precio inválido."
	end
	if coins < price then
		return false, "Coins insuficientes."
	end

	-- Descontar y añadir
	player:SetAttribute("Coins", coins - price)
	local owned = getOwnedEmotes(player)
	table.insert(owned, cosmeticId)
	setOwnedEmotes(player, owned)

	-- Una compra no debe perderse por un crash antes del próximo autosave.
	PlayerData.saveNow(player)

	return true, "Compra exitosa!"
end

-- == LÓGICA DE EQUIP EMOTE (RemoteEvent) ==

EquipEmoteRemote.OnServerEvent:Connect(function(player, slotIndex, emoteId)
	if not RateLimiter.allow(player, "EquipEmote", 5, 8) then return end
	if not PlayerData.isLoaded(player) then return end
	if typeof(slotIndex) ~= "number" or slotIndex ~= slotIndex then return end -- NaN pasa el chequeo de rango
	if typeof(emoteId) ~= "string" then return end
	slotIndex = math.floor(slotIndex)
	if slotIndex < 1 or slotIndex > 6 then return end

	if emoteId ~= "" and not ownsEmote(player, emoteId) then return end

	local equipped = getEquippedEmotes(player)
	-- Qitar el emote de cualquier otro slot que lo tenga
	for i = 1, 6 do
		if equipped[i] == emoteId and i ~= slotIndex then
			equipped[i] = ""
		end
	end
	equipped[slotIndex] = emoteId
	setEquippedEmotes(player, equipped)
end)

print("[CosmeticsServer] Sistema de Cosmetics & Emotes activo.")