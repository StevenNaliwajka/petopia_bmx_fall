--[[--------------------------------------------------------------------------
    entities/bmx_city_solid/shared.lua

    The solid parts of the city: a viaduct, or a pier. sh_city.lua lays them
    out as boxes under a name; this entity is spawned once per name by
    sv_city.lua and gives those boxes collision, on the server for physics and
    on the client for player movement prediction.

    It draws nothing. cl_city.lua draws the whole city in one pass, solid parts
    included, so what you see and what you hit come from the same layout.
----------------------------------------------------------------------------]]

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "BMX city solid"
ENT.Author = "naliwajka"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_OPAQUE
ENT.PhysgunDisabled = true
ENT.m_tblToolsAllowed = {}

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "SolidName")
end

-- The boxes for this entity's name, as convex hulls in ENTITY space.
function ENT:Convexes()
    local L = BMX.City and BMX.City.Layout()
    local s = L and L.solids[self:GetSolidName()]
    if not s then return nil end
    local o = self:GetPos()
    local out = {}
    for _, b in ipairs(s.boxes) do
        local x0, y0, z0, x1, y1, z1 = b[1] - o.x, b[2] - o.y, b[3] - o.z, b[4] - o.x, b[5] - o.y, b[6] - o.z
        out[#out + 1] = {
            Vector(x0, y0, z0), Vector(x1, y0, z0), Vector(x1, y1, z0), Vector(x0, y1, z0),
            Vector(x0, y0, z1), Vector(x1, y0, z1), Vector(x1, y1, z1), Vector(x0, y1, z1),
        }
    end
    return out
end

function ENT:BuildPhysics()
    local hulls = self:Convexes()
    if not hulls then return false end
    self:PhysicsInitMultiConvex(hulls)
    self:SetSolid(SOLID_VPHYSICS)
    -- MOVETYPE_VPHYSICS: the entity follows its body, so what traces hit and
    -- what the bike's hull meets are the same place.
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:EnableCustomCollisions(true)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        -- THE MATERIAL FIRST, THEN FREEZE. PhysObj:SetMaterial on a body that
        -- is already frozen THAWS it inside VPhysics, while IsMotionEnabled()
        -- goes on saying false: measured on a real server, a bike pressing a
        -- pier's plinth at walking pace pushed this 50,000 kg "frozen" body
        -- 3-6 u per ride (at 500 kg, 100-160 u), and with the material set
        -- before EnableMotion(false) -- or not at all -- 0.00. That was the
        -- whole story of the bike riding into the kerbs: under MOVETYPE_NONE
        -- the thawed body was shoved out from under the entity (traces still
        -- hit the kerb, the hull went into it, the wheels sank and the bike
        -- fell); under MOVETYPE_VPHYSICS the entity went with it (beds
        -- knocked out of place, d555635). bmx_test_solid and bmx_park_piece
        -- always had this order, which is why no headless case ever saw it.
        phys:SetMaterial("metal")
        phys:SetMass(50000)
        phys:EnableMotion(false)
        phys:Sleep()
    end
    self._built = true
    return true
end
