if select(2, UnitClass('player')) ~= 'ROGUE' then
	DisableAddOn('Assassin')
	return
end

-- copy heavily accessed global functions into local scope for performance
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellCharges = _G.GetSpellCharges
local GetTime = _G.GetTime
local UnitCastingInfo = _G.UnitCastingInfo
local UnitAura = _G.UnitAura
-- end copy global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
   return string.lower(str:sub(1, start:len())) == start:lower()
end
-- end useful functions

Assassin = {}
local Opt -- use this as a local table reference to Assassin

SLASH_Assassin1, SLASH_Assassin2 = '/assassin', '/ass'
BINDING_HEADER_ASSASSIN = 'Assassin'

local function InitOpts()
	local function SetDefaults(t, ref)
		local k, v
		for k, v in next, ref do
			if t[k] == nil then
				local pchar
				if type(v) == 'boolean' then
					pchar = v and 'true' or 'false'
				elseif type(v) == 'table' then
					pchar = 'table'
				else
					pchar = v
				end
				t[k] = v
			elseif type(t[k]) == 'table' then
				SetDefaults(t[k], v)
			end
		end
	end
	SetDefaults(Assassin, { -- defaults
		locked = false,
		snap = false,
		scale = {
			main = 1,
			previous = 0.7,
			cooldown = 0.7,
			interrupt = 0.4,
			extra = 0.4,
			glow = 1,
		},
		glow = {
			main = true,
			cooldown = true,
			interrupt = false,
			extra = true,
			blizzard = false,
			color = { r = 1, g = 1, b = 1 },
		},
		hide = {
			assassination = false,
			outlaw = false,
			subtlety = false,
		},
		alpha = 1,
		frequency = 0.2,
		previous = true,
		always_on = false,
		cooldown = true,
		spell_swipe = true,
		dimmer = true,
		miss_effect = true,
		boss_only = false,
		interrupt = true,
		aoe = false,
		auto_aoe = false,
		auto_aoe_ttl = 10,
		pot = false,
		trinket = true,
		poisons = true,
		priority_rotation = false,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	glows = {},
}

-- automatically registered events container
local events = {}

local timer = {
	combat = 0,
	display = 0,
	health = 0
}

-- specialization constants
local SPEC = {
	NONE = 0,
	ASSASSINATION = 1,
	OUTLAW = 2,
	SUBTLETY = 3,
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	spec = 0,
	target_mode = 0,
	gcd = 1,
	health = 0,
	health_max = 0,
	energy = 0,
	energy_max = 100,
	energy_regen = 0,
	combo_points = 0,
	combo_points_max = 5,
	last_swing_taken = 0,
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
	},
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false,
	estimated_range = 30,
}

-- Azerite trait API access
local Azerite = {}

local assassinPanel = CreateFrame('Frame', 'assassinPanel', UIParent)
assassinPanel:SetPoint('CENTER', 0, -169)
assassinPanel:SetFrameStrata('BACKGROUND')
assassinPanel:SetSize(64, 64)
assassinPanel:SetMovable(true)
assassinPanel:Hide()
assassinPanel.icon = assassinPanel:CreateTexture(nil, 'BACKGROUND')
assassinPanel.icon:SetAllPoints(assassinPanel)
assassinPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
assassinPanel.border = assassinPanel:CreateTexture(nil, 'ARTWORK')
assassinPanel.border:SetAllPoints(assassinPanel)
assassinPanel.border:SetTexture('Interface\\AddOns\\Assassin\\border.blp')
assassinPanel.border:Hide()
assassinPanel.dimmer = assassinPanel:CreateTexture(nil, 'BORDER')
assassinPanel.dimmer:SetAllPoints(assassinPanel)
assassinPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
assassinPanel.dimmer:Hide()
assassinPanel.swipe = CreateFrame('Cooldown', nil, assassinPanel, 'CooldownFrameTemplate')
assassinPanel.swipe:SetAllPoints(assassinPanel)
assassinPanel.swipe:SetDrawBling(false)
assassinPanel.text = CreateFrame('Frame', nil, assassinPanel)
assassinPanel.text:SetAllPoints(assassinPanel)
assassinPanel.text.tl = assassinPanel.text:CreateFontString(nil, 'OVERLAY')
assassinPanel.text.tl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
assassinPanel.text.tl:SetPoint('TOPLEFT', assassinPanel, 'TOPLEFT', 2.5, -3)
assassinPanel.text.tl:SetJustifyH('LEFT')
assassinPanel.text.tr = assassinPanel.text:CreateFontString(nil, 'OVERLAY')
assassinPanel.text.tr:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
assassinPanel.text.tr:SetPoint('TOPRIGHT', assassinPanel, 'TOPRIGHT', -2.5, -3)
assassinPanel.text.tr:SetJustifyH('RIGHT')
assassinPanel.text.bl = assassinPanel.text:CreateFontString(nil, 'OVERLAY')
assassinPanel.text.bl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
assassinPanel.text.bl:SetPoint('BOTTOMLEFT', assassinPanel, 'BOTTOMLEFT', 2.5, 3)
assassinPanel.text.bl:SetJustifyH('LEFT')
assassinPanel.text.br = assassinPanel.text:CreateFontString(nil, 'OVERLAY')
assassinPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
assassinPanel.text.br:SetPoint('BOTTOMRIGHT', assassinPanel, 'BOTTOMRIGHT', -2.5, 3)
assassinPanel.text.br:SetJustifyH('RIGHT')
assassinPanel.text.center = assassinPanel.text:CreateFontString(nil, 'OVERLAY')
assassinPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
assassinPanel.text.center:SetAllPoints(assassinPanel.text)
assassinPanel.text.center:SetJustifyH('CENTER')
assassinPanel.text.center:SetJustifyV('CENTER')
assassinPanel.button = CreateFrame('Button', nil, assassinPanel)
assassinPanel.button:SetAllPoints(assassinPanel)
assassinPanel.button:RegisterForClicks('LeftButtonDown', 'RightButtonDown', 'MiddleButtonDown')
local assassinPreviousPanel = CreateFrame('Frame', 'assassinPreviousPanel', UIParent)
assassinPreviousPanel:SetFrameStrata('BACKGROUND')
assassinPreviousPanel:SetSize(64, 64)
assassinPreviousPanel:Hide()
assassinPreviousPanel:RegisterForDrag('LeftButton')
assassinPreviousPanel:SetScript('OnDragStart', assassinPreviousPanel.StartMoving)
assassinPreviousPanel:SetScript('OnDragStop', assassinPreviousPanel.StopMovingOrSizing)
assassinPreviousPanel:SetMovable(true)
assassinPreviousPanel.icon = assassinPreviousPanel:CreateTexture(nil, 'BACKGROUND')
assassinPreviousPanel.icon:SetAllPoints(assassinPreviousPanel)
assassinPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
assassinPreviousPanel.border = assassinPreviousPanel:CreateTexture(nil, 'ARTWORK')
assassinPreviousPanel.border:SetAllPoints(assassinPreviousPanel)
assassinPreviousPanel.border:SetTexture('Interface\\AddOns\\Assassin\\border.blp')
local assassinCooldownPanel = CreateFrame('Frame', 'assassinCooldownPanel', UIParent)
assassinCooldownPanel:SetSize(64, 64)
assassinCooldownPanel:SetFrameStrata('BACKGROUND')
assassinCooldownPanel:Hide()
assassinCooldownPanel:RegisterForDrag('LeftButton')
assassinCooldownPanel:SetScript('OnDragStart', assassinCooldownPanel.StartMoving)
assassinCooldownPanel:SetScript('OnDragStop', assassinCooldownPanel.StopMovingOrSizing)
assassinCooldownPanel:SetMovable(true)
assassinCooldownPanel.icon = assassinCooldownPanel:CreateTexture(nil, 'BACKGROUND')
assassinCooldownPanel.icon:SetAllPoints(assassinCooldownPanel)
assassinCooldownPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
assassinCooldownPanel.border = assassinCooldownPanel:CreateTexture(nil, 'ARTWORK')
assassinCooldownPanel.border:SetAllPoints(assassinCooldownPanel)
assassinCooldownPanel.border:SetTexture('Interface\\AddOns\\Assassin\\border.blp')
assassinCooldownPanel.cd = CreateFrame('Cooldown', nil, assassinCooldownPanel, 'CooldownFrameTemplate')
assassinCooldownPanel.cd:SetAllPoints(assassinCooldownPanel)
local assassinInterruptPanel = CreateFrame('Frame', 'assassinInterruptPanel', UIParent)
assassinInterruptPanel:SetFrameStrata('BACKGROUND')
assassinInterruptPanel:SetSize(64, 64)
assassinInterruptPanel:Hide()
assassinInterruptPanel:RegisterForDrag('LeftButton')
assassinInterruptPanel:SetScript('OnDragStart', assassinInterruptPanel.StartMoving)
assassinInterruptPanel:SetScript('OnDragStop', assassinInterruptPanel.StopMovingOrSizing)
assassinInterruptPanel:SetMovable(true)
assassinInterruptPanel.icon = assassinInterruptPanel:CreateTexture(nil, 'BACKGROUND')
assassinInterruptPanel.icon:SetAllPoints(assassinInterruptPanel)
assassinInterruptPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
assassinInterruptPanel.border = assassinInterruptPanel:CreateTexture(nil, 'ARTWORK')
assassinInterruptPanel.border:SetAllPoints(assassinInterruptPanel)
assassinInterruptPanel.border:SetTexture('Interface\\AddOns\\Assassin\\border.blp')
assassinInterruptPanel.cast = CreateFrame('Cooldown', nil, assassinInterruptPanel, 'CooldownFrameTemplate')
assassinInterruptPanel.cast:SetAllPoints(assassinInterruptPanel)
local assassinExtraPanel = CreateFrame('Frame', 'assassinExtraPanel', UIParent)
assassinExtraPanel:SetFrameStrata('BACKGROUND')
assassinExtraPanel:SetSize(64, 64)
assassinExtraPanel:Hide()
assassinExtraPanel:RegisterForDrag('LeftButton')
assassinExtraPanel:SetScript('OnDragStart', assassinExtraPanel.StartMoving)
assassinExtraPanel:SetScript('OnDragStop', assassinExtraPanel.StopMovingOrSizing)
assassinExtraPanel:SetMovable(true)
assassinExtraPanel.icon = assassinExtraPanel:CreateTexture(nil, 'BACKGROUND')
assassinExtraPanel.icon:SetAllPoints(assassinExtraPanel)
assassinExtraPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
assassinExtraPanel.border = assassinExtraPanel:CreateTexture(nil, 'ARTWORK')
assassinExtraPanel.border:SetAllPoints(assassinExtraPanel)
assassinExtraPanel.border:SetTexture('Interface\\AddOns\\Assassin\\border.blp')

-- Start AoE

Player.target_modes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.ASSASSINATION] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
	[SPEC.OUTLAW] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
	[SPEC.SUBTLETY] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(mode, #self.target_modes[self.spec])
	self.enemies = self.target_modes[self.spec][self.target_mode][1]
	assassinPanel.text.br:SetText(self.target_modes[self.spec][self.target_mode][2])
end

function Player:ToggleTargetMode()
	local mode = self.target_mode + 1
	self:SetTargetMode(mode > #self.target_modes[self.spec] and 1 or mode)
end

function Player:ToggleTargetModeReverse()
	local mode = self.target_mode - 1
	self:SetTargetMode(mode < 1 and #self.target_modes[self.spec] or mode)
end

-- Target Mode Keybinding Wrappers
function Assassin_SetTargetMode(mode)
	Player:SetTargetMode(mode)
end

function Assassin_ToggleTargetMode()
	Player:ToggleTargetMode()
end

function Assassin_ToggleTargetModeReverse()
	Player:ToggleTargetModeReverse()
end

-- End AoE

-- Start Auto AoE

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		[120651] = true, -- Explosives (Mythic+ affix)
	},
}

function autoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local unitId = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	if unitId and self.ignored_units[tonumber(unitId)] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function autoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function autoAoe:Clear()
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
	local count, i = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		Player:SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #Player.target_modes[Player.spec], 1, -1 do
		if count >= Player.target_modes[Player.spec][i][1] then
			Player:SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function autoAoe:Purge()
	local update, guid, t
	for guid, t in next, self.targets do
		if Player.time - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	-- remove expired blacklisted enemies
	for guid, t in next, self.blacklist do
		if Player.time > t then
			self.blacklist[guid] = nil
		end
	end
	if update then
		self:Update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {}
}

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellId = spellId,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		energy_cost = 0,
		cp_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
		velocity = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, self)
	abilities.all[#abilities.all + 1] = ability
	return ability
end

function Ability:Match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function Ability:Usable(pool)
	if not self.known then
		return false
	end
	if not pool then
		if self:EnergyCost() > Player.energy then
			return false
		end
	end
	if self:CPCost() > Player.combo_points then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready()
end

function Ability:Remains()
	if self:Casting() or self:Traveling() then
		return self:Duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - Player.ctime - Player.execute_remains, 0)
		end
	end
	return 0
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up()
	return self:Remains() > 0
end

function Ability:Down()
	return not self:Up()
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.travel_start = {}
	else
		self.travel_start = nil
		self.velocity = 0
	end
end

function Ability:Traveling()
	if self.travel_start and self.travel_start[Target.guid] then
		if Player.time - self.travel_start[Target.guid] < self.max_range / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:Up() and 1 or 0
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:Stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:Match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:EnergyCost()
	return self.energy_cost
end

function Ability:CPCost()
	return self.cp_cost
end

function Ability:Charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.ability_casting == self
end

function Ability:Channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:CastTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and Player.gcd or 0
	end
	return castTime / 1000
end

function Ability:CastEnergyRegen()
	return Player.energy_regen * self:CastTime() - self:EnergyCost()
end

function Ability:WontCapEnergy(reduction)
	return (Player.energy + self:CastEnergyRegen()) < (Player.energy_max - (reduction or 5))
end

function Ability:Previous(n)
	local i = n or 1
	if Player.ability_casting then
		if i == 1 then
			return Player.ability_casting == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:AzeriteRank()
	return Azerite.traits[self.spellId] or 0
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {}
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	else
		self.auto_aoe.trigger = 'SPELL_DAMAGE'
	end
end

function Ability:RecordTargetHit(guid)
	self.auto_aoe.targets[guid] = Player.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:UpdateTargetsHit()
	if self.auto_aoe.start_time and Player.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		if self.auto_aoe.remove then
			autoAoe:Clear()
		end
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
		end
		autoAoe:Update()
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	local _, ability
	for _, ability in next, abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {
		expires = Player.time + self:Duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:RefreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:ApplyAura(guid)
		return
	end
	local duration = self:Duration()
	aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Rogue Abilities
---- Multiple Specializations
local Kick = Ability:Add(1766, false, true)
Kick.cooldown_duration = 15
Kick.triggers_gcd = false
local Stealth = Ability:Add(1784, true, true, 115191)
local Vanish = Ability:Add(1856, true, true, 11327)
------ Procs

------ Talents
local Alacrity = Ability:Add(193539, true, true)
Alacrity.buff_duration = 20
local Anticipation = Ability:Add(114015, false, true)
local DeeperStratagem = Ability:Add(193531, false, true)
local MarkedForDeath = Ability:Add(137619, false, true)
MarkedForDeath.cooldown_duration = 60
MarkedForDeath.triggers_gcd = false
local Nightstalker = Ability:Add(14062, false, true)
local ShadowFocus = Ability:Add(108209, false, true)
local Subterfuge = Ability:Add(108208, true, true, 115192)
local Vigor = Ability:Add(14983, false, true)
---- Assassination
local Envenom = Ability:Add(32645, true, true)
Envenom.buff_duration = 1
Envenom.energy_cost = 25
Envenom.cp_cost = 1
local FanOfKnives = Ability:Add(51723, false, true)
FanOfKnives.energy_cost = 35
FanOfKnives.cp_cost = -1
FanOfKnives:AutoAoe(true)
local Garrote = Ability:Add(703, false, true)
Garrote.buff_duration = 18
Garrote.cooldown_duration = 15
Garrote.energy_cost = 45
Garrote.cp_cost = -1
Garrote.tick_interval = 2
Garrote.hasted_ticks = true
Garrote:TrackAuras()
local Mutilate = Ability:Add(1329, false, true)
Mutilate.energy_cost = 55
Mutilate.cp_cost = -2
local Rupture = Ability:Add(1943, false, true)
Rupture.buff_duration = 4
Rupture.energy_cost = 25
Rupture.cp_cost = 1
Rupture.tick_interval = 2
Rupture.hasted_ticks = true
Rupture:TrackAuras()
local SurgeOfToxins = Ability:Add(192425, false, true)
SurgeOfToxins.buff_duration = 5
local Vendetta = Ability:Add(79140, false, true)
Vendetta.buff_duration = 20
Vendetta.cooldown_duration = 120
Vendetta.triggers_gcd = false
local VirulentPoisons = Ability:Add(252277, true, true)
VirulentPoisons.buff_duration = 6
------ Poisons
local CripplingPoison = Ability:Add(3408, true, true)
CripplingPoison.triggers_gcd = false
CripplingPoison.dot = Ability:Add(3409, false, true)
CripplingPoison.dot.buff_duration = 12
local DeadlyPoison = Ability:Add(2823, true, true)
DeadlyPoison.triggers_gcd = false
DeadlyPoison.dot = Ability:Add(2818, false, true)
DeadlyPoison.dot.buff_duration = 12
DeadlyPoison.dot.tick_interval = 2
DeadlyPoison.dot.hasted_ticks = true
DeadlyPoison.dot:TrackAuras()
local WoundPoison = Ability:Add(8679, true, true)
WoundPoison.triggers_gcd = false
WoundPoison.dot = Ability:Add(8680, false, true)
WoundPoison.dot.buff_duration = 12
WoundPoison.dot:TrackAuras()
------ Talents
local DeathFromAbove = Ability:Add(152150, false, true)
DeathFromAbove.cooldown_duration = 20
DeathFromAbove.energy_cost = 25
DeathFromAbove.cp_cost = 1
DeathFromAbove:AutoAoe(true)
local ElaboratePlanning = Ability:Add(193640, false, true, 193641)
ElaboratePlanning.buff_duration = 5
local Exsanguinate = Ability:Add(200806, false, true)
Exsanguinate.cooldown_duration = 45
Exsanguinate.energy_cost = 25
local Hemorrhage = Ability:Add(16511, false, true)
Hemorrhage.buff_duration = 20
Hemorrhage.energy_cost = 30
Hemorrhage.cp_cost = -1
local MasterPoisoner = Ability:Add(196864, false, true)
local ToxicBlade = Ability:Add(245388, false, true, 245389)
ToxicBlade.buff_duration = 9
ToxicBlade.cooldown_duration = 25
ToxicBlade.energy_cost = 20
ToxicBlade.cp_cost = -1
local VenomRush = Ability:Add(152152, false, true)
------ Procs

---- Outlaw

------ Talents

------ Procs

---- Subtlety
local Backstab = Ability:Add(53, false, true)
Backstab.energy_cost = 35
Backstab.cp_cost = -1
local Eviscerate = Ability:Add(196819, false, true)
Eviscerate.energy_cost = 35
Eviscerate.cp_cost = 1
local Nightblade = Ability:Add(195452, false, true)
Nightblade.energy_cost = 25
Nightblade.cp_cost = 1
Nightblade.buff_duration = 6
Nightblade.tick_interval = 2
Nightblade.hasted_ticks = true
Nightblade:TrackAuras()
local ShadowBlades = Ability:Add(121471, true, true)
ShadowBlades.buff_duration = 20
ShadowBlades.cooldown_duration = 180
local ShadowDance = Ability:Add(185313, true, true, 185422)
ShadowDance.buff_duration = 5
ShadowDance.cooldown_duration = 60
ShadowDance.requires_charge = true
ShadowDance.triggers_gcd = false
local Shadowstrike = Ability:Add(185438, false, true)
Shadowstrike.energy_cost = 40
Shadowstrike.cp_cost = -2
local ShurikenStorm = Ability:Add(197835, false, true)
ShurikenStorm.energy_cost = 35
ShurikenStorm.cp_cost = -2
ShurikenStorm:AutoAoe(true)
local ShurikenToss = Ability:Add(114014, false, true)
ShurikenToss.energy_cost = 40
ShurikenToss.cp_cost = -1
local SymbolsOfDeath = Ability:Add(212283, true, true)
SymbolsOfDeath.buff_duration = 10
SymbolsOfDeath.cooldown_duration = 30
------ Talents
local Gloomblade = Ability:Add(200758, false, true)
Gloomblade.energy_cost = 35
Gloomblade.cp_cost = -1
local DarkShadow = Ability:Add(245687, false, true)
local FindWeakness = Ability:Add(91023, false, true, 91021)
FindWeakness.buff_duration = 10
local MasterOfShadows = Ability:Add(196976, false, true)
local SecretTechnique = Ability:Add(280719, true, true)
SecretTechnique.energy_cost = 30
SecretTechnique.cp_cost = 1
SecretTechnique:AutoAoe(true)
local ShurikenTornado = Ability:Add(277925, true, true)
ShurikenTornado.energy_cost = 60
ShurikenTornado.buff_duration = 4
ShurikenTornado.cooldown_duration = 60
ShurikenTornado.tick_interval = 1
ShurikenTornado:AutoAoe(true)
------ Procs

-- Azerite Traits
local BladeInTheShadows = Ability:Add(275896, true, true, 279754)
BladeInTheShadows.buff_duration = 60
local Inevitability = Ability:Add(278683, false, true)
local NightsVengeance = Ability:Add(273418, true, true, 273424)
NightsVengeance.buff_duration = 8
local Perforate = Ability:Add(277673, true, true, 277720)
Perforate.buff_duration = 12
local SharpenedBlades = Ability:Add(272911, true, true, 272916)
SharpenedBlades.buff_duration = 20
local TheFirstDance = Ability:Add(278861, true, true, 278981)
TheFirstDance.buff_duration = 5
-- Heart of Azeroth
---- Major Essences
local BloodOfTheEnemy = Ability:Add(298277, false, true)
BloodOfTheEnemy.buff_duration = 10
BloodOfTheEnemy.cooldown_duration = 120
BloodOfTheEnemy.essence_id = 23
BloodOfTheEnemy.essence_major = true
local ConcentratedFlame = Ability:Add(295373, true, true, 295378)
ConcentratedFlame.buff_duration = 180
ConcentratedFlame.cooldown_duration = 30
ConcentratedFlame.requires_charge = true
ConcentratedFlame.essence_id = 12
ConcentratedFlame.essence_major = true
ConcentratedFlame:SetVelocity(40)
ConcentratedFlame.dot = Ability:Add(295368, false, true)
ConcentratedFlame.dot.buff_duration = 6
ConcentratedFlame.dot.tick_interval = 2
ConcentratedFlame.dot.essence_id = 12
ConcentratedFlame.dot.essence_major = true
local GuardianOfAzeroth = Ability:Add(295840, false, true)
GuardianOfAzeroth.cooldown_duration = 180
GuardianOfAzeroth.essence_id = 14
GuardianOfAzeroth.essence_major = true
local FocusedAzeriteBeam = Ability:Add(295258, false, true)
FocusedAzeriteBeam.cooldown_duration = 90
FocusedAzeriteBeam.essence_id = 5
FocusedAzeriteBeam.essence_major = true
local MemoryOfLucidDreams = Ability:Add(298357, true, true)
MemoryOfLucidDreams.buff_duration = 15
MemoryOfLucidDreams.cooldown_duration = 120
MemoryOfLucidDreams.essence_id = 27
MemoryOfLucidDreams.essence_major = true
local PurifyingBlast = Ability:Add(295337, false, true, 295338)
PurifyingBlast.cooldown_duration = 60
PurifyingBlast.essence_id = 6
PurifyingBlast.essence_major = true
PurifyingBlast:AutoAoe(true)
local ReapingFlames = Ability:Add(310690, false, true) -- 311195
ReapingFlames.cooldown_duration = 45
ReapingFlames.essence_id = 35
ReapingFlames.essence_major = true
local RippleInSpace = Ability:Add(302731, true, true)
RippleInSpace.buff_duration = 2
RippleInSpace.cooldown_duration = 60
RippleInSpace.essence_id = 15
RippleInSpace.essence_major = true
local TheUnboundForce = Ability:Add(298452, false, true)
TheUnboundForce.cooldown_duration = 45
TheUnboundForce.essence_id = 28
TheUnboundForce.essence_major = true
local VisionOfPerfection = Ability:Add(299370, true, true, 303345)
VisionOfPerfection.buff_duration = 10
VisionOfPerfection.essence_id = 22
VisionOfPerfection.essence_major = true
local WorldveinResonance = Ability:Add(295186, true, true)
WorldveinResonance.cooldown_duration = 60
WorldveinResonance.essence_id = 4
WorldveinResonance.essence_major = true
---- Minor Essences
local AncientFlame = Ability:Add(295367, false, true)
AncientFlame.buff_duration = 10
AncientFlame.essence_id = 12
local CondensedLifeForce = Ability:Add(295367, false, true)
CondensedLifeForce.essence_id = 14
local FocusedEnergy = Ability:Add(295248, true, true)
FocusedEnergy.buff_duration = 4
FocusedEnergy.essence_id = 5
local Lifeblood = Ability:Add(295137, true, true)
Lifeblood.essence_id = 4
local LucidDreams = Ability:Add(298343, true, true)
LucidDreams.buff_duration = 8
LucidDreams.essence_id = 27
local PurificationProtocol = Ability:Add(295305, false, true)
PurificationProtocol.essence_id = 6
PurificationProtocol:AutoAoe()
local RealityShift = Ability:Add(302952, true, true)
RealityShift.buff_duration = 20
RealityShift.cooldown_duration = 30
RealityShift.essence_id = 15
local RecklessForce = Ability:Add(302932, true, true)
RecklessForce.buff_duration = 3
RecklessForce.essence_id = 28
RecklessForce.counter = Ability:Add(302917, true, true)
RecklessForce.counter.essence_id = 28
local StriveForPerfection = Ability:Add(299369, true, true)
StriveForPerfection.essence_id = 22
-- Racials
local ArcaneTorrent = Ability:Add(25046, true, false) -- Blood Elf
local Shadowmeld = Ability:Add(58984, true, true) -- Night Elf

-- PvP talents

-- Trinket Effects

-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems, Trinket = {}, {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
	}
	setmetatable(item, self)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:Charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:Cooldown()
	local startTime, duration
	if self.equip_slot then
		startTime, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		startTime, duration = GetItemCooldown(self.itemId)
	end
	return startTime == 0 and 0 or duration - (Player.ctime - startTime)
end

function InventoryItem:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function InventoryItem:Equipped()
	return self.equip_slot and true
end

function InventoryItem:Usable(seconds)
	if not self.can_use then
		return false
	end
	if not self:Equipped() and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

-- Inventory Items
local GreaterFlaskOfTheCurrents = InventoryItem:Add(168651)
GreaterFlaskOfTheCurrents.buff = Ability:Add(298836, true, true)
local SuperiorBattlePotionOfAgility = InventoryItem:Add(168489)
SuperiorBattlePotionOfAgility.buff = Ability:Add(298146, true, true)
SuperiorBattlePotionOfAgility.buff.triggers_gcd = false
local PotionOfUnbridledFury = InventoryItem:Add(169299)
PotionOfUnbridledFury.buff = Ability:Add(300714, true, true)
PotionOfUnbridledFury.buff.triggers_gcd = false
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Azerite Trait API

Azerite.equip_slots = { 1, 3, 5 } -- Head, Shoulder, Chest

function Azerite:Init()
	self.locations = {}
	self.traits = {}
	self.essences = {}
	local i
	for i = 1, #self.equip_slots do
		self.locations[i] = ItemLocation:CreateFromEquipmentSlot(self.equip_slots[i])
	end
end

function Azerite:Update()
	local _, loc, slot, pid, pinfo
	for pid in next, self.traits do
		self.traits[pid] = nil
	end
	for pid in next, self.essences do
		self.essences[pid] = nil
	end
	if UnitEffectiveLevel('player') < 110 then
		return -- disable all Azerite/Essences for players scaled under 110
	end
	for _, loc in next, self.locations do
		if GetInventoryItemID('player', loc:GetEquipmentSlot()) and C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItem(loc) then
			for _, slot in next, C_AzeriteEmpoweredItem.GetAllTierInfo(loc) do
				if slot.azeritePowerIDs then
					for _, pid in next, slot.azeritePowerIDs do
						if C_AzeriteEmpoweredItem.IsPowerSelected(loc, pid) then
							self.traits[pid] = 1 + (self.traits[pid] or 0)
							pinfo = C_AzeriteEmpoweredItem.GetPowerInfo(pid)
							if pinfo and pinfo.spellID then
								--print('Azerite found:', pinfo.azeritePowerID, GetSpellInfo(pinfo.spellID))
								self.traits[pinfo.spellID] = self.traits[pid]
							end
						end
					end
				end
			end
		end
	end
	for _, loc in next, C_AzeriteEssence.GetMilestones() or {} do
		if loc.slot then
			pid = C_AzeriteEssence.GetMilestoneEssence(loc.ID)
			if pid then
				pinfo = C_AzeriteEssence.GetEssenceInfo(pid)
				self.essences[pid] = {
					id = pid,
					rank = pinfo.rank,
					major = loc.slot == 0,
				}
			end
		end
	end
end

-- End Azerite Trait API

-- Start Player API

function Player:Health()
	return self.health
end

function Player:HealthMax()
	return self.health_max
end

function Player:HealthPct()
	return self.health / self.health_max * 100
end

function Player:Energy()
	return self.energy
end

function Player:EnergyRegen()
	return self.energy_regen
end

function Player:EnergyDeficit()
	return self.energy_max - self.energy
end

function Player:EnergyTimeToMax()
	local deficit = self.energy_max - self.energy
	if deficit <= 0 then
		return 0
	end
	return deficit / self.energy_regen
end

function Player:ComboPoints()
	return self.combo_points
end

function Player:ComboPointsDeficit()
	return self.combo_points_max - self.combo_points
end

function Player:ComboPointsMaxSpend()
	return DeeperStratagem.known and 6 or 5
end

function Player:UnderAttack()
	return (Player.time - self.last_swing_taken) < 3
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	return 0
end

function Player:BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if (
			id == 2825 or   -- Bloodlust (Horde Shaman)
			id == 32182 or  -- Heroism (Alliance Shaman)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			id == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740    -- Drums of the Maelstrom (Leatherworking)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	if slot then
		return GetInventoryItemID('player', slot) == itemID, slot
	end
	local i
	for i = 1, 19 do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateAbilities()
	self.energy_max = UnitPowerMax('player', 3)
	self.combo_points_max = UnitPowerMax('player', 4)

	local _, ability

	for _, ability in next, abilities.all do
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
		ability.known = false
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.spellId2 and C_LevelLink.IsSpellLocked(ability.spellId2)) then
			-- spell is locked, do not mark as known
		elseif IsPlayerSpell(ability.spellId) or (ability.spellId2 and IsPlayerSpell(ability.spellId2)) then
			ability.known = true
		elseif Azerite.traits[ability.spellId] then
			ability.known = true
		elseif ability.essence_id and Azerite.essences[ability.essence_id] then
			if ability.essence_major then
				ability.known = Azerite.essences[ability.essence_id].major
			else
				ability.known = true
			end
		end
	end

	abilities.bySpellId = {}
	abilities.velocity = {}
	abilities.autoAoe = {}
	abilities.trackAuras = {}
	for _, ability in next, abilities.all do
		if ability.known then
			abilities.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				abilities.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				abilities.velocity[#abilities.velocity + 1] = ability
			end
			if ability.auto_aoe then
				abilities.autoAoe[#abilities.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				abilities.trackAuras[#abilities.trackAuras + 1] = ability
			end
		end
	end
end

-- End Player API

-- Start Target API

function Target:UpdateHealth()
	timer.health = 0
	self.health = UnitHealth('target')
	self.health_max = UnitHealthMax('target')
	table.remove(self.healthArray, 1)
	self.healthArray[25] = self.health
	self.timeToDieMax = self.health / Player.health_max * 15
	self.healthPercentage = self.health_max > 0 and (self.health / self.health_max * 100) or 100
	self.healthLostPerSec = (self.healthArray[1] - self.health) / 5
	self.timeToDie = self.healthLostPerSec > 0 and min(self.timeToDieMax, self.health / self.healthLostPerSec) or self.timeToDieMax
end

function Target:Update()
	UI:Disappear()
	if UI:ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = UnitLevel('player')
		self.hostile = true
		local i
		for i = 1, 25 do
			self.healthArray[i] = 0
		end
		self:UpdateHealth()
		if Opt.always_on then
			UI:UpdateCombat()
			assassinPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			assassinPreviousPanel:Hide()
		end
		return
	end
	if guid ~= self.guid then
		self.guid = guid
		local i
		for i = 1, 25 do
			self.healthArray[i] = UnitHealth('target')
		end
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self:UpdateHealth()
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= UnitLevel('player') + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health_max > Player.health_max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		assassinPanel:Show()
		return true
	end
end

-- End Target API

-- Start Ability Modifications

function Ability:EnergyCost()
	local cost = self.energy_cost
	if ShadowFocus.known and Player.stealthed then
		cost = cost - (cost * 0.20)
	end
	return cost
end

function ConcentratedFlame.dot:Remains()
	if ConcentratedFlame:Traveling() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function Envenom:Duration()
	return self.buff_duration + Player.combo_points
end

function Rupture:Duration()
	return self.buff_duration + (4 * Player.combo_points)
end

function Nightblade:Duration()
	return self.buff_duration + (2 * Player.combo_points)
end

function Vanish:Usable()
	if not UnitInParty('player') then
		return false
	end
	return Ability.Usable(self)
end

local function TickingPoisoned(self)
	local count, guid, aura, poisoned = 0
	for guid, aura in next, self.aura_targets do
		if aura.expires - Player.time > Player.execute_remains then
			poisoned = DeadlyPoison.dot.aura_targets[guid] or WoundPoison.dot.aura_targets[guid]
			if poisoned then
				if poisoned.expires - Player.time > Player.execute_remains then
					count = count + 1
				end
			end
		end
	end
	return count
end

Garrote.TickingPoisoned = TickingPoisoned
Rupture.TickingPoisoned = TickingPoisoned

-- End Ability Modifications

local function UseCooldown(ability, overwrite)
	if Opt.cooldown and (not Opt.boss_only or Target.boss) and (not Player.cd or overwrite) then
		Player.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not Player.extra or overwrite then
		Player.extra = ability
	end
end

local function Pool(ability, extra)
	Player.pool_energy = ability:EnergyCost() + (extra or 0)
	return ability
end

-- Begin Action Priority Lists

local APL = {
	[SPEC.NONE] = {
		main = function() end
	},
	[SPEC.ASSASSINATION] = {},
	[SPEC.OUTLAW] = {},
	[SPEC.SUBTLETY] = {}
}

APL[SPEC.ASSASSINATION].main = function(self)
	if Player:TimeInCombat() == 0 then
		if Opt.poisons then
			if WoundPoison:Up() then
				if WoundPoison:Remains() < 300 then
					return WoundPoison
				end
			elseif DeadlyPoison:Remains() < 300 then
				return DeadlyPoison
			end
			if CripplingPoison:Up() then
				if CripplingPoison:Remains() < 300 then
					return CripplingPoison
				end
			end
		end
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfEndlessFathoms:Usable() and GreaterFlaskOfEndlessFathoms.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheCurrents)
			end
		end
		if not Player.stealthed then
			return Stealth
		end
		if Opt.pot and not Player:InArenaOrBattleground() then
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
		end
	end
	Player.energy_regen_combined = Player.energy_regen + (Garrote:TickingPoisoned() + Rupture:TickingPoisoned()) * (VenomRush.known and 10 or 7) / 2
	Player.energy_time_to_max_combined = Player:EnergyDeficit() / Player.energy_regen_combined
	local apl
	if Player:TimeInCombat() > 0 then
		apl = self:cds()
		if apl then return apl end
	end
	if Player.enemies > 2 then
		return self:aoe()
	end
	if Player.stealthed then
		return self:stealthed()
	end
	apl = self:maintain()
	if apl then return apl end
	if not Exsanguinate.known or Exsanguinate:Cooldown() > 2 then
		apl = self:finish()
		if apl then return apl end
	end
	if Player:ComboPointsDeficit() > (Anticipation.known and 2 or 1) or Player:EnergyDeficit() <= 25 + Player.energy_regen_combined then
		apl = self:build()
		if apl then return apl end
	end
end

APL[SPEC.ASSASSINATION].aoe = function(self)
--[[
actions.aoe=envenom,if=!buff.envenom.up&combo_points>=cp_max_spend
actions.aoe+=/rupture,cycle_targets=1,if=combo_points>=cp_max_spend&refreshable&(pmultiplier<=1|remains<=tick_time)&(!exsanguinated|remains<=tick_time*2)&target.time_to_die-remains>4
actions.aoe+=/garrote,cycle_targets=1,if=talent.subterfuge.enabled&stealthed.rogue&refreshable&!exsanguinated
actions.aoe+=/envenom,if=combo_points>=cp_max_spend
actions.aoe+=/fan_of_knives
]]
	if Envenom:Usable() and Envenom:Down() and Player:ComboPoints() >= Player:ComboPointsMaxSpend() then
		return Envenom
	end
	if Rupture:Usable() and Player:ComboPoints() >= Player:ComboPointsMaxSpend() and Rupture:Refreshable() and Target.timeToDie - Rupture:Remains() > 4 then
		return Rupture
	end
	if Subterfuge.known and Garrote:Usable() and Player.stealthed and Garrote:Refreshable() then
		return Garrote
	end
	if Envenom:Usable() and Player:ComboPoints() >= Player:ComboPointsMaxSpend() then
		return Envenom
	end
	return FanOfKnives
end

APL[SPEC.ASSASSINATION].build = function(self)
--[[
actions.build=hemorrhage,if=refreshable
actions.build+=/hemorrhage,cycle_targets=1,if=refreshable&dot.rupture.ticking&spell_targets.fan_of_knives<2+equipped.insignia_of_ravenholdt
actions.build+=/fan_of_knives,if=buff.the_dreadlords_deceit.stack>=29
# Mutilate is worth using over FoK for Exsanguinate builds in some 2T scenarios.
actions.build+=/mutilate,if=talent.exsanguinate.enabled&(debuff.vendetta.up|combo_points<=2)
actions.build+=/fan_of_knives,if=spell_targets>1+equipped.insignia_of_ravenholdt
actions.build+=/fan_of_knives,if=combo_points>=3+talent.deeper_stratagem.enabled&artifact.poison_knives.rank>=5|fok_rotation
actions.build+=/mutilate,cycle_targets=1,if=dot.deadly_poison_dot.refreshable
actions.build+=/mutilate
]]
end

APL[SPEC.ASSASSINATION].cds = function(self)
	if Opt.pot and PotionOfUnbridledFury:Usable() and (Player:BloodlustActive() or Target.timeToDie <= 60 or Vendetta:Up() and Vanish:Ready(5)) then
		return UseCooldown(PotionOfUnbridledFury)
	end
	if ArcaneTorrent:Usable() and Envenom:Down() and Player:EnergyDeficit() >= 15 + Player.energy_regen_combined * Player.gcd_remains * 1.1 then
		return UseCooldown(ArcaneTorrent)
	end
	if MarkedForDeath:Usable() and Target.timeToDie < Player:ComboPointsDeficit() * 1.5 then
		return UseCooldown(MarkedForDeath)
	end
	if Vendetta:Usable() and (not Exsanguinate.known or Rupture:Up()) then
		return UseCooldown(Vendetta)
	end
	if Vanish:Usable() and not Player.stealthed then
		if Target.timeToDie <= 6 then
			return UseCooldown(Vanish)
		end
		if Nightstalker.known then
			if Player:ComboPoints() >= Player:ComboPointsMaxSpend() then
				if not Exsanguinate.known and Vendetta:Up() then
					return UseCooldown(Vanish)
				elseif Exsanguinate.known and Exsanguinate:Ready(1) then
					return UseCooldown(Vanish)
				end
			end
		elseif Subterfuge.known then
			if Garrote:Refreshable() and ((Player.enemies <= 3 and Player:ComboPointsDeficit() >= 1 + Player.enemies) or (Player.enemies >= 4 and Player:ComboPointsDeficit() >= 4)) then
				return UseCooldown(Vanish)
			end
		elseif ShadowFocus.known and Player.energy_time_to_max_combined >= 2 and Player:ComboPointsDeficit() >= 4 then
			return UseCooldown(Vanish)
		end
	end
	if ToxicBlade:Usable() and (Target.timeToDie <= 6 or Player:ComboPointsDeficit() >= 1 and Rupture:Remains() > 8 and Vendetta:Cooldown() > 10) then
		return UseCooldown(ToxicBlade)
	end
end

APL[SPEC.ASSASSINATION].finish = function(self)
--[[
actions.finish=death_from_above,if=combo_points>=5
actions.finish+=/envenom,if=talent.anticipation.enabled&combo_points>=5&((debuff.toxic_blade.up&buff.virulent_poisons.remains<2)|mantle_duration>=0.2|buff.virulent_poisons.remains<0.2|energy.deficit<=25+variable.energy_regen_combined)
actions.finish+=/envenom,if=talent.anticipation.enabled&combo_points>=4&!buff.virulent_poisons.up
actions.finish+=/envenom,if=!talent.anticipation.enabled&combo_points>=4+(talent.deeper_stratagem.enabled&!set_bonus.tier19_4pc)&(debuff.vendetta.up|debuff.toxic_blade.up|mantle_duration>=0.2|debuff.surge_of_toxins.remains<0.2|energy.deficit<=25+variable.energy_regen_combined)
actions.finish+=/envenom,if=talent.elaborate_planning.enabled&combo_points>=3+!talent.exsanguinate.enabled&buff.elaborate_planning.remains<0.2
]]
end

APL[SPEC.ASSASSINATION].maintain = function(self)
--[[
actions.maintain=rupture,if=talent.exsanguinate.enabled&((combo_points>=cp_max_spend&cooldown.exsanguinate.remains<1)|(!ticking&(time>10|combo_points>=2+artifact.urge_to_kill.enabled)))
actions.maintain+=/rupture,cycle_targets=1,if=combo_points>=4&refreshable&(pmultiplier<=1|remains<=tick_time)&(!exsanguinated|remains<=tick_time*2)&target.time_to_die-remains>6
actions.maintain+=/pool_resource,for_next=1
actions.maintain+=/garrote,cycle_targets=1,if=(!talent.subterfuge.enabled|!(cooldown.vanish.up&cooldown.vendetta.remains<=4))&combo_points.deficit>=1&refreshable&(pmultiplier<=1|remains<=tick_time)&(!exsanguinated|remains<=tick_time*2)&target.time_to_die-remains>4
actions.maintain+=/garrote,if=set_bonus.tier20_4pc&talent.exsanguinate.enabled&prev_gcd.1.rupture&cooldown.exsanguinate.remains<1&(!cooldown.vanish.up|time>12)
actions.maintain+=/garrote,if=!set_bonus.tier20_4pc&talent.exsanguinate.enabled&cooldown.exsanguinate.remains<2+2*(cooldown.vanish.remains<2)&time>12
actions.maintain+=/rupture,if=!talent.exsanguinate.enabled&combo_points>=3&!ticking&mantle_duration=0&target.time_to_die>6
]]
end

APL[SPEC.ASSASSINATION].stealthed = function(self)
--[[
actions.stealthed=mutilate,if=talent.shadow_focus.enabled&dot.garrote.ticking
actions.stealthed+=/garrote,cycle_targets=1,if=talent.subterfuge.enabled&combo_points.deficit>=1&set_bonus.tier20_4pc&((dot.garrote.remains<=13&!debuff.toxic_blade.up)|pmultiplier<=1)&!exsanguinated
actions.stealthed+=/garrote,cycle_targets=1,if=talent.subterfuge.enabled&combo_points.deficit>=1&!set_bonus.tier20_4pc&refreshable&(!exsanguinated|remains<=tick_time*2)&target.time_to_die-remains>2
actions.stealthed+=/garrote,cycle_targets=1,if=talent.subterfuge.enabled&combo_points.deficit>=1&!set_bonus.tier20_4pc&remains<=10&pmultiplier<=1&!exsanguinated&target.time_to_die-remains>2
actions.stealthed+=/rupture,cycle_targets=1,if=combo_points>=4&refreshable&(pmultiplier<=1|remains<=tick_time)&(!exsanguinated|remains<=tick_time*2)&target.time_to_die-remains>6
actions.stealthed+=/rupture,if=talent.exsanguinate.enabled&talent.nightstalker.enabled&target.time_to_die-remains>6
actions.stealthed+=/envenom,if=combo_points>=cp_max_spend
actions.stealthed+=/garrote,if=!talent.subterfuge.enabled&target.time_to_die-remains>4
actions.stealthed+=/mutilate
]]
	if ShadowFocus.known and Mutilate:Usable() and Garrote:Ticking() > 0 then
		return Mutilate
	end
	if Subterfuge.known and Garrote:Usable() and Player:ComboPointsDeficit() >= 1 and Garrote:Refreshable() and Garrote:Remains() <= Garrote:TickTime() * 2 and Target.timeToDie - Garrote:Remains() > 2 then
		return Garrote
	end
	if Rupture:Usable() then
		if Rupture:Refreshable() and Player:ComboPoints() >= 4 and Rupture:Remains() <= Rupture:TickTime() and Target.timeToDie - Rupture:Remains() > 6 then
			return Rupture
		end
		if Exsanguinate.known and Nightstalker.known and Target.timeToDie - Rupture:Remains() > 6 then
			return Rupture
		end
	end
	if Envenom:Usable() and Player:ComboPoints() >= Player:ComboPointsMaxSpend() then
		return Envenom
	end
	if not Subterfuge.known and Garrote:Usable() and Target.timeToDie - Garrote:Remains() > 4 then
		return Garrote
	end
	if Mutilate:Usable() then
		return Mutilate
	end
end

APL[SPEC.OUTLAW].main = function(self)
	if Player:TimeInCombat() == 0 then
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfEndlessFathoms:Usable() and GreaterFlaskOfEndlessFathoms.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheCurrents)
			end
		end
		if not Player.stealthed then
			return Stealth
		end
		if Opt.pot and not Player:InArenaOrBattleground() then
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
		end
	end
end

APL[SPEC.SUBTLETY].main = function(self)
	if Player:TimeInCombat() == 0 then
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfEndlessFathoms:Usable() and GreaterFlaskOfEndlessFathoms.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheCurrents)
			end
		end
		if not Player.stealthed then
			return Stealth
		end
		if Opt.pot and not Player:InArenaOrBattleground() then
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
		end
	end
--[[
# Check CDs at first
actions=call_action_list,name=cds
# Run fully switches to the Stealthed Rotation (by doing so, it forces pooling if nothing is available).
actions+=/run_action_list,name=stealthed,if=stealthed.all
# Apply Nightblade at 2+ CP during the first 10 seconds, after that 4+ CP if it expires within the next GCD or is not up
actions+=/nightblade,if=target.time_to_die>6&remains<gcd.max&combo_points>=4-(time<10)*2
# Only change rotation if we have priority_rotation set and multiple targets up.
actions+=/variable,name=use_priority_rotation,value=priority_rotation&spell_targets.shuriken_storm>=2
# Priority Rotation? Let's give a crap about energy for the stealth CDs (builder still respect it). Yup, it can be that simple.
actions+=/call_action_list,name=stealth_cds,if=variable.use_priority_rotation
# Used to define when to use stealth CDs or builders
actions+=/variable,name=stealth_threshold,value=25+talent.vigor.enabled*35+talent.master_of_shadows.enabled*25+talent.shadow_focus.enabled*20+talent.alacrity.enabled*10+15*(spell_targets.shuriken_storm>=3)
# Consider using a Stealth CD when reaching the energy threshold
actions+=/call_action_list,name=stealth_cds,if=energy.deficit<=variable.stealth_threshold
# Night's Vengeance: Nightblade before Symbols at low CP to combine early refresh with getting the buff up. Also low CP during Symbols between Dances with 2+ NV.
actions+=/nightblade,if=azerite.nights_vengeance.enabled&!buff.nights_vengeance.up&combo_points.deficit>1&(spell_targets.shuriken_storm<2|variable.use_priority_rotation)&(cooldown.symbols_of_death.remains<=3|(azerite.nights_vengeance.rank>=2&buff.symbols_of_death.remains>3&!stealthed.all&cooldown.shadow_dance.charges_fractional>=0.9))
# Finish at 4+ without DS, 5+ with DS (outside stealth)
actions+=/call_action_list,name=finish,if=combo_points.deficit<=1|target.time_to_die<=1&combo_points>=3
# With DS also finish at 4+ against exactly 4 targets (outside stealth)
actions+=/call_action_list,name=finish,if=spell_targets.shuriken_storm=4&combo_points>=4
# Use a builder when reaching the energy threshold
actions+=/call_action_list,name=build,if=energy.deficit<=variable.stealth_threshold
# Lowest priority in all of the APL because it causes a GCD
actions+=/arcane_torrent,if=energy.deficit>=15+energy.regen
actions+=/arcane_pulse
actions+=/lights_judgment
actions+=/bag_of_tricks
actions+=/detection,if=equipped.echoing_void|equipped.echoing_void_oh
]]
	Player.use_priority_rotation = Opt.priority_rotation and Player.enemies >= 2
	Player.stealth_threshold = 25 + (Vigor.known and 35 or 0) + (MasterOfShadows.known and 25 or 0) + (ShadowFocus.known and 20 or 0) + (Alacrity.known and 10 or 0) + (Player.enemies >= 3 and 15 or 0)
	local apl
	apl = self:cds()
	if apl then return apl end
	if Player.stealthed then
		return self:stealthed()
	end
	if Nightblade:Usable() and Target.timeToDie > 6 and Nightblade:Remains() < Player.gcd and Player:ComboPoints() >= (Player:TimeInCombat() < 10 and 2 or 4) then
		return Nightblade
	end
	if Player.use_priority_rotation or Player:EnergyDeficit() <= Player.stealth_threshold then
		apl = self:stealth_cds()
		if apl then return apl end
	end
	if Nightblade:Usable() and (NightsVengeance.known and NightsVengeance:Down() and Player:ComboPointsDeficit() > 1 and (Player.enemies < 2 or Player.use_priority_rotation) and (SymbolsOfDeath:Ready(3) or (NightsVengeance:AzeriteRank() >= 2 and SymbolsOfDeath:Remains() > 3 and not Player.stealthed and ShadowDance:ChargesFractional() >= 0.9))) then
		return Nightblade
	end
	if (
		(Player:ComboPoints() >= (DeeperStratagem.known and 5 or 4)) or
		(Player.enemies == 4 and Player:ComboPoints() >= 4) or
		(Player.enemies == 1 and Target.timeToDie < 1 and Player:ComboPoints() >= 3)
	) then
		apl = self:finish()
		if apl then return apl end
	end
	if Player:EnergyDeficit() <= Player.stealth_threshold then
		apl = self:build()
		if apl then return apl end
	end
	if ArcaneTorrent:Usable() and Player:EnergyDeficit() >= 15 + Player:EnergyRegen() then
		UseCooldown(ArcaneTorrent)
	end
end

APL[SPEC.SUBTLETY].cds = function(self)
--[[
# Use Dance off-gcd before the first Shuriken Storm from Tornado comes in.
actions.cds=shadow_dance,use_off_gcd=1,if=!buff.shadow_dance.up&buff.shuriken_tornado.up&buff.shuriken_tornado.remains<=3.5
# (Unless already up because we took Shadow Focus) use Symbols off-gcd before the first Shuriken Storm from Tornado comes in.
actions.cds+=/symbols_of_death,use_off_gcd=1,if=buff.shuriken_tornado.up&buff.shuriken_tornado.remains<=3.5
actions.cds+=/call_action_list,name=essences,if=!stealthed.all&dot.nightblade.ticking
# Pool for Tornado pre-SoD with ShD ready when not running SF.
actions.cds+=/pool_resource,for_next=1,if=!talent.shadow_focus.enabled
# Use Tornado pre SoD when we have the energy whether from pooling without SF or just generally.
actions.cds+=/shuriken_tornado,if=energy>=60&dot.nightblade.ticking&cooldown.symbols_of_death.up&cooldown.shadow_dance.charges>=1
# Use Symbols on cooldown (after first Nightblade) unless we are going to pop Tornado and do not have Shadow Focus.
actions.cds+=/symbols_of_death,if=dot.nightblade.ticking&!cooldown.shadow_blades.up&(!talent.shuriken_tornado.enabled|talent.shadow_focus.enabled|cooldown.shuriken_tornado.remains>2)&(!essence.blood_of_the_enemy.major|cooldown.blood_of_the_enemy.remains>2)&(azerite.nights_vengeance.rank<2|buff.nights_vengeance.up)
# If adds are up, snipe the one with lowest TTD. Use when dying faster than CP deficit or not stealthed without any CP.
actions.cds+=/marked_for_death,target_if=min:target.time_to_die,if=raid_event.adds.up&(target.time_to_die<combo_points.deficit|!stealthed.all&combo_points.deficit>=cp_max_spend)
# If no adds will die within the next 30s, use MfD on boss without any CP and no stealth.
actions.cds+=/marked_for_death,if=raid_event.adds.in>30-raid_event.adds.duration&!stealthed.all&combo_points.deficit>=cp_max_spend
actions.cds+=/shadow_blades,if=!stealthed.all&dot.nightblade.ticking&combo_points.deficit>=2
# With SF, if not already done, use Tornado with SoD up.
actions.cds+=/shuriken_tornado,if=talent.shadow_focus.enabled&dot.nightblade.ticking&buff.symbols_of_death.up
actions.cds+=/shadow_dance,if=!buff.shadow_dance.up&target.time_to_die<=5+talent.subterfuge.enabled&!raid_event.adds.up
actions.cds+=/potion,if=buff.bloodlust.react|buff.symbols_of_death.up&(buff.shadow_blades.up|cooldown.shadow_blades.remains<=10)
actions.cds+=/blood_fury,if=buff.symbols_of_death.up
actions.cds+=/berserking,if=buff.symbols_of_death.up
actions.cds+=/fireblood,if=buff.symbols_of_death.up
actions.cds+=/ancestral_call,if=buff.symbols_of_death.up
actions.cds+=/use_item,effect_name=cyclotronic_blast,if=!stealthed.all&dot.nightblade.ticking&!buff.symbols_of_death.up&energy.deficit>=30
actions.cds+=/use_item,name=azsharas_font_of_power,if=!buff.shadow_dance.up&cooldown.symbols_of_death.remains<10
# Very roughly rule of thumbified maths below: Use for Inkpod crit, otherwise with SoD at 25+ stacks or 15+ with also Blood up.
actions.cds+=/use_item,name=ashvanes_razor_coral,if=debuff.razor_coral_debuff.down|debuff.conductive_ink_debuff.up&target.health.pct<32&target.health.pct>=30|!debuff.conductive_ink_debuff.up&(debuff.razor_coral_debuff.stack>=25-10*debuff.blood_of_the_enemy.up|target.time_to_die<40)&buff.symbols_of_death.remains>8
actions.cds+=/use_item,name=mydas_talisman
# Default fallback for usable items: Use with Symbols of Death.
actions.cds+=/use_items,if=buff.symbols_of_death.up|target.time_to_die<20
]]
	if ShurikenTornado.known and ShurikenTornado:Up() and ShurikenTornado:Remains() <= 3.5 then
		if ShadowDance:Usable() and not Player.stealthed then
			return UseCooldown(ShadowDance)
		end
		if SymbolsOfDeath:Usable() then
			return UseCooldown(SymbolsOfDeath)
		end
	end
	if not Player.stealthed and Nightblade:Ticking() > 0 then
		local apl = self:essences()
		if apl then return apl end
	end
	if ShurikenTornado:Usable(true) and Nightblade:Ticking() > 0 and SymbolsOfDeath:Ready() and ShadowDance:Charges() >= 1 then
		if not ShadowFocus.known then
			return Pool(ShurikenTornado, 60)
		end
		if Player:Energy() >= 60 then
			return UseCooldown(ShurikenTornado)
		end
	end
	if SymbolsOfDeath:Usable() and Nightblade:Ticking() > 0 and not ShadowBlades:Ready() and (not ShurikenTornado.known or ShadowFocus.known or ShurikenTornado:Cooldown() > 2) and (not BloodOfTheEnemy.known or BloodOfTheEnemy:Cooldown() > 2) and (NightsVengeance:AzeriteRank() < 2 or NightsVengeance:Up()) then
		return UseCooldown(SymbolsOfDeath)
	end
	if MarkedForDeath:Usable() and (
		(Player.enemies > 1 and Target.timeToDie < Player:ComboPointsDeficit()) or
		(not Player.stealthed and Player:ComboPointsDeficit() >= Player:ComboPointsMaxSpend())
	) then
		return UseCooldown(MarkedForDeath)
	end
	if ShadowBlades:Usable() and not Player.stealthed and Nightblade:Ticking() > 0 and Player:ComboPointsDeficit() >= 2 then
		return UseCooldown(ShadowBlades)
	end
	if ShurikenTornado:Usable() and ShadowFocus.known and Nightblade:Ticking() > 0 and SymbolsOfDeath:Up() then
		return UseCOoldown(ShurikenTornado)
	end
	if ShadowDance:Usable() and not Player.stealthed and Target.timeToDie <= (Subterfuge.known and 6 or 5) then
		return UseCooldown(ShadowDance)
	end
	if Opt.pot and Target.boss and PotionOfUnbridledFury:Usable() and (Player:BloodlustActive() or SymbolsOfDeath:Up() and (ShadowBlades:Up() or ShadowBlades:Ready(10))) then
		return UseCooldown(PotionOfUnbridledFury)
	end
	if Opt.trinket and (Target.timeToDie < 20 or SymbolsOfDeath:Remains() > 6) then
		if Trinket1:Usable() then
			return UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			return UseCooldown(Trinket2)
		end
	end
end

APL[SPEC.SUBTLETY].stealth_cds = function(self)
--[[
# Helper Variable
actions.stealth_cds=variable,name=shd_threshold,value=cooldown.shadow_dance.charges_fractional>=1.75
# Vanish unless we are about to cap on Dance charges. Only when Find Weakness is about to run out.
actions.stealth_cds+=/vanish,if=!variable.shd_threshold&combo_points.deficit>1&debuff.find_weakness.remains<1&cooldown.symbols_of_death.remains>=3
# Pool for Shadowmeld + Shadowstrike unless we are about to cap on Dance charges. Only when Find Weakness is about to run out.
actions.stealth_cds+=/pool_resource,for_next=1,extra_amount=40
actions.stealth_cds+=/shadowmeld,if=energy>=40&energy.deficit>=10&!variable.shd_threshold&combo_points.deficit>1&debuff.find_weakness.remains<1
# CP requirement: Dance at low CP by default.
actions.stealth_cds+=/variable,name=shd_combo_points,value=combo_points.deficit>=4
# CP requirement: Dance only before finishers if we have amp talents and priority rotation.
actions.stealth_cds+=/variable,name=shd_combo_points,value=combo_points.deficit<=1+2*azerite.the_first_dance.enabled,if=variable.use_priority_rotation&(talent.nightstalker.enabled|talent.dark_shadow.enabled)
# With Dark Shadow only Dance when Nightblade will stay up. Use during Symbols or above threshold. Wait for NV buff with 2+NV.
actions.stealth_cds+=/shadow_dance,if=variable.shd_combo_points&(!talent.dark_shadow.enabled|dot.nightblade.remains>=5+talent.subterfuge.enabled)&(variable.shd_threshold|buff.symbols_of_death.remains>=1.2|spell_targets.shuriken_storm>=4&cooldown.symbols_of_death.remains>10)&(azerite.nights_vengeance.rank<2|buff.nights_vengeance.up)
# Burn remaining Dances before the target dies if SoD won't be ready in time.
actions.stealth_cds+=/shadow_dance,if=variable.shd_combo_points&target.time_to_die<cooldown.symbols_of_death.remains&!raid_event.adds.up
]]
	Player.shd_threshold = ShadowDance:ChargesFractional() >= 1.75
	if not Player.shd_threshold and Player:ComboPointsDeficit() > 1 and FindWeakness:Remains() < 1 then
		if Vanish:Usable() and not SymbolsOfDeath:Ready(3) then
			return UseCooldown(Vanish)
		end
		if Shadowmeld:Usable() and Player:Energy() >= 40 and Player:EnergyDeficit() >= 10 then
			return Pool(Shadowmeld, 80)
		end
	end
	if Player.use_priority_rotation and (Nightstalker.known or DarkShadow.known) then
		Player.shd_combo_points = Player:ComboPointsDeficit() <= (TheFirstDance.known and 3 or 1)
	else
		Player.shd_combo_points = Player:ComboPointsDeficit() >= 4
	end
	if ShadowDance:Usable() and not Player.stealthed and Player.shd_combo_points then
		if (not DarkShadow.known or Nightblade:Remains() >= (Subterfuge.known and 6 or 5)) and (Player.shd_threshold or SymbolsOfDeath:Remains() >= 1.2 or (Player.enemies >= 4 and SymbolsOfDeath:Cooldown() > 10)) and (NightsVengeance:AzeriteRank() < 2 or NightsVengeance:Up()) then
			return UseCooldown(ShadowDance)
		end
		if Player.enemies == 1 and Target.timeToDie < SymbolsOfDeath:Cooldown() then
			return UseCooldown(ShadowDance)
		end
	end
end

APL[SPEC.SUBTLETY].essences = function(self)
--[[
actions.essences=concentrated_flame,if=energy.time_to_max>1&!buff.symbols_of_death.up&(!dot.concentrated_flame_burn.ticking&!action.concentrated_flame.in_flight|full_recharge_time<gcd.max)
actions.essences+=/blood_of_the_enemy,if=!cooldown.shadow_blades.up&cooldown.symbols_of_death.up|target.time_to_die<=10
actions.essences+=/guardian_of_azeroth
actions.essences+=/focused_azerite_beam,if=(spell_targets.shuriken_storm>=2|raid_event.adds.in>60)&!cooldown.symbols_of_death.up&!buff.symbols_of_death.up&energy.deficit>=30
actions.essences+=/purifying_blast,if=spell_targets.shuriken_storm>=2|raid_event.adds.in>60
actions.essences+=/the_unbound_force,if=buff.reckless_force.up|buff.reckless_force_counter.stack<10
actions.essences+=/ripple_in_space
actions.essences+=/worldvein_resonance,if=cooldown.symbols_of_death.remains<5|target.time_to_die<18
actions.essences+=/memory_of_lucid_dreams,if=energy<40&buff.symbols_of_death.up
actions.essences+=/reaping_flames,if=target.health.pct>80|target.health.pct<=20|target.time_to_pct_20>30
]]
	if ConcentratedFlame:Usable() and EnergyTimeToMax() > 1 and not SymbolsOfDeath:Up() and (ConcentratedFlame.dot:Down() or ConcentratedFlame:Charges() > 1.8) then
		return ConcentratedFlame
	end
	if BloodOfTheEnemy:Usable() and (not ShadowBlades:Ready() and SymbolsOfDeath:Ready() or Target.timeToDie <= 10) then
		return UseCooldown(BloodOfTheEnemy)
	end
	if GuardianOfAzeroth:Usable() then
		return UseCooldown(GuardianOfAzeroth)
	end
	if FocusedAzeriteBeam:Usable() and not SymbolsOfDeath:Ready() and SymbolsOfDeath:Down() and Player:EnergyDeficit() >= 30 then
		return UseCooldown(FocusedAzeriteBeam)
	end
	if PurifyingBlast:Usable() then
		return UseCooldown(PurifyingBlast)
	end
	if TheUnboundForce:Usable() and (RecklessForce:Up() or RecklessForce.counter:Stack() < 10) then
		return UseCooldown(TheUnboundForce)
	end
	if RippleInSpace:Usable() then
		return UseCooldown(RippleInSpace)
	end
	if WorldveinResonance:Usable() and (SymbolsOfDeath:Ready(5) or Target.timeToDie < 18) then
		return UseCooldown(WorldveinResonance)
	end
	if MemoryOfLucidDreams:Usable() and Energy() < 40 and (SymbolsOfDeath:Up() or SymbolsOfDeath:Ready(2)) then
		return UseCooldown(MemoryOfLucidDreams)
	end
	if ReapingFlames:Usable() then
		return UseCooldown(ReapingFlames)
	end
end

APL[SPEC.SUBTLETY].finish = function(self)
--[[
actions.finish=pool_resource,for_next=1
# Eviscerate has highest priority with Night's Vengeance up.
actions.finish+=/eviscerate,if=buff.nights_vengeance.up
# Keep up Nightblade if it is about to run out. Do not use NB during Dance, if talented into Dark Shadow.
actions.finish+=/nightblade,if=(!talent.dark_shadow.enabled|!buff.shadow_dance.up)&target.time_to_die-remains>6&remains<tick_time*2
# Multidotting outside Dance on targets that will live for the duration of Nightblade, refresh during pandemic. Multidot as long as 2+ targets do not have Nightblade up with Replicating Shadows (unless you have Night's Vengeance too).
actions.finish+=/nightblade,cycle_targets=1,if=!variable.use_priority_rotation&spell_targets.shuriken_storm>=2&(azerite.nights_vengeance.enabled|!azerite.replicating_shadows.enabled|spell_targets.shuriken_storm-active_dot.nightblade>=2)&!buff.shadow_dance.up&target.time_to_die>=(5+(2*combo_points))&refreshable
# Refresh Nightblade early if it will expire during Symbols. Do that refresh if SoD gets ready in the next 5s.
actions.finish+=/nightblade,if=remains<cooldown.symbols_of_death.remains+10&cooldown.symbols_of_death.remains<=5&target.time_to_die-remains>cooldown.symbols_of_death.remains+5
actions.finish+=/secret_technique
actions.finish+=/eviscerate
]]
	if NightsVengeance.known and Eviscerate:Usable(true) and NightsVengeance:Up() then
		return Pool(Eviscerate)
	end
	if Nightblade:Usable(true) and (
		((not DarkShadow.known or ShadowDance:Down()) and (Target.timeToDie - Nightblade:Remains()) > 6 and Nightblade:Remains() < (Nightblade:TickTime() * 2)) or
		(not Player.use_priority_rotation and Player.enemies >= 2 and (NightsVengeance.known or not ReplicatingShadows.known or (Player.enemies - Nightblade:Ticking()) >= 2) and ShadowDance:Down() and Target.timeToDie >= (5 + (2 * Player:ComboPoints())) and Nightblade:Refreshable()) or
		(Nightblade:Remains() < (SymbolsOfDeath:Cooldown() + 10) and SymbolsOfDeath:Ready(5) and (Target.timeToDie - Nightblade:Remains()) > (SymbolsOfDeath:Cooldown() + 5))
	) then
		return Pool(Nightblade)
	end
	if SecretTechnique:Usable(true) then
		return Pool(SecretTechnique)
	end
	if Eviscerate:Usable(true) then
		return Pool(Eviscerate)
	end
end

APL[SPEC.SUBTLETY].build = function(self)
--[[
actions.build=shuriken_storm,if=spell_targets>=2+(talent.gloomblade.enabled&azerite.perforate.rank>=2&position_back)
actions.build+=/gloomblade
actions.build+=/backstab
]]
	if ShurikenStorm:Usable() and Player.enemies >= ((Gloomblade.known and Perforate:AzeriteRank() >= 2) and 3 or 2) then
		return ShurikenStorm
	end
	if Gloomblade:Usable() then
		return Gloomblade
	end
	if Backstab:Usable() then
		return Backstab
	end
end

APL[SPEC.SUBTLETY].stealthed = function(self)
--[[
# If Stealth/vanish are up, use Shadowstrike to benefit from the passive bonus and Find Weakness, even if we are at max CP (from the precombat MfD).
actions.stealthed=shadowstrike,if=(talent.find_weakness.enabled|spell_targets.shuriken_storm<3)&(buff.stealth.up|buff.vanish.up)
# Finish at 3+ CP without DS / 4+ with DS with Shuriken Tornado buff up to avoid some CP waste situations.
actions.stealthed+=/call_action_list,name=finish,if=buff.shuriken_tornado.up&combo_points.deficit<=2
# Also safe to finish at 4+ CP with exactly 4 targets. (Same as outside stealth.)
actions.stealthed+=/call_action_list,name=finish,if=spell_targets.shuriken_storm=4&combo_points>=4
# Finish at 4+ CP without DS, 5+ with DS, and 6 with DS after Vanish or The First Dance and no Dark Shadow + no Subterfuge
actions.stealthed+=/call_action_list,name=finish,if=combo_points.deficit<=1-(talent.deeper_stratagem.enabled&(buff.vanish.up|azerite.the_first_dance.enabled&!talent.dark_shadow.enabled&!talent.subterfuge.enabled&spell_targets.shuriken_storm<3))
# Use Gloomblade over Shadowstrike and Storm with 2+ Perforate at 2 or less targets.
actions.stealthed+=/gloomblade,if=azerite.perforate.rank>=2&spell_targets.shuriken_storm<=2&position_back
# At 2 targets with Secret Technique keep up Find Weakness by cycling Shadowstrike.
actions.stealthed+=/shadowstrike,cycle_targets=1,if=talent.secret_technique.enabled&talent.find_weakness.enabled&debuff.find_weakness.remains<1&spell_targets.shuriken_storm=2&target.time_to_die-remains>6
# Without Deeper Stratagem and 3 Ranks of Blade in the Shadows it is worth using Shadowstrike on 3 targets.
actions.stealthed+=/shadowstrike,if=!talent.deeper_stratagem.enabled&azerite.blade_in_the_shadows.rank=3&spell_targets.shuriken_storm=3
# For priority rotation, use Shadowstrike over Storm 1) with WM against up to 4 targets, 2) if FW is running off (on any amount of targets), or 3) to maximize SoD extension with Inevitability on 3 targets (4 with BitS).
actions.stealthed+=/shadowstrike,if=variable.use_priority_rotation&(talent.find_weakness.enabled&debuff.find_weakness.remains<1|talent.weaponmaster.enabled&spell_targets.shuriken_storm<=4|azerite.inevitability.enabled&buff.symbols_of_death.up&spell_targets.shuriken_storm<=3+azerite.blade_in_the_shadows.enabled)
actions.stealthed+=/shuriken_storm,if=spell_targets>=3
actions.stealthed+=/shadowstrike
]]
	if Shadowstrike:Usable() and (FindWeakness.known or Enemies() < 3) and (Stealth:Up() or Vanish:Up())  then
		return Shadowstrike
	end
	if (
		(ShurikenTornado.known and ShurikenTornado:Up() and Player:ComboPointsDeficit() <= 2) or
		(Player.enemies == 4 and Player:ComboPoints() >= 4) or
		(Player:ComboPointsDeficit() <= (DeeperStratagem.known and (Vanish:Up() or TheFirstDance.known and not DarkShadow.known and not Subterfuge.known and Player.enemies < 3) and 0 or 1))
	) then
		local apl = self:finish()
		if apl then return apl end
	end
	if Gloomblade:Usable() and Player.enemies <= 2 and Perforate:AzeriteRank() >= 2 then
		return Gloomblade
	end
	if Shadowstrike:Usable() and (
		(SecretTechnique.known and FindWeakness.known and Player.enemies == 2 and FindWeakness:Remains() < 1 and (Target.timeToDie - Shadowstrike:Remains()) > 6) or
		(BladeInTheShadows.known and not DeeperStratagem.known and Player.enemies == 3 and BladeInTheShadows:AzeriteRank() >= 3) or
		(Player.use_priority_rotation and ((FindWeakness.known and FindWeakness:Remains() < 1) or (WeaponMaster.known and Player.enemies <= 4) or (Inevitability.known and SymbolsOfDeath:Up() and Player.enemies <= (BladeInTheShadows.known and 4 or 3))))
	) then
		return Shadowstrike
	end
	if ShurikenStorm:Usable() and Player.enemies >= 3 then
		return ShurikenStorm
	end
	if Shadowstrike:Usable() then
		return Shadowstrike
	end
end

APL.Interrupt = function(self)
	if Kick:Usable() then
		return Kick
	end
end

-- End Action Priority Lists

-- Start UI API

function UI.DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.spark:SetVertexColor(r, g, b)
		glow.innerGlow:SetVertexColor(r, g, b)
		glow.innerGlowOver:SetVertexColor(r, g, b)
		glow.outerGlow:SetVertexColor(r, g, b)
		glow.outerGlowOver:SetVertexColor(r, g, b)
		glow.ants:SetVertexColor(r, g, b)
	end
end

function UI:CreateOverlayGlows()
	local b, i
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			self.glows[#self.glows + 1] = glow
		end
	end
	for i = 1, 12 do
		GenerateGlow(_G['ActionButton' .. i])
		GenerateGlow(_G['MultiBarLeftButton' .. i])
		GenerateGlow(_G['MultiBarRightButton' .. i])
		GenerateGlow(_G['MultiBarBottomLeftButton' .. i])
		GenerateGlow(_G['MultiBarBottomRightButton' .. i])
	end
	for i = 1, 10 do
		GenerateGlow(_G['PetActionButton' .. i])
	end
	if Bartender4 then
		for i = 1, 120 do
			GenerateGlow(_G['BT4Button' .. i])
		end
	end
	if Dominos then
		for i = 1, 60 do
			GenerateGlow(_G['DominosActionButton' .. i])
		end
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['ElvUI_Bar' .. b .. 'Button' .. i])
			end
		end
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['LUIBarBottom' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarLeft' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarRight' .. b .. 'Button' .. i])
			end
		end
	end
	UI:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, icon, i
	for i = 1, #self.glows do
		glow = self.glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Opt.glow.main and Player.main and icon == Player.main.icon) or
			(Opt.glow.cooldown and Player.cd and icon == Player.cd.icon) or
			(Opt.glow.interrupt and Player.interrupt and icon == Player.interrupt.icon) or
			(Opt.glow.extra and Player.extra and icon == Player.extra.icon)
			) then
			if not glow:IsVisible() then
				glow.animIn:Play()
			end
		elseif glow:IsVisible() then
			glow.animIn:Stop()
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	assassinPanel:EnableMouse(Opt.aoe or not Opt.locked)
	assassinPanel.button:SetShown(Opt.aoe)
	if Opt.locked then
		assassinPanel:SetScript('OnDragStart', nil)
		assassinPanel:SetScript('OnDragStop', nil)
		assassinPanel:RegisterForDrag(nil)
		assassinPreviousPanel:EnableMouse(false)
		assassinCooldownPanel:EnableMouse(false)
		assassinInterruptPanel:EnableMouse(false)
		assassinExtraPanel:EnableMouse(false)
	else
		if not Opt.aoe then
			assassinPanel:SetScript('OnDragStart', assassinPanel.StartMoving)
			assassinPanel:SetScript('OnDragStop', assassinPanel.StopMovingOrSizing)
			assassinPanel:RegisterForDrag('LeftButton')
		end
		assassinPreviousPanel:EnableMouse(true)
		assassinCooldownPanel:EnableMouse(true)
		assassinInterruptPanel:EnableMouse(true)
		assassinExtraPanel:EnableMouse(true)
	end
end

function UI:UpdateAlpha()
	assassinPanel:SetAlpha(Opt.alpha)
	assassinPreviousPanel:SetAlpha(Opt.alpha)
	assassinCooldownPanel:SetAlpha(Opt.alpha)
	assassinInterruptPanel:SetAlpha(Opt.alpha)
	assassinExtraPanel:SetAlpha(Opt.alpha)
end

function UI:UpdateScale()
	assassinPanel:SetSize(64 * Opt.scale.main, 64 * Opt.scale.main)
	assassinPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	assassinCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
	assassinInterruptPanel:SetSize(64 * Opt.scale.interrupt, 64 * Opt.scale.interrupt)
	assassinExtraPanel:SetSize(64 * Opt.scale.extra, 64 * Opt.scale.extra)
end

function UI:SnapAllPanels()
	assassinPreviousPanel:ClearAllPoints()
	assassinPreviousPanel:SetPoint('TOPRIGHT', assassinPanel, 'BOTTOMLEFT', -3, 40)
	assassinCooldownPanel:ClearAllPoints()
	assassinCooldownPanel:SetPoint('TOPLEFT', assassinPanel, 'BOTTOMRIGHT', 3, 40)
	assassinInterruptPanel:ClearAllPoints()
	assassinInterruptPanel:SetPoint('BOTTOMLEFT', assassinPanel, 'TOPRIGHT', 3, -21)
	assassinExtraPanel:ClearAllPoints()
	assassinExtraPanel:SetPoint('BOTTOMRIGHT', assassinPanel, 'TOPLEFT', -3, -21)
end

UI.anchor_points = {
	blizzard = { -- Blizzard Personal Resource Display (Default)
		[SPEC.ASSASSINATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		},
		[SPEC.OUTLAW] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		},
		[SPEC.SUBTLETY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.ASSASSINATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 30 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
		[SPEC.OUTLAW] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 30 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
		[SPEC.SUBTLETY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 30 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
	},
}

function UI.OnResourceFrameHide()
	if Opt.snap then
		assassinPanel:ClearAllPoints()
	end
end

function UI.OnResourceFrameShow()
	if Opt.snap then
		local p = UI.anchor.points[Player.spec][Opt.snap]
		assassinPanel:ClearAllPoints()
		assassinPanel:SetPoint(p[1], UI.anchor.frame, p[2], p[3], p[4])
		UI:SnapAllPanels()
	end
end

function UI:HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		self.anchor.points = self.anchor_points.kui
		self.anchor.frame = KuiNameplatesPlayerAnchor
	else
		self.anchor.points = self.anchor_points.blizzard
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateBar()
	end
	if self.anchor.frame then
		self.anchor.frame:HookScript('OnHide', self.OnResourceFrameHide)
		self.anchor.frame:HookScript('OnShow', self.OnResourceFrameShow)
	end
end

function UI:ShouldHide()
	return (Player.spec == SPEC.NONE or
		(Player.spec == SPEC.ASSASSINATION and Opt.hide.assassination) or
		(Player.spec == SPEC.OUTLAW and Opt.hide.outlaw) or
		(Player.spec == SPEC.SUBTLETY and Opt.hide.subtlety))
end

function UI:Disappear()
	assassinPanel:Hide()
	assassinPanel.icon:Hide()
	assassinPanel.border:Hide()
	assassinCooldownPanel:Hide()
	assassinInterruptPanel:Hide()
	assassinExtraPanel:Hide()
	Player.main = nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	UI:UpdateGlows()
end

function UI:UpdateDisplay()
	timer.display = 0
	local dim, text_center
	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
	end
	if Player.pool_energy then
		local deficit = Player.pool_energy - UnitPower('player', 3)
		if deficit > 0 then
			text_center = format('POOL %d', deficit)
			dim = Opt.dimmer
		end
	end
	assassinPanel.dimmer:SetShown(dim)
	assassinPanel.text.center:SetText(text_center)
	--assassinPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
end

function UI:UpdateCombat()
	timer.combat = 0
	local _, start, duration, remains, spellId
	Player.ctime = GetTime()
	Player.time = Player.ctime - Player.time_diff
	Player.main =  nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	Player.pool_energy = nil
	start, duration = GetSpellCooldown(61304)
	Player.gcd_remains = start > 0 and duration - (Player.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	Player.ability_casting = abilities.bySpellId[spellId]
	Player.execute_remains = max(remains and (remains / 1000 - Player.ctime) or 0, Player.gcd_remains)
	Player.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	Player.energy_regen = GetPowerRegen()
	Player.energy = UnitPower('player', 3) + (Player.energy_regen * Player.execute_remains)
	Player.energy = min(max(Player.energy, 0), Player.energy_max)
	Player.combo_points = UnitPower('player', 4)
	Player.health = UnitHealth('player')
	Player.health_max = UnitHealthMax('player')
	Player.stealthed = Stealth:Up() or Vanish:Up() or (ShadowDance.known and ShadowDance:Up())

	trackAuras:Purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end

	Player.main = APL[Player.spec]:main()
	if Player.main then
		assassinPanel.icon:SetTexture(Player.main.icon)
	end
	if Player.cd then
		assassinCooldownPanel.icon:SetTexture(Player.cd.icon)
	end
	if Player.extra then
		assassinExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local ends, notInterruptible
		_, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			assassinInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			assassinInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		assassinInterruptPanel.icon:SetShown(Player.interrupt)
		assassinInterruptPanel.border:SetShown(Player.interrupt)
		assassinInterruptPanel:SetShown(start and not notInterruptible)
	end
	assassinPanel.icon:SetShown(Player.main)
	assassinPanel.border:SetShown(Player.main)
	assassinCooldownPanel:SetShown(Player.cd)
	assassinExtraPanel:SetShown(Player.extra)

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI API

-- Start Event Handling

function events:ADDON_LOADED(name)
	if name == 'Assassin' then
		Opt = Assassin
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. name .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Assassin1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 110 then
			print('[|cFFFFD000Warning|r] ' .. name .. ' is not designed for players under level 110, and almost certainly will not operate properly!')
		end
		InitOpts()
		Azerite:Init()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName, _, missType = CombatLogGetCurrentEventInfo()
	Player.time = timeStamp
	Player.ctime = GetTime()
	Player.time_diff = Player.ctime - Player.time

	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:Remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:Remove(dstGUID)
		end
	end
	if eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED' then
		if dstGUID == Player.guid then
			Player.last_swing_taken = Player.time
		end
		if Opt.auto_aoe then
			if dstGUID == Player.guid then
				autoAoe:Add(srcGUID, true)
			elseif srcGUID == Player.guid and not (missType == 'EVADE' or missType == 'IMMUNE') then
				autoAoe:Add(dstGUID, true)
			end
		end
	end

	if srcGUID ~= Player.guid then
		return
	end

	local ability = spellId and abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, spellName, spellId))
		return
	end

	if not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_AURA_REMOVED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_PERIODIC_DAMAGE' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end

	UI:UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		if srcGUID == Player.guid or ability.player_triggered then
			Player.last_ability = ability
			if ability.triggers_gcd then
				Player.previous_gcd[10] = nil
				table.insert(Player.previous_gcd, 1, ability)
			end
			if ability.travel_start then
				ability.travel_start[dstGUID] = Player.time
			end
			if Opt.previous and assassinPanel:IsVisible() then
				assassinPreviousPanel.ability = ability
				assassinPreviousPanel.border:SetTexture('Interface\\AddOns\\Assassin\\border.blp')
				assassinPreviousPanel.icon:SetTexture(ability.icon)
				assassinPreviousPanel:Show()
			end
		end
		return
	end

	if dstGUID == Player.guid then
		return -- ignore buffs beyond here
	end
	if ability.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if Opt.auto_aoe then
		if eventType == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (eventType == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and eventType == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		if ability.travel_start and ability.travel_start[dstGUID] then
			ability.travel_start[dstGUID] = nil
		end
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and assassinPanel:IsVisible() and ability == assassinPreviousPanel.ability then
			assassinPreviousPanel.border:SetTexture('Interface\\AddOns\\Assassin\\misseffect.blp')
		end
	end
end

function events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.last_swing_taken = 0
	Target.estimated_range = 30
	Player.previous_gcd = {}
	if Player.last_ability then
		Player.last_ability = nil
		assassinPreviousPanel:Hide()
	end
	local _, ability, guid
	for _, ability in next, abilities.velocity do
		for guid in next, ability.travel_start do
			ability.travel_start[guid] = nil
		end
	end
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability.auto_aoe.start_time = nil
			for guid in next, ability.auto_aoe.targets do
				ability.auto_aoe.targets[guid] = nil
			end
		end
		autoAoe:Clear()
		autoAoe:Update()
	end
	Player.opener_done = nil
end

function events:PLAYER_EQUIPMENT_CHANGED()
	local _, i, equipType, hasCooldown
	Trinket1.itemId = GetInventoryItemID('player', 13) or 0
	Trinket2.itemId = GetInventoryItemID('player', 14) or 0
	for _, i in next, Trinket do -- use custom APL lines for these trinkets
		if Trinket1.itemId == i.itemId then
			Trinket1.itemId = 0
		end
		if Trinket2.itemId == i.itemId then
			Trinket2.itemId = 0
		end
	end
	for i = 1, #inventoryItems do
		inventoryItems[i].name, _, _, _, _, _, _, _, equipType, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId or 0)
		inventoryItems[i].can_use = inventoryItems[i].name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, inventoryItems[i].equip_slot = Player:Equipped(inventoryItems[i].itemId)
			if inventoryItems[i].equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', inventoryItems[i].equip_slot)
			end
			inventoryItems[i].can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[inventoryItems[i].itemId] then
			inventoryItems[i].can_use = false
		end
	end
	Azerite:Update()
	Player:UpdateAbilities()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	assassinPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Target:Update()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, start, duration, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
		end
		assassinPanel.swipe:SetCooldown(start, duration)
	end
end

function events:UNIT_POWER_UPDATE(srcName, powerType)
	if srcName == 'player' and powerType == 'COMBO_POINTS' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_START(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateAbilities()
end

function events:AZERITE_ESSENCE_UPDATE()
	Azerite:Update()
	Player:UpdateAbilities()
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:PLAYER_ENTERING_WORLD()
	if #UI.glows == 0 then
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	local _
	_, Player.instance = IsInInstance()
	Player.guid = UnitGUID('player')
	events:PLAYER_SPECIALIZATION_CHANGED('player')
end

assassinPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			Player:ToggleTargetMode()
		elseif button == 'RightButton' then
			Player:ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			Player:SetTargetMode(1)
		end
	end
end)

assassinPanel:SetScript('OnUpdate', function(self, elapsed)
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

assassinPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	assassinPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local ChatFrame_OnHyperlinkShow_Original = ChatFrame_OnHyperlinkShow
function ChatFrame_OnHyperlinkShow(chatFrame, link, ...)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		return BattleTagInviteFrame_Show(linkData)
	end
	return ChatFrame_OnHyperlinkShow_Original(chatFrame, link, ...)
end

local function Status(desc, opt, ...)
	local opt_view
	if type(opt) == 'string' then
		if opt:sub(1, 2) == '|c' then
			opt_view = opt
		else
			opt_view = '|cFFFFD000' .. opt .. '|r'
		end
	elseif type(opt) == 'number' then
		opt_view = '|cFFFFD000' .. opt .. '|r'
	else
		opt_view = opt and '|cFF00C000On|r' or '|cFFC00000Off|r'
	end
	print('Assassin -', desc .. ':', opt_view, ...)
end

function SlashCmdList.Assassin(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
			else
				Opt.snap = false
				assassinPanel:ClearAllPoints()
			end
			UI.OnResourceFrameShow()
		end
		return Status('Snap to the Personal Resource Display frame', Opt.snap)
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Previous ability icon scale', Opt.scale.previous, 'times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				UI:UpdateScale()
			end
			return Status('Main ability icon scale', Opt.scale.main, 'times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Cooldown ability icon scale', Opt.scale.cooldown, 'times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Interrupt ability icon scale', Opt.scale.interrupt, 'times')
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Extra cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UI:UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UI:UpdateAlpha()
		end
		return Status('Icon transparency', Opt.alpha * 100 .. '%')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.2
		end
		return Status('Calculation frequency (max time to wait between each update): Every', Opt.frequency, 'seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (main icon)', Opt.glow.main)
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (cooldown icon)', Opt.glow.cooldown)
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (interrupt icon)', Opt.glow.interrupt)
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (extra cooldown icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			Target:Update()
		end
		return Status('Previous ability icon', Opt.previous)
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			Target:Update()
		end
		return Status('Show the Assassin UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use Assassin for cooldown management', Opt.cooldown)
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
		end
		return Status('Spell casting swipe animation', Opt.spell_swipe)
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
		end
		return Status('Dim main ability icon when you don\'t have enough resources to use it', Opt.dimmer)
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return Status('Red border around previous ability when it fails to hit', Opt.miss_effect)
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			Player:SetTargetMode(1)
			UI:UpdateDraggable()
		end
		return Status('Allow clicking main ability icon to toggle amount of targets (disables moving)', Opt.aoe)
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return Status('Only use cooldowns on bosses', Opt.boss_only)
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'a') then
				Opt.hide.assassination = not Opt.hide.assassination
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Assassination specialization', not Opt.hide.assassination)
			end
			if startsWith(msg[2], 'o') then
				Opt.hide.outlaw = not Opt.hide.outlaw
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Outlaw specialization', not Opt.hide.outlaw)
			end
			if startsWith(msg[2], 's') then
				Opt.hide.subtlety = not Opt.hide.subtlety
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Subtlety specialization', not Opt.hide.subtlety)
			end
		end
		return Status('Possible hidespec options', '|cFFFFD000assassination|r/|cFFFFD000outlaw|r/|cFFFFD000subtlety|r')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return Status('Show an icon for interruptable spells', Opt.interrupt)
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return Status('Automatically change target mode on AoE spells', Opt.auto_aoe)
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return Status('Length of time target exists in auto AoE after being hit', Opt.auto_aoe_ttl, 'seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return Status('Show flasks and battle potions in cooldown UI', Opt.pot)
	end
	if startsWith(msg[1], 'tri') then
		if msg[2] then
			Opt.trinket = msg[2] == 'on'
		end
		return Status('Show on-use trinkets in cooldown UI', Opt.trinket)
	end
	if startsWith(msg[1], 'poi') then
		if msg[2] then
			Opt.poisons = msg[2] == 'on'
		end
		return Status('Show a reminder for poisons (5 minutes outside combat)', Opt.poisons)
	end
	if startsWith(msg[1], 'pri') then
		if msg[2] then
			Opt.priority_rotation = msg[2] == 'on'
		end
		return Status('Use "priority rotation" mode (off by default)', Opt.priority_rotation)
	end
	if msg[1] == 'reset' then
		assassinPanel:ClearAllPoints()
		assassinPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print('Assassin (version: |cFFFFD000' .. GetAddOnMetadata('Assassin', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the Assassin UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the Assassin UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the Assassin UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the Assassin UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the Assassin UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use Assassin for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000assassination|r/|cFFFFD000outlaw|r/|cFFFFD000subtlety|r - toggle disabling Assassin for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'poisons |cFF00C000on|r/|cFFC00000off|r - show a reminder for poisons (5 minutes outside combat)',
		'priority |cFF00C000on|r/|cFFC00000off|r - use "priority rotation" mode (off by default)',
		'|cFFFFD000reset|r - reset the location of the Assassin UI to default',
	} do
		print('  ' .. SLASH_Assassin1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
