local GetSpellName = C_Spell.GetSpellName
local IsSpellUsable = C_Spell.IsSpellUsable
local Range = {
	friendly = {
		["PRIEST"] = {
			(GetSpellName(17)), -- Power Word: Shield
			(GetSpellName(527)), -- Purify
		},
		["DRUID"] = {
			(GetSpellName(774)), -- Rejuvenation
			(GetSpellName(2782)), -- Remove Corruption
		},
		["PALADIN"] = GetSpellName(19750), -- Flash of Light
		["SHAMAN"] = GetSpellName(8004), -- Healing Surge
		["WARLOCK"] = GetSpellName(5697), -- Unending Breath
		--["DEATHKNIGHT"] = GetSpellName(61999), -- Raise Ally (resurrection only, nil on living targets)
		["MONK"] = GetSpellName(115450), -- Detox
		["MAGE"] = {
			(GetSpellName(1459)), -- Arcane Intellect (works on any friendly target)
			(GetSpellName(130)), -- Slow Fall (players only)
		},
		["WARRIOR"] = GetSpellName(3411), -- Intervene
		["EVOKER"] = GetSpellName(361469), -- Living Flame
		--["ROGUE"] = GetSpellName(57934), -- Tricks of the Trade (100yd)
		--["DEMONHUNTER"] = nil, 
	},
	hostile = {
		["DEATHKNIGHT"] = {
			(GetSpellName(47541)), -- Death Coil
			(GetSpellName(49576)), -- Death Grip
		},
		["DEMONHUNTER"] = GetSpellName(185123), -- Throw Glaive
		["DRUID"] = GetSpellName(8921),  -- Moonfire
		["HUNTER"] = {
			(GetSpellName(193455)), -- Cobra Shot
			(GetSpellName(19434)), -- Aimed Short
			(GetSpellName(193265)), -- Hatchet Toss
		},
		["MAGE"] = {
			(GetSpellName(116)), -- Frostbolt
			(GetSpellName(30451)), -- Arcane Blast
			(GetSpellName(133)), -- Fireball
		},
		["MONK"] = GetSpellName(115546), -- Provoke
		["PALADIN"] = GetSpellName(62124), -- Hand of Reckoning
		["PRIEST"] = GetSpellName(585), -- Smite
		["ROGUE"] = {
			(GetSpellName(185565)), -- Poisoned Knife
			(GetSpellName(185763)), -- Pistol Shot
			(GetSpellName(114014)), -- Shuriken Toss
		},
		["SHAMAN"] = GetSpellName(188196), -- Lightning Bolt
		["WARLOCK"] = GetSpellName(686), -- Shadow Bolt
		["WARRIOR"] = GetSpellName(355), -- Taunt
		["EVOKER"] = GetSpellName(361469), -- Living Flame
	},
}

ShadowUF:RegisterModule(Range, "range", ShadowUF.L["Range indicator"])

local LSR = LibStub("SpellRange-1.0")

local playerClass = select(2, UnitClass("player"))
local rangeSpells = {}

local UnitPhaseReason_o = UnitPhaseReason
local UnitPhaseReason = function(unit)
	local phase = UnitPhaseReason_o(unit)
	-- Secret when the unit's identity is secret, comparing would error
	if( issecretvalue and issecretvalue(phase) ) then return nil end
	if (phase == Enum.PhaseReason.WarMode or phase == Enum.PhaseReason.ChromieTime or phase == Enum.PhaseReason.TimerunningHwt) and UnitIsVisible(unit) then
		return nil
	end
	return phase
end

local function SafeAlphaFromBool(v, inAlpha, oorAlpha)
    local ok, alpha = pcall(function()
        return v and inAlpha or oorAlpha
    end)
    if ok then
        return alpha
    end
    -- If v is a secret boolean (or otherwise forbidden), we can't branch on it.
    -- Default to "in range" so we don't dim incorrectly and don't error.
    return inAlpha
end

local scrub = scrubsecretvalues or function(v) return v end


local function SafeIsSpellInRange(spell, unit)
    local ok, res = pcall(LSR.IsSpellInRange, spell, unit)
    if not ok or res == nil then return nil end
    -- C_Spell.IsSpellInRange never returns secrets; direct comparison is safe.
    return res == 1
end

-- Coerce a possibly-secret boolean without erroring; false when it can't be read.
local function SafeBool(v)
    local ok, res = pcall(function() return v and true or false end)
    return ok and res
end

-- Only push the alpha through when it actually changed, to skip redundant
-- SetAlpha calls. Cache in _rangeLastAlpha (SetRangeAlpha owns .rangeAlpha).
local function applyRangeAlpha(frame, alpha)
    if frame._rangeLastAlpha ~= alpha then
        frame._rangeLastAlpha = alpha
        frame:SetRangeAlpha(alpha)
    end
end


local function checkRange(self)
    local frame = self.parent
    local cfg = ShadowUF.db.profile.units[frame.unitType].range
    local inAlpha, oorAlpha = cfg.inAlpha, cfg.oorAlpha

    -- Check which spell to use
    local spell
    if UnitCanAssist("player", frame.unitSUF) then
        spell = rangeSpells.friendly
    elseif UnitCanAttack("player", frame.unitSUF) then
        spell = rangeSpells.hostile
    end

    if (not UnitIsConnected(frame.unitSUF)) or UnitPhaseReason(frame.unitSUF) then
        applyRangeAlpha(frame, oorAlpha)
        return
    end

    -- Primary: spell-based range check (most accurate)
    if spell then
        local inRange = SafeIsSpellInRange(spell, frame.unitSUF)
        if inRange ~= nil then
            applyRangeAlpha(frame, inRange and inAlpha or oorAlpha)
            return
        end
        -- nil = inconclusive (e.g. C_Spell.IsSpellInRange returns nil for raidN tokens)
        -- Fall through to UnitInRange for group members
    end

    -- Fallback: UnitInRange for group members
    if not ShadowUF.IsUnitIdentitySecret(frame.unitSUF) and (UnitInRaid(frame.unitSUF) or UnitInParty(frame.unitSUF)) then
        local ok, inRange, checkedRange = pcall(UnitInRange, frame.unitSUF)
        if ok and not frame.disableRangeAlpha then
            local secret = issecretvalue and (issecretvalue(inRange) or issecretvalue(checkedRange))
            if secret then
                -- Combat: the range booleans are secret. SetAlphaFromBoolean sets
                -- alpha from the secret without reading it. Can't no-op cache a
                -- value we can't see, so invalidate the cache.
                if frame.SetAlphaFromBoolean then
                    frame:SetAlphaFromBoolean(inRange, inAlpha, oorAlpha)
                    frame._rangeLastAlpha = nil
                    return
                end
            elseif SafeBool(checkedRange) then
                -- Readable: checkedRange true means the unit was really tested, so
                -- a false inRange is meaningful. Safe to no-op cache.
                applyRangeAlpha(frame, SafeAlphaFromBool(inRange, inAlpha, oorAlpha))
                return
            end
            -- checkedRange readable-false = untestable unit: fall through.
        end
        -- Not ok or fader active: fall through, next tick after release reapplies.
    end

    if InCombatLockdown() then
        applyRangeAlpha(frame, inAlpha)
        return
    end

    -- Fallback: CheckInteractDistance for non-group units (friendly NPCs, etc.)
    -- distIndex 4 ~ 28 yards
    -- Returns 1 when in range, nil when out of range or the check isn't available
    local ok, inDist = pcall(CheckInteractDistance, frame.unitSUF, 4)
    if ok and inDist ~= nil then
        applyRangeAlpha(frame, inDist and inAlpha or oorAlpha)
        return
    end

    -- Interact distance unavailable (nil/errored): default to visible
    applyRangeAlpha(frame, inAlpha)
end

local function updateSpellCache(category)
	rangeSpells[category] = nil
	if( ShadowUF.db.profile.range[category .. playerClass] and IsSpellUsable(ShadowUF.db.profile.range[category .. playerClass]) ) then
		rangeSpells[category] = ShadowUF.db.profile.range[category .. playerClass]

	elseif( ShadowUF.db.profile.range[category .. "Alt" .. playerClass] and IsSpellUsable(ShadowUF.db.profile.range[category .. "Alt" .. playerClass]) ) then
		rangeSpells[category] = ShadowUF.db.profile.range[category .. "Alt" .. playerClass]

	elseif( Range[category][playerClass] ) then
		if( type(Range[category][playerClass]) == "table" ) then
			for i = 1, #Range[category][playerClass] do
				local spell = Range[category][playerClass][i]
				if( spell and IsSpellUsable(spell) ) then
					rangeSpells[category] = spell
					break
				end
			end
		elseif( Range[category][playerClass] and IsSpellUsable(Range[category][playerClass]) ) then
			rangeSpells[category] = Range[category][playerClass]
		end
	end
end

-- Shared ticker, one single timer iterates all visible range-enabled frames
local rangeFrames = {}
local sharedTicker = nil

local function sharedRangeCheck()
	for frame in pairs(rangeFrames) do
		if frame:IsVisible() and frame.range and frame.range.timer then
			checkRange(frame.range.timer)
		end
	end
end

local function ensureSharedTicker()
	if not sharedTicker then
		local rate = ShadowUF.Performance:GetRate("rangeCheck")
		sharedTicker = C_Timer.NewTicker(rate, sharedRangeCheck)
	end
end

local function stopSharedTicker()
	if sharedTicker and not next(rangeFrames) then
		sharedTicker:Cancel()
		sharedTicker = nil
	end
end

local function createTimer(frame)
	if not frame.range.timer then
		-- Lightweight stub compatible with checkRange(self) reading self.parent
		frame.range.timer = {parent = frame}
	end
	-- Force the next check to apply: the frame's alpha may have been changed
	-- elsewhere (OnDisable reset, layout, fader release) since we last ran.
	frame._rangeLastAlpha = nil
	rangeFrames[frame] = true
	ensureSharedTicker()
end

local function cancelTimer(frame)
	if frame.range and frame.range.timer then
		frame.range.timer = nil
	end
	rangeFrames[frame] = nil
	stopSharedTicker()
end

-- Rebuild shared ticker when rate changes via Performance UI
ShadowUF.Performance:RegisterCallback("rangeCheck", function(newRate)
	if sharedTicker then
		sharedTicker:Cancel()
		sharedTicker = C_Timer.NewTicker(newRate, sharedRangeCheck)
	end
end)

function Range:ForceUpdate(frame)
	-- UnitIsUnit can return secret values for fake units, boolean test must be inside pcall
	local ok, isPlayer = pcall(function() return UnitIsUnit(frame.unitSUF, "player") and true or false end)
	if( ok and isPlayer ) then
		frame:SetRangeAlpha(ShadowUF.db.profile.units[frame.unitType].range.inAlpha)
		cancelTimer(frame)
	else
		createTimer(frame)
		checkRange(frame.range.timer)
	end
end

function Range:OnEnable(frame)
	if( not frame.range ) then
		frame.range = CreateFrame("Frame", nil, frame)
	end

	frame:RegisterNormalEvent("PLAYER_SPECIALIZATION_CHANGED", self, "SpellChecks")
	frame:RegisterUpdateFunc(self, "ForceUpdate")

	createTimer(frame)
end

function Range:OnLayoutApplied(frame)
	self:SpellChecks(frame)
end

function Range:OnDisable(frame)
	frame:UnregisterAll(self)

	if( frame.range ) then
		cancelTimer(frame)
		frame:SetRangeAlpha(1.0)
	end
end


function Range:SpellChecks(frame)
	updateSpellCache("friendly")
	updateSpellCache("hostile")
	if( frame.range and ShadowUF.db.profile.units[frame.unitType].range.enabled ) then
		self:ForceUpdate(frame)
	end
end
