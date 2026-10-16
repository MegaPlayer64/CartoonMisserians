--[[
	CosmeticsDatabase (ModuleScript)
	ReplicatedStorage.Framework.CosmeticsDatabase

	Base de datos centralizada para el sistema de Cosmetics & Emotes.
	Diseñado para extenderse a Personajes y Skins en el futuro.
]]

local CosmeticsDatabase = {}

-- == EMOTES ==
-- Stickers flotantes que aparecen sobre la cabeza del personaje.
-- Image debe ser un rbxassetid:// válido (subir a Roblox y usar el ID).
CosmeticsDatabase.Emotes = {
	["TadeoAFK"] = {
		Id = "TadeoAFK",
		Name = "Tadeo AFK",
		Image = "rbxassetid://98279490499409",
		Price = 0,
		Description = "Made by: CarbaYT",
	},
	["BCGG"] = {
		Id = "BCGG",
		Name = "Brothercat GG",
		Image = "rbxassetid://134677311099948",
		Price = 0,
		Description = "Made by: CarbaYT",
	},
	["YouTUP"] = {
		Id = "YouTUP",
		Name = "You Thumbsup",
		Image = "rbxassetid://113192557534992",
		Price = 0,
		Description = "Made by: CarbaYT",
	},
	["BobST"] = {
		Id = "BobST",
		Name = "Bob Smart Thinking",
		Image = "rbxassetid://80060874371451",
		Price = 250,
		Description = "Made by: CarbaYT",
	},
	["LuciaSmile"] = {
		Id = "LuciaSmile",
		Name = "Lucia Smile",
		Image = "rbxassetid://95794214439623",
		Price = 0,
		Description = "Made by: xXmegaplayer64Xx",
	},
	["Shock"] = {
		Id = "Shock",
		Name = "Shock",
		Image = "rbxassetid://7733993044",
		Price = 400,
		Description = "¡¿Qué?!",
	},
}

-- Lista ordenada para iteración en UI
CosmeticsDatabase.EmoteList = { "TadeoAFK", "BCGG", "YouTUP", "BobST", "LuciaSmile"}

-- == DANCES (Bailes / Animaciones de Personaje) ==
-- Bailes que reproducen una animacion en el Humanoid.Animator del personaje.
-- AnimationId debe ser un rbxassetid:// valido de una Animation subida a Roblox.
CosmeticsDatabase.Dances = {
	["Dance1"] = {
		Id = "Dance1",
		Name = "Floss",
		AnimationId = "rbxassetid://123456789",
		Price = 300,
		Description = "El baile del momento.",
	},
	["Dance2"] = {
		Id = "Dance2",
		Name = "Breakdance",
		AnimationId = "rbxassetid://123456789",
		Price = 500,
		Description = "Pasos prohibidos en el piso.",
	},
}

CosmeticsDatabase.DanceList = { "Dance1", "Dance2" }

-- == PERSONAJES (Estructura futura) ==
--[[
CosmeticsDatabase.Characters = {
	["CharacterId"] = {
		Id = "CharacterId",
		Name = "Display Name",
		Image = "rbxassetid://...",
		Price = 1000,
		Description = "...",
	},
}
]]
CosmeticsDatabase.Characters = {}

-- == SKINS (Estructura futura) ==
--[[
CosmeticsDatabase.Skins = {
	["SkinId"] = {
		Id = "SkinId",
		Name = "Display Name",
		Image = "rbxassetid://...",
		Price = 750,
		TargetCharacter = "CharacterId",
		Description = "...",
	},
}
]]
CosmeticsDatabase.Skins = {}

-- == HELPERS ==

-- Obtiene un emote (sticker) por su ID, o nil si no existe.
function CosmeticsDatabase.GetEmote(emoteId)
	return CosmeticsDatabase.Emotes[emoteId]
end

-- Obtiene un baile por su ID, o nil si no existe.
function CosmeticsDatabase.GetDance(danceId)
	return CosmeticsDatabase.Dances[danceId]
end

-- Obtiene cualquier cosmetico por su ID, buscando en Emotes y Dances.
function CosmeticsDatabase.GetCosmetic(cosmeticId)
	return CosmeticsDatabase.Emotes[cosmeticId] or CosmeticsDatabase.Dances[cosmeticId] or nil
end

-- Alias retrocompatible
CosmeticsDatabase.GetItem = CosmeticsDatabase.GetCosmetic

-- Obtiene todos los emotes (stickers) en lista ordenada.
function CosmeticsDatabase.GetAllEmotes()
	local list = {}
	for _, id in ipairs(CosmeticsDatabase.EmoteList) do
		local emote = CosmeticsDatabase.Emotes[id]
		if emote then
			table.insert(list, emote)
		end
	end
	return list
end

-- Obtiene todos los bailes en lista ordenada.
function CosmeticsDatabase.GetAllDances()
	local list = {}
	for _, id in ipairs(CosmeticsDatabase.DanceList) do
		local dance = CosmeticsDatabase.Dances[id]
		if dance then
			table.insert(list, dance)
		end
	end
	return list
end

-- Obtiene el precio de cualquier cosmetico (0 = gratis).
function CosmeticsDatabase.GetPrice(cosmeticId)
	local item = CosmeticsDatabase.GetCosmetic(cosmeticId)
	return item and item.Price or 0
end

-- Determina si un ID es un baile (Animation) o un sticker (Emote).
function CosmeticsDatabase.GetItemType(cosmeticId)
	if CosmeticsDatabase.Dances[cosmeticId] then return "Dance" end
	if CosmeticsDatabase.Emotes[cosmeticId] then return "Emote" end
	return nil
end

return CosmeticsDatabase