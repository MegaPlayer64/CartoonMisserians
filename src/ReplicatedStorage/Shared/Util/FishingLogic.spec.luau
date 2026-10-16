--!nocheck
-- Specs TestEZ (describe/it/expect son globales inyectados por el runner).
return function()
	local Config = require(script.Parent.Parent.Config)
	local FishingLogic = require(script.Parent.FishingLogic)
	local C = Config.Fishing

	local function seq(values)
		local i = 0
		return function()
			i += 1
			return values[i] or values[#values]
		end
	end

	local function kind(id, category, weight)
		return {
			id = id, name = id, category = category, icon = "?", radius = 0.5,
			speedMin = 1, speedMax = 3, weight = weight, points = 0, cartonsitos = 0,
			livesLost = 0, stun = false,
		}
	end

	describe("progress", function()
		it("se queda entre 0 y 1", function()
			expect(FishingLogic.progress(10, 5, 60)).to.equal(0)
			expect(FishingLogic.progress(10, 40, 60)).to.equal(0.5)
			expect(FishingLogic.progress(10, 999, 60)).to.equal(1)
		end)
	end)

	describe("entityX / isGone", function()
		it("nace fuera del campo según la dirección", function()
			local right = { id = 1, kind = "Sardina", dir = 1, y = 2, speed = 4, spawnTime = 10 }
			local left = { id = 2, kind = "Sardina", dir = -1, y = 2, speed = 4, spawnTime = 10 }
			expect(FishingLogic.entityX(right, 10, C)).to.equal(-C.offscreenMargin)
			expect(FishingLogic.entityX(right, 11, C)).to.equal(-C.offscreenMargin + 4)
			expect(FishingLogic.entityX(left, 10, C)).to.equal(C.fieldWidth + C.offscreenMargin)
			expect(FishingLogic.entityX(left, 11, C)).to.equal(C.fieldWidth + C.offscreenMargin - 4)
		end)

		it("desaparece justo después de cruzar todo el campo", function()
			local e = { id = 1, kind = "Sardina", dir = 1, y = 2, speed = 4, spawnTime = 0 }
			local crossing = (C.fieldWidth + 2 * C.offscreenMargin) / e.speed
			expect(FishingLogic.isGone(e, 0, C)).to.equal(false)
			expect(FishingLogic.isGone(e, crossing - 0.01, C)).to.equal(false)
			expect(FishingLogic.isGone(e, crossing + 0.01, C)).to.equal(true)
		end)
	end)

	describe("stepHook", function()
		it("se mueve a velocidad constante", function()
			expect(FishingLogic.stepHook(4, 1, 0.5, 6, 0, 9)).to.equal(7)
			expect(FishingLogic.stepHook(4, -1, 0.5, 6, 0, 9)).to.equal(1)
			expect(FishingLogic.stepHook(4, 0, 1, 6, 0, 9)).to.equal(4)
		end)

		it("no sale de los límites", function()
			expect(FishingLogic.stepHook(8, 1, 1, 6, 0, 9)).to.equal(9)
			expect(FishingLogic.stepHook(1, -1, 1, 6, 0, 9)).to.equal(0)
		end)
	end)

	describe("hits", function()
		it("incluye el borde exacto y excluye lo que queda fuera", function()
			expect(FishingLogic.hits(0, 0, 1, 2, 0, 1)).to.equal(true)
			expect(FishingLogic.hits(0, 0, 1, 2.01, 0, 1)).to.equal(false)
			expect(FishingLogic.hits(0, 0, 1, 0, 0, 1)).to.equal(true)
		end)
	end)

	describe("pickKind", function()
		local two = { kind("A", "Fish", 1), kind("B", "Fish", 1) }

		it("respeta los límites de los pesos", function()
			expect(FishingLogic.pickKind(seq({ 0 }), two, 0).id).to.equal("A")
			expect(FishingLogic.pickKind(seq({ 0.49 }), two, 0).id).to.equal("A")
			expect(FishingLogic.pickKind(seq({ 0.5 }), two, 0).id).to.equal("B")
			expect(FishingLogic.pickKind(seq({ 0.999999 }), two, 0).id).to.equal("B")
		end)

		it("los peligrosos pesan el doble al final de la ronda", function()
			local mixed = { kind("Fish", "Fish", 1), kind("Shark", "Danger", 1) }
			-- progreso 0: reparto 1/2. progreso 1: Danger pesa 2 -> Fish ocupa 1/3.
			expect(FishingLogic.pickKind(seq({ 0.4 }), mixed, 1).id).to.equal("Fish")
			expect(FishingLogic.pickKind(seq({ 0.4 }), mixed, 0).id).to.equal("Fish")
			expect(FishingLogic.pickKind(seq({ 0.4 }), mixed, 1).id).to.equal("Fish")
			expect(FishingLogic.pickKind(seq({ 0.34 }), mixed, 1).id).to.equal("Shark")
		end)

		it("siempre devuelve un tipo válido", function()
			for i = 1, 100 do
				local picked = FishingLogic.pickKind(seq({ i / 101 }), C.kinds, i / 100)
				expect(C.kindsById[picked.id]).to.be.ok()
			end
		end)
	end)

	describe("makeEntity", function()
		it("usa dirección, carril y velocidad del rng en ese orden", function()
			local k = kind("A", "Fish", 1)
			local e = FishingLogic.makeEntity(seq({ 0.9, 0, 0.5 }), 7, k, 100, C)
			expect(e.id).to.equal(7)
			expect(e.dir).to.equal(-1)
			expect(e.y).to.equal(C.laneMargin)
			expect(e.speed).to.equal(2)
			expect(e.spawnTime).to.equal(100)
		end)

		it("el carril siempre queda dentro del agua", function()
			local k = kind("A", "Fish", 1)
			local top = FishingLogic.makeEntity(seq({ 0, 0, 0 }), 1, k, 0, C)
			local bottom = FishingLogic.makeEntity(seq({ 0, 1, 0 }), 1, k, 0, C)
			expect(top.y >= C.laneMargin).to.equal(true)
			expect(bottom.y <= C.fieldDepth - C.laneMargin).to.equal(true)
		end)
	end)

	describe("spawnDelay", function()
		it("va del valor inicial al mínimo", function()
			expect(FishingLogic.spawnDelay(0, C)).to.equal(C.spawnDelayStart)
			expect(FishingLogic.spawnDelay(1, C)).to.equal(C.spawnDelayMin)
		end)
	end)

	describe("applyPoints", function()
		it("nunca baja de 0", function()
			expect(FishingLogic.applyPoints(100, -150)).to.equal(0)
			expect(FishingLogic.applyPoints(100, 50)).to.equal(150)
			expect(FishingLogic.applyPoints(0, -300)).to.equal(0)
		end)
	end)
end
