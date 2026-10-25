--[[
	CharacterDatabase (ModuleScript)
	Ubicacion: ReplicatedStorage.Framework.CharacterDatabase

	Base de datos central de personajes seleccionables.
	Define los Toonflows y Devilishes disponibles con sus stats personalizados.
]]

local CharacterDatabase = {}

-- == ENUMERACION DE TIPOS DE PERSONAJE ==
CharacterDatabase.CharacterType = {
	Toonflow = "Toonflow",
	Devilish = "Devilish",
}

-- == TOONFLOWS SELECCIONABLES ==
CharacterDatabase.Toonflows = {
	{
		Name = "Brothercat",
		DisplayName = "Brothercat",
		Description = "El Toonflow equilibrado. Bueno para principiantes.",
		Color = Color3.fromRGB(100, 150, 255),  -- Azul
		Stats = {
			MaxHealth = 100,
			WalkSpeed = 16,
			RunSpeed = 24,
			DownedHealth = 50,
			ReviveTime = 5,
			BleedOutTime = 30,
		},
	},
	{
		Name = "TobyWilliams",
		DisplayName = "Toby Williams",
		Description = "Toonflow Sentinel. Habilidades de control y trampas.",
		Color = Color3.fromRGB(100, 255, 150),  -- Verde claro
		Stats = {
			MaxHealth = 100,
			WalkSpeed = 16,
			RunSpeed = 24,
			DownedHealth = 50,
			ReviveTime = 5,
			BleedOutTime = 30,
		},
		Abilities = {
			Slot1 = "YaLevantate",
			Slot2 = "BaraNormal",
			Slot3 = "RayosLaserToby",
			Slot4 = "EscudoToby",
		},
	},
	{
		Name = "Takorita",
		DisplayName = "Takorita & Announcer",
		Description = "Toonflow Support. Curacion canalizada y disrupcion sonora.",
		Color = Color3.fromRGB(255, 182, 193),  -- Rosa pastel
		Stats = {
			MaxHealth = 100,
			WalkSpeed = 16,
			RunSpeed = 24,
			DownedHealth = 50,
			ReviveTime = 5,
			BleedOutTime = 30,
		},
	},
	{
		Name = "Deerphina",
		DisplayName = "Deerphina",
		Description = "Una ciervo misteriosa. Embiste, aturde con sus cuernos y comparte galletas curativas.",
		Color = Color3.fromRGB(180, 110, 50), -- Marrón ciervo
		Icon = "rbxassetid://0",
		Stats = {
			MaxHealth = 100,
			WalkSpeed = 16,
			SprintSpeed = 22,
			DownedHealth = 50,
			ReviveTime = 5,
			BleedOutTime = 30,
		},
		Abilities = {
			Slot1 = "Koshintantan",
			Slot2 = "ChistesDeCiervos",
			Slot3 = "GalletasParaCiervos",
			Slot4 = "RegaloDeAmigos",
		},
	}
}

-- == DEVILISHES SELECCIONABLES ==
CharacterDatabase.Devilishes = {
	{
		Name = "MissCircle",
		DisplayName = "Miss Circle",
		Description = "DEVILISH inicial. Profesora implacable que rastrea indisciplinas con precisión geométrica y acorta distancia con su compás.",
		Color = Color3.fromRGB(25, 25, 30),
		Icon = "rbxassetid://132470659616223", -- Reemplaza con su Asset ID final
		Stats = {
			MaxHealth = 1100,
			WalkSpeed = 16,
			AttackRange = 8,
			AttackCooldown = 1.0,
			AttackDamage = 25,
			AbsorptionMax = 100,
			AbsorptionPerHit = 10,
		},
		Abilities = {
			Slot1 = "LinearThrust",
			Slot2 = "PunishmentRadius",
			Slot3 = "FailingGrade",
			Slot4 = "DetentionTime",
		},
	},
	{
		Name = "Stan.oma.png",
		DisplayName = "Stan.oma.png",
		Description = "Entidad corrupta de cartucho. Manipula el sistema y deja rastros de veneno.",
		Color = Color3.fromRGB(80, 0, 100),
		Icon = "rbxassetid://90837561622868",
		Stats = {
			MaxHealth = 1100,
			WalkSpeed = 16,
			AttackRange = 7,
			AttackCooldown = 1.0,
			AttackDamage = 22,
			AbsorptionMax = 100,
			AbsorptionPerHit = 10,
		},
		Abilities = {
			Slot1 = "RayoCorrupto",
			Slot2 = "BetterCallStan",
			Slot3 = "CorrupcionGrave",
			Slot4 = "CambioArma",
		},
	},
	{
		Name = "Mariposaurio",
		DisplayName = "Mariposaurio",
		Description = "Entidad de alucinaciones y sombras. Atormenta a sus presas y las convierte en marionetas.",
		Color = Color3.fromRGB(40, 40, 40),
		Icon = "rbxassetid://75810794691135",
		Stats = {
			MaxHealth = 1100,
			WalkSpeed = 16,
			SprintSpeed = 23,
			AttackRange = 8,
			AttackCooldown = 1.0,
			AttackDamage = 24,
			AbsorptionMax = 100,
			AbsorptionPerHit = 10,
		},
		Abilities = {
			Slot1 = "HereComes",
			Slot2 = "AThought",
			Slot3 = "Boo",
			Slot4 = "DeadHope",
		},
	},
	{
		Name = "Shedmov",
		DisplayName = "Shed.mov",
		Description = "DEVILISH asesino. Velocidad letal y ataques imparables.",
		Color = Color3.fromRGB(57, 216, 110),
		Stats = {
			MaxHealth = 1100,
			WalkSpeed = 16,
			SprintSpeed = 23,
			AttackRange = 8,
			AttackCooldown = 1.0,
			AttackDamage = 24,
			AbsorptionMax = 100,
			AbsorptionPerHit = 10,
		},
		Abilities = {
			Slot1 = "CargaMotosierra",
			Slot2 = "FueraDeMiCobertizo",
			Slot3 = "BienvenidaAPonyville",
		},
	},
}

-- == VALORES POR DEFECTO ==
CharacterDatabase.DefaultToonflow = "Brothercat"
CharacterDatabase.DefaultDevilish = "Stan.oma.png"

-- Trunks y Neuro/Blazer
table.insert(CharacterDatabase.Toonflows, {
	Name = "Trunks",
	DisplayName = "Trunks",
	Description = "Toonflow Sentinel. Espada Z, Rafagas de Ki y transformacion Super Sayajin.",
	Color = Color3.fromRGB(255, 215, 0),
	Stats = {
		MaxHealth = 100,
		WalkSpeed = 16,
		RunSpeed = 24,
		DownedHealth = 50,
		ReviveTime = 5,
		BleedOutTime = 30,
	},
})

table.insert(CharacterDatabase.Devilishes, {
	Name = "Neuro",
	DisplayName = "Blazer",
	Description = "DEVILISH alterado. Cuanto mas famoso, mas peligroso.",
	Color = Color3.fromRGB(200, 150, 255),
	Stats = {
		MaxHealth = 1100,
		WalkSpeed = 16,
		AttackRange = 8,
		AttackCooldown = 1.0,
		AttackDamage = 26,
		AbsorptionMax = 100,
		AbsorptionPerHit = 10,
	},
})

--[[
	Busca un Toonflow por nombre o DisplayName.
]]
function CharacterDatabase.GetToonflow(name)
	for _, toon in ipairs(CharacterDatabase.Toonflows) do
		if toon.Name == name or toon.DisplayName == name then
			return toon
		end
	end
	return nil
end

--[[
	Busca un Devilish por nombre o DisplayName.
]]
function CharacterDatabase.GetDevilish(name)
	for _, devilish in ipairs(CharacterDatabase.Devilishes) do
		if devilish.Name == name or devilish.DisplayName == name then
			return devilish
		end
	end
	return nil
end

--[[
	Busca un personaje (Toonflow o Devilish) por nombre o DisplayName.
]]
function CharacterDatabase.GetCharacterData(name)
	local toon = CharacterDatabase.GetToonflow(name)
	if toon then return toon end
	local devilish = CharacterDatabase.GetDevilish(name)
	if devilish then return devilish end
	return nil
end

--[[
	Valida si un nombre de Toonflow existe en la base de datos.
]]
function CharacterDatabase.IsValidToonflow(name)
	return CharacterDatabase.GetToonflow(name) ~= nil
end

--[[
	Valida si un nombre de Devilish existe en la base de datos.
]]
function CharacterDatabase.IsValidDevilish(name)
	return CharacterDatabase.GetDevilish(name) ~= nil
end

--[[
	Obtiene la tabla de stats de un Toonflow por nombre.
]]
function CharacterDatabase.GetToonflowStats(name)
	local toon = CharacterDatabase.GetToonflow(name)
	if toon then
		return toon.Stats
	end
	local default = CharacterDatabase.GetToonflow(CharacterDatabase.DefaultToonflow)
	return default and default.Stats or nil
end

--[[
	Obtiene la tabla de stats de un Devilish por nombre.
]]
function CharacterDatabase.GetDevilishStats(name)
	local devilish = CharacterDatabase.GetDevilish(name)
	if devilish then
		return devilish.Stats
	end
	local default = CharacterDatabase.GetDevilish(CharacterDatabase.DefaultDevilish)
	return default and default.Stats or nil
end

return CharacterDatabase