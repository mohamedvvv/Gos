local Heroes = {"Yone"}

if not table.contains(Heroes, myHero.charName) then return end


if not FileExist(COMMON_PATH .. "GGPrediction.lua") then
	DownloadFileAsync("https://raw.githubusercontent.com/gamsteron/GG/master/GGPrediction.lua", COMMON_PATH .. "GGPrediction.lua", function() end)
	print("GGPrediction installed Press 2x F6")
	return
end


local GameHeroCount     = Game.HeroCount
local GameHero          = Game.Hero

local TableInsert       = table.insert

local lastIG = 0
local lastMove = 0

local Enemys =   {}
local Allys  =   {}
local Units = 	 {}
local myHero = myHero

function LoadUnits()
	for i = 1, Game.HeroCount() do
		local unit = Game.Hero(i); Units[i] = {unit = unit, spell = nil}
	end
end

local function GetDistanceSqr(pos1, pos2)
	local pos2 = pos2 or myHero.pos
	local dx = pos1.x - pos2.x
	local dz = (pos1.z or pos1.y) - (pos2.z or pos2.y)
	return dx * dx + dz * dz
end

local function GetDistance(p1, p2)
	p2 = p2 or myHero
	return math.sqrt(GetDistanceSqr(p1, p2))
end

local function IsValid(unit)
    if (unit 
        and unit.valid 
        and unit.isTargetable 
        and unit.alive 
        and unit.visible 
        and unit.networkID 
        and unit.health > 0
        and not unit.dead
    ) then
        return true;
    end
    return false;
end

local function Ready(spell)
    return myHero:GetSpellData(spell).currentCd == 0 
    and myHero:GetSpellData(spell).level > 0 
    and myHero:GetSpellData(spell).mana <= myHero.mana 
    and Game.CanUseSpell(spell) == 0
end

local function OnAllyHeroLoad(cb)
    for i = 1, GameHeroCount() do
        local obj = GameHero(i)
        if obj.isAlly then
            cb(obj)
        end
    end
end

local function OnEnemyHeroLoad(cb)
    for i = 1, GameHeroCount() do
        local obj = GameHero(i)
        if obj.isEnemy then
            cb(obj)
        end
    end
end

local function GetEnemyHeroes()
	local _EnemyHeroes = {}
	for i = 1, Game.HeroCount() do
		local unit = Game.Hero(i)
		if unit.team ~= myHero.team then
			table.insert(_EnemyHeroes, unit)
		end
	end
	return _EnemyHeroes
end

local function GetMinionCount(range, pos)
    local pos = pos.pos
	local count = 0
	for i = 1,Game.MinionCount() do
	local hero = Game.Minion(i)
	local Range = range * range
		if hero.team ~= TEAM_ALLY and hero.dead == false and GetDistanceSqr(pos, hero.pos) < Range then
			count = count + 1
		end
	end
	return count
end

local function GetEnemyCount(range, pos)
    local pos = pos.pos
	local count = 0
	for i, hero in ipairs(GetEnemyHeroes()) do
	local Range = range * range
		if GetDistanceSqr(pos, hero.pos) < Range and IsValid(hero) then
		count = count + 1
		end
	end
	return count
end

local function ConvertToHitChance(menuValue, hitChance)
    return menuValue == 1 and _G.PremiumPrediction.HitChance.High(hitChance)
    or menuValue == 2 and _G.PremiumPrediction.HitChance.VeryHigh(hitChance)
    or _G.PremiumPrediction.HitChance.Immobile(hitChance)
end

local function CheckHPPred(unit, time)
	if _G.SDK and _G.SDK.Orbwalker then
		return _G.SDK.HealthPrediction:GetPrediction(unit, time)
	elseif _G.PremiumOrbwalker then
		return _G.PremiumOrbwalker:GetHealthPrediction(unit, time)
	end
end

local function VectorPointProjectionOnLineSegment(v1, v2, v)
	local cx, cy, ax, ay, bx, by = v.x, v.z, v1.x, v1.z, v2.x, v2.z
	local rL = ((cx - ax) * (bx - ax) + (cy - ay) * (by - ay)) / ((bx - ax) ^ 2 + (by - ay) ^ 2)
	local pointLine = { x = ax + rL * (bx - ax), y = ay + rL * (by - ay) }
	local rS = rL < 0 and 0 or (rL > 1 and 1 or rL)
	local isOnSegment = rS == rL
	local pointSegment = isOnSegment and pointLine or { x = ax + rS * (bx - ax), y = ay + rS * (by - ay) }
	return pointSegment, pointLine, isOnSegment
end 

local function GetPathNodes(unit)
	local nodes = {}
	table.insert(nodes, unit.pos)
	if unit.pathing.hasMovePath then
		for i = unit.pathing.pathIndex, unit.pathing.pathCount do
			path = unit:GetPath(i)
			table.insert(nodes, path)
		end
	end		
	return nodes
end

local function GetTargetMS(target)
	local ms = target.ms
	return ms
end	

local function PredictUnitPosition(unit, delay)
	local predictedPosition = unit.pos
	local timeRemaining = delay
	local pathNodes = GetPathNodes(unit)
	for i = 1, #pathNodes -1 do
		local nodeDistance = GetDistance(pathNodes[i], pathNodes[i +1])
		local nodeTraversalTime = nodeDistance / GetTargetMS(unit)
			
		if timeRemaining > nodeTraversalTime then
			timeRemaining =  timeRemaining - nodeTraversalTime
			predictedPosition = pathNodes[i + 1]
		else
			local directionVector = (pathNodes[i+1] - pathNodes[i]):Normalized()
			predictedPosition = pathNodes[i] + directionVector *  GetTargetMS(unit) * timeRemaining
			break;
		end
	end
	return predictedPosition
end

local function GetLineTargetCount(source, Pos, delay, speed, width, range)
	local Count = 0
	for i = 1, Game.MinionCount() do
		local minion = Game.Minion(i)
		if minion and minion.team == TEAM_ENEMY and source:DistanceTo(minion.pos) < range and IsValid(minion) then
			
			local predictedPos = PredictUnitPosition(minion, delay+ GetDistance(source, minion.pos) / speed)
			local proj1, pointLine, isOnSegment = VectorPointProjectionOnLineSegment(source, Pos, predictedPos)
			if proj1 and isOnSegment and (GetDistanceSqr(predictedPos, proj1) <= (minion.boundingRadius + width) * (minion.boundingRadius + width)) then
				Count = Count + 1
			end
		end
	end
	return Count
end

class "Yone"

function Yone:__init()
    self.Q = {speed = 5000, range = 500, delay = 0.12, radius = 15, collision = {nil}, type = "linear"}
    self.Q3 = {speed = 500, range = 1000, delay = 0.12, radius = 50, collision = {nil}, type = "linear"}
	self.W = {speed = 500, range = 600, delay = 0.15, radius = 0, angle = 45, collision = {nil}, type = "conic"}
   self.R = {speed = 1500, range = 1000, delay = 0.50, radius = 225, collision = {nil}, type = "linear"}

    self.lastQTick = GetTickCount()
	
	

    OnAllyHeroLoad(function(hero) TableInsert(Allys, hero); end)
    OnEnemyHeroLoad(function(hero) TableInsert(Enemys, hero); end)

    self:LoadMenu()
	
	if not PredLoaded then
		DelayAction(function()
			if self.tyMenu.Pred:Value() == 1 then
				require('GGPrediction')
				PredLoaded = true					
			end
		end, 1)	
	end	

    Callback.Add("Tick", function() self:Tick() end)
end


function Yone:LoadMenu()
    self.tyMenu = MenuElement({type = MENU, id = "1.0", name = "YoneMomz"})
	self.tyMenu:MenuElement({name = " ", drop = {"Momz"}})
	self.tyMenu:MenuElement({name = "Ping", id = "ping", value = 20, min = 0, max = 300, step = 1})
	
    self.tyMenu:MenuElement({type = MENU, id = "combo", name = "Combo"})
	
		self.tyMenu.combo:MenuElement({id = "useQL", name = "[Q1]/[Q2]", value = true})
        self.tyMenu.combo:MenuElement({id = "useQ3", name = "[Q3]", value = true})	
        self.tyMenu.combo:MenuElement({id = "useW", name = "[W]", value = true})
	    self.tyMenu.combo:MenuElement({id = "useR", name = "[R] multible Enemies", value = true})
	    self.tyMenu.combo:MenuElement({id = "Count", name = "Min Enemies for [R]", value = 3, min = 2, max = 5})
		
    self.tyMenu:MenuElement({type = MENU, id = "harass", name = "Harass"})
        self.tyMenu.harass:MenuElement({id = "useQL", name = "[Q1]/[Q2]", value = true})
        self.tyMenu.harass:MenuElement({id = "useQ3", name = "[Q3]", value = true})
	    self.tyMenu.harass:MenuElement({id = "useW", name = "[W]", value = true})

    self.tyMenu:MenuElement({type = MENU, id = "jungle", name = "JungleClear"})
        self.tyMenu.jungle:MenuElement({id = "useQL", name = "[Q1]/[Q2]", value = true})
        self.tyMenu.jungle:MenuElement({id = "useQ3", name = "[Q3]", value = true})				
        self.tyMenu.jungle:MenuElement({id = "useW", name = "[W]", value = true})
		
    self.tyMenu:MenuElement({type = MENU, id = "clear", name = "LaneClear"})
        self.tyMenu.clear:MenuElement({id = "useQL", name = "[Q1]/[Q2]", value = true})
        self.tyMenu.clear:MenuElement({id = "useQ3", name = "[Q3]", value = true})
		self.tyMenu.clear:MenuElement({id = "useW", name = "[W]", value = true})
	
	self.tyMenu:MenuElement({type = MENU, id = "last", name = "LastHit Minion"})
        self.tyMenu.last:MenuElement({id = "useQL", name = "[Q1]/[Q2]", value = true})
        self.tyMenu.last:MenuElement({id = "useQ3", name = "[Q3]", value = true})
 
		
	self.tyMenu:MenuElement({type = MENU, id = "Pred", name = "Prediction Settings"})
		self.tyMenu.Pred:MenuElement({name = " ", drop = {"After change Prediction Typ press 2xF6"}})	
		self.tyMenu.Pred:MenuElement({id = "Change", name = "Change Prediction Typ", value = 2, drop = {"Premium Prediction", "GGPrediction"}})	
		self.tyMenu.Pred:MenuElement({id = "PredQ", name = "Hitchance[Q]", value = 1, drop = {"Normal", "High", "Immobile"}})
		self.tyMenu.Pred:MenuElement({id = "PredQ3", name = "Hitchance[Q3]", value = 2, drop = {"Normal", "High", "Immobile"}})
		self.tyMenu.Pred:MenuElement({id = "PredW", name = "Hitchance[W]", value = 2, drop = {"Normal", "High", "Immobile"}})
		self.tyMenu.Pred:MenuElement({id = "PredR", name = "Hitchance[R]", value = 2, drop = {"Normal", "High", "Immobile"}})
end

function Yone:Tick()
	
	if Control.IsKeyDown(HK_Q) then
		Control.KeyUp(HK_Q)
	end

    local enemys = _G.SDK.ObjectManager:GetEnemyHeroes(1500)

    for i = 1, #enemys do
        local enemy = enemys[i]
    end
    if myHero.dead or Game.IsChatOpen() or (_G.JustEvade and _G.JustEvade:Evading()) or (_G.ExtLibEvade and _G.ExtLibEvade.Evading) then
        return
    end

    self:UpdateQDelay()

    if _G.SDK.Orbwalker.Modes[0] then --combo
			self:combo()	
    elseif _G.SDK.Orbwalker.Modes[1] then --harass
        self:harass()
    elseif _G.SDK.Orbwalker.Modes[3] then --jungle + lane
        self:Jungle()
		self:Clear()
    elseif _G.SDK.Orbwalker.Modes[4] then --lasthit
        self:LastHit()
    end
    -- print(self.Q3.delay)
end


function Yone:UpdateQDelay()
    local activeSpell = myHero.activeSpell

    if activeSpell.valid then
        if activeSpell.name == "YoneQ1" or activeSpell.name == "YoneQ2" then
            self.Q.delay = activeSpell.windup
        end

        if activeSpell.name == "YoneQ3" then
            self.Q3.delay = activeSpell.windup

            -- print(self.Q3.delay)
        end
    end
end


function Yone:combo()
    local target = nil
	
	target = self:GetHeroTarget(self.R.range)
    if target and self.tyMenu.combo.useR:Value() and self.tyMenu.combo.Count:Value() then
	    local count = GetEnemyCount(1000, target)
		if count >= self.tyMenu.combo.Count:Value() then
        self:CastR(target)
		end
    end
	
	target = self:GetHeroTarget(self.W.range)
    if target and self.tyMenu.combo.useW:Value()then
        self:CastW(target)
    end
	
    target = self:GetHeroTarget(self.Q3.range)
    if target and self.tyMenu.combo.useQ3:Value()then
        self:CastQ3(target)
    end

    target = self:GetHeroTarget(self.Q.range)
    if self.tyMenu.combo.useQL:Value() then
		if target then
			self:CastQ(target)	
		end	
    end
end

function Yone:harass()
    local target = nil
	
	target = self:GetHeroTarget(self.W.range)
    if target and self.tyMenu.harass.useW:Value()then
        self:CastW(target)
    end
	
    target = self:GetHeroTarget(self.Q3.range)
    if target and self.tyMenu.harass.useQ3:Value()then
        self:CastQ3(target)
    end

    target = self:GetHeroTarget(self.Q.range)
    if self.tyMenu.harass.useQL:Value() then
		if target then
			self:CastQ(target)	
		end	
    end
end


function Yone:Clear()
    local minionInRange = _G.SDK.ObjectManager:GetEnemyMinions(self.Q3.range)
    if next(minionInRange) == nil then end

    for i = 1, #minionInRange do
        local minion = minionInRange[i]
		
		if self.tyMenu.clear.useW:Value() and Ready(_W) and myHero.pos:DistanceTo(minion.pos) < 600 and myHero:GetSpellData(0).name ~= "YoneQ3" and _G.SDK.Orbwalker:CanMove(myHero) and self.lastQTick + 300 < GetTickCount() then
			Control.CastSpell(HK_W, minion.pos)
			self.lastQTick = GetTickCount()
        end
		
        if self.tyMenu.clear.useQ3:Value() and Ready(_Q) and myHero:GetSpellData(0).name == "YoneQ3" and _G.SDK.Orbwalker:CanMove(myHero) and self.lastQTick + 300 then
			Control.CastSpell(HK_Q, minion.pos)
			self.lastQTick = GetTickCount()	
        end	

        if self.tyMenu.clear.useQL:Value() and Ready(_Q) and myHero.pos:DistanceTo(minion.pos) < 475 and myHero:GetSpellData(0).name ~= "YoneQ3" and _G.SDK.Orbwalker:CanMove(myHero) and self.lastQTick + 300 < GetTickCount() then
			Control.CastSpell(HK_Q, minion.pos)
			self.lastQTick = GetTickCount()
        end
    end
end

function Yone:Jungle()
    local jungleInrange = _G.SDK.ObjectManager:GetMonsters(self.Q3.range)
    if next(jungleInrange) == nil then end

    for i = 1, #jungleInrange do
        local minion = jungleInrange[i]
		
		if self.tyMenu.jungle.useW:Value() and Ready(_W) and myHero.pos:DistanceTo(minion.pos) < 600 and myHero:GetSpellData(0).name ~= "YoneQ3" and _G.SDK.Orbwalker:CanMove(myHero)then
			Control.CastSpell(HK_W, minion.pos)
			self.lastWTick = GetTickCount()
        end


        if self.tyMenu.jungle.useQ3:Value() and Ready(_Q) and myHero:GetSpellData(0).name == "YoneQ3" and _G.SDK.Orbwalker:CanMove(myHero) and self.lastQTick + 300 then
			Control.CastSpell(HK_Q, minion.pos)
			self.lastQTick = GetTickCount()	
        end		

        if self.tyMenu.jungle.useQL:Value() and Ready(_Q) and myHero.pos:DistanceTo(minion.pos) < 475 and myHero:GetSpellData(0).name ~= "YoneQ3" and _G.SDK.Orbwalker:CanMove(myHero)then
			Control.CastSpell(HK_Q, minion.pos)
			self.lastQTick = GetTickCount()
        end
	end	
end

function Yone:LastHit()
    local minionInRange = _G.SDK.ObjectManager:GetEnemyMinions(self.Q3.range)
    if next(minionInRange) == nil then return  end

    for i = 1, #minionInRange do
        local minion = minionInRange[i]
		
        if self.tyMenu.last.useQ3:Value() and Ready(_Q) and myHero:GetSpellData(0).name == "YoneQ3" and _G.SDK.Orbwalker:CanMove(myHero) and self.lastQTick + 300 then
			local delay = myHero.pos:DistanceTo(minion.pos)/1500 + self.tyMenu.ping:Value()/1000
			local hpPred = CheckHPPred(minion, delay)			
			local Q3Dmg = self:GetQDamge(minion)
			if Q3Dmg > hpPred then
				Control.CastSpell(HK_Q, minion.pos)
				self.lastQTick = GetTickCount()
			end	
        end		

        if self.tyMenu.last.useQL:Value() and Ready(_Q) and myHero.pos:DistanceTo(minion.pos) < 475 and myHero:GetSpellData(0).name ~= "YoneQ3" and _G.SDK.Orbwalker:CanMove(myHero) and self.lastQTick + 300 then
			local QDmg = self:GetQDamge(minion)
			if QDmg > minion.health then
				Control.CastSpell(HK_Q, minion.pos)
				self.lastQTick = GetTickCount()
			end	
        end
    end
end

function Yone:GetHeroTarget(range)
    local EnemyHeroes = _G.SDK.ObjectManager:GetEnemyHeroes(range, false)
    local target = _G.SDK.TargetSelector:GetTarget(EnemyHeroes)

    return target
end


function Yone:CastR(target)
	if Ready(_R) 
	and myHero:GetSpellData(0).name ~= "YoneQ3" 
	and myHero.pos:DistanceTo(target.pos) <= self.R.range 
	and _G.SDK.Orbwalker:CanMove(myHero) 
	and self.lastQTick + 300 < GetTickCount() then
		
		if self.tyMenu.Pred.Change:Value() == 1 then
			local pred = _G.PremiumPrediction:GetPrediction(myHero, target, self.R)
			if pred.CastPos and ConvertToHitChance(self.tyMenu.Pred.PredR:Value(), pred.HitChance) then
				Control.CastSpell(HK_R, pred.CastPos)
				self.lastRTick = GetTickCount()
			end
		else
			local RPrediction = GGPrediction:SpellPrediction({Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.50, Radius = 225, Range = 1000, Speed = 1500, Collision = false})
				  RPrediction:GetPrediction(target, myHero)
			if RPrediction:CanHit(self.tyMenu.Pred.PredR:Value()+1) then
				Control.CastSpell(HK_R, RPrediction.CastPosition)
				self.lastRTick = GetTickCount()
			end	
		end
    end
end	


function Yone:CastW(target)
	if Ready(_W) 
	and myHero:GetSpellData(0).name ~= "YoneQ3" 
	and myHero.pos:DistanceTo(target.pos) <= self.W.range 
	and _G.SDK.Orbwalker:CanMove(myHero) 
	and self.lastQTick + 300 < GetTickCount() then
		
		if self.tyMenu.Pred.Change:Value() == 1 then
			local pred = _G.PremiumPrediction:GetPrediction(myHero, target, self.W)
			if pred.CastPos and ConvertToHitChance(self.tyMenu.Pred.PredW:Value(), pred.HitChance) then
				Control.CastSpell(HK_W, pred.CastPos)
				self.lastQTick = GetTickCount()
			end
		else
			local WPrediction = GGPrediction:SpellPrediction({Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.15, Radius = 0, Range = 600, Speed = 500, Collision = false})
				  WPrediction:GetPrediction(target, myHero)
			if WPrediction:CanHit(self.tyMenu.Pred.PredW:Value()+1) then
				Control.CastSpell(HK_W, WPrediction.CastPosition)
				self.lastQTick = GetTickCount()
			end	
		end
    end
end

 
function Yone:CastQ(target)
	if Ready(_Q)
	and myHero:GetSpellData(0).name ~= "YoneQ3" 
	and myHero.pos:DistanceTo(target.pos) <= self.Q.range 
	and _G.SDK.Orbwalker:CanMove(myHero) 
	and self.lastQTick + 300 < GetTickCount() then
		
		if self.tyMenu.Pred.Change:Value() == 1 then
			local pred = _G.PremiumPrediction:GetPrediction(myHero, target, self.Q)
			if pred.CastPos and ConvertToHitChance(self.tyMenu.Pred.PredQ:Value(), pred.HitChance) then
				Control.CastSpell(HK_Q, pred.CastPos)
				self.lastQTick = GetTickCount()
			end
		else
			local QPrediction = GGPrediction:SpellPrediction({Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.12, Radius = 15, Range = 500, Speed = 5000, Collision = false})
				  QPrediction:GetPrediction(target, myHero)
			if QPrediction:CanHit(self.tyMenu.Pred.PredQ:Value()+1) then
				Control.CastSpell(HK_Q, QPrediction.CastPosition)
				self.lastQTick = GetTickCount()
			end	
		end
    end
end

function Yone:CastQ3(target)
    if Ready(_Q)
    and myHero:GetSpellData(0).name == "YoneQ3"  
    and myHero.pos:DistanceTo(target.pos) <= self.Q3.range 
    and _G.SDK.Orbwalker:CanMove(myHero) 
    and self.lastQTick + 300 < GetTickCount() then
		
		if self.tyMenu.Pred.Change:Value() == 1 then
			local pred = _G.PremiumPrediction:GetPrediction(myHero, target, self.Q3)
			if pred.CastPos and ConvertToHitChance(self.tyMenu.Pred.PredQ3:Value(), pred.HitChance) then
				Control.CastSpell(HK_Q, pred.CastPos)
				self.lastQTick = GetTickCount()
			end
		else
			local QPrediction = GGPrediction:SpellPrediction({Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.12, Radius = 50, Range = 1000, Speed = 500, Collision = false})
				  QPrediction:GetPrediction(target, myHero)
			if QPrediction:CanHit(self.tyMenu.Pred.PredQ3:Value()+1) then
				Control.CastSpell(HK_Q, QPrediction.CastPosition)
				self.lastQTick = GetTickCount()
			end	
		end 
    end
end

local function OnProcessSpell()
	for i = 1, #Units do
		local unit = Units[i].unit; local last = Units[i].spell; local spell = unit.activeSpell
		if spell and last ~= (spell.name .. spell.endTime) and unit.activeSpell.isChanneling then
			Units[i].spell = spell.name .. spell.endTime; return unit, spell
		end
	end
	return nil, nil
end

function Yone:GetQDamge(obj)
    local baseDMG = ({20,40,60,80,100})[myHero:GetSpellData(0).level]
    local AD = myHero.totalDamage
    local dmg = _G.SDK.Damage:CalculateDamage(myHero, obj, _G.SDK.DAMAGE_TYPE_PHYSICAL ,  baseDMG + AD )

    return dmg
end

function Yone:HasBuff(unit, name)
    for i = 0, unit.buffCount do
        local buff = unit:GetBuff(i)
        if buff and buff.count > 0 and buff.name == name then
            return true , buff.count
        end
    end
    return false
end

DelayAction(function()
	if table.contains(Heroes, myHero.charName) then		
		require "DamageLib"
		require "GGPrediction"
		_G[myHero.charName]()
		LoadUnits()
	end		
end, math.max(0.07, 10 - Game.Timer()))
