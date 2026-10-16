--[[
	MusicData (ModuleScript)
	Ubicación: ReplicatedStorage.Framework.MusicData

	Base de datos de canciones:
	Maneja Lobby, Mapas, Capas de Tensión por Personaje/Skin y Chase Themes.
]]

local MusicData = {
	-- Música del Lobby / Intermisión
	Lobby = "rbxassetid://118532326034309",

	-- Música Ambiental por Mapa
	Maps = {
		["DigitalCircus"] = "rbxassetid://128160814627157",
		["Default"] = "rbxassetid://136743220559160",
	},

	-- 3 Capas de Tensión PERSONALIZADAS por Personaje y Skin
	TensionLayers = {
		["Stan.oma.png"] = {
			Layer1 = "rbxassetid://114120194034218",
			Layer2 = "rbxassetid://105936372235454",
			Layer3 = "rbxassetid://90566778767369",
		},
		["Default"] = {
			Layer1 = "rbxassetid://96081482761997",
			Layer2 = "rbxassetid://95715387055424",
			Layer3 = "rbxassetid://138708524220458",
		},
	},

	-- Música de Persecución (Chase Theme) cuando el Devilish está a menos de 25 studs
	ChaseThemes = {
		["Stan.oma.png"] = "rbxassetid://125854384141826",
		["Default"] = "rbxassetid://108014890185870",
	},
}

return MusicData