AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    if self.CitySolidName then self:SetSolidName(self.CitySolidName) end
    self:SetModel("models/hunter/blocks/cube025x025x025.mdl")
    self:DrawShadow(false)
    self:BuildPhysics()
    self.homePos, self.homeAng = self:GetPos(), self:GetAngles()
end

-- NOTHING MOVES IT. Frozen, a VPhysics body can still be nudged: a bike
-- pressing on a pier's plinth at walking pace moved it half a unit, and
-- before gmod-bmx 04141d0 beds were knocked clean out of place. So every tick
-- it is put back where the city laid it, frozen and asleep.
function ENT:Think()
    local home = self.homePos
    if home and (self:GetPos():DistToSqr(home) > 0.01 or self:GetAngles() ~= self.homeAng) then
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then
            phys:EnableMotion(false)
            phys:SetPos(home)
            phys:SetAngles(self.homeAng)
            phys:Sleep()
        end
        self:SetPos(home)
        self:SetAngles(self.homeAng)
    end
    self:NextThink(CurTime())
    return true
end

-- A handful of these exist per map; always send them, so a rider's client has
-- the collision before they ride under a viaduct, not when it enters the PVS.
function ENT:UpdateTransmitState() return TRANSMIT_ALWAYS end
