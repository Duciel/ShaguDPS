-- Native data sources: structured combat events from client mods instead of
-- matching localized text patterns against every combat log chat line.
--
--   ClassicAPI  COMBAT_LOG_EVENT_UNFILTERED with GUIDs and unit flags
--   Nampower    SPELL_DAMAGE_EVENT_*, AUTO_ATTACK_*, SPELL_HEAL_BY_* events
--               (needs GUID unit tokens from SuperWoW or ClassicAPI)
--
-- The chat parser in parser-vanilla.lua stays as the fallback. The source in
-- use is picked by parser:SelectSource() once the settings are loaded.

local parser = ShaguDPS.parser
local config = ShaguDPS.config

local autohit = "Auto Hit"

-- school names as the chat combat log prints them, by Nampower's school index
local school_index = {
  [0] = "Physical", [1] = "Holy", [2] = "Fire", [3] = "Nature",
  [4] = "Frost", [5] = "Shadow", [6] = "Arcane",
}

-- school names by the school bit mask the combat log events use
local school_mask = {
  [1] = "Physical", [2] = "Holy", [4] = "Fire", [8] = "Nature",
  [16] = "Frost", [32] = "Shadow", [64] = "Arcane",
}

-- "Reflect (Fire)" etc, built once
local reflect = {}
for _, school in pairs(school_index) do reflect[school] = "Reflect (" .. school .. ")" end

-- Lua 5.0 has no bit operators: test a single bit by arithmetic
local function hasbit(value, bit)
  return math.mod(math.floor(value / bit), 2) == 1
end

-------------------------------------------------------------------------------
-- unit helpers
-------------------------------------------------------------------------------

-- GUID of a unit token, from whichever client mod provides one
local function GUIDOf(unit)
  if UnitGUID then return UnitGUID(unit) end
  if GetUnitGUID then return GetUnitGUID(unit) end
  local _, guid = UnitExists(unit) -- SuperWoW
  return guid
end

-- true when "0x..." GUID strings work as unit tokens (SuperWoW or ClassicAPI)
local guid_tokens
local function GUIDTokensWork()
  if guid_tokens == nil then
    local guid = GUIDOf("player")
    local name = UnitName("player")
    guid_tokens = (type(guid) == "string" and name and UnitName(guid) == name) and true or false
  end
  return guid_tokens
end

-- name of the player owning a pet, guardian or totem
local function OwnerName(guid)
  if UnitOwnerGUID then
    local owner = UnitOwnerGUID(guid)
    if owner and UnitIsPlayer(owner) then return UnitName(owner) end
    return nil
  end

  -- SuperWoW: "<guid>owner" is the owner's unit token
  local owner = guid .. "owner"
  if UnitExists(owner) and UnitIsPlayer(owner) then return UnitName(owner) end
end

-- Names of group members and their pets by GUID. Pets use the "Pet (Owner)"
-- format of the SuperWoW combat log, so the core's pet detection and merging
-- work the same for every source. Units that aren't tracked are cached as
-- false, so the expensive name scans of the core run once per unit and not on
-- every hit. Entries expire so group changes are picked up.
local cache, cache_size, cache_trackall = {}, 0, nil

local function CacheGet(guid)
  -- toggling "track all units" changes what is tracked
  if cache_trackall ~= config.track_all_units then
    cache, cache_size, cache_trackall = {}, 0, config.track_all_units
  end

  local entry = cache[guid]
  if entry and entry.expire > GetTime() then return true, entry.name end
end

local function CacheSet(guid, name, lifetime)
  if cache_size > 2000 then cache, cache_size = {}, 0 end
  if not cache[guid] then cache_size = cache_size + 1 end
  cache[guid] = cache[guid] or {}
  cache[guid].name = name
  cache[guid].expire = GetTime() + lifetime
  return name
end

-- is this a player of the group (or anyone when tracking all units)?
local function Tracked(name)
  if not name or name == UNKNOWNOBJECT or name == UNKNOWN then return nil end
  if config.track_all_units == 1 then return true end
  return parser:ScanName(name) == "PLAYER"
end

-- label of a pet/guardian: "Pet (Owner)" or nil when the owner isn't tracked
local function PetLabel(guid, name, owner)
  name = name or UnitName(guid)
  owner = owner or OwnerName(guid)
  if name and owner and Tracked(owner) then
    return name .. " (" .. owner .. ")"
  end
end

-------------------------------------------------------------------------------
-- ClassicAPI: COMBAT_LOG_EVENT_UNFILTERED
-------------------------------------------------------------------------------

-- COMBATLOG_OBJECT_* bits: affiliation 1 mine, 2 party, 4 raid; unit types below
local TYPE_PLAYER, TYPE_PET, TYPE_GUARDIAN = 1024, 4096, 8192

local function CLEUSource(guid, name, flags)
  if not guid or not name or not flags or flags < 0 then return nil end

  local found, label = CacheGet(guid)
  if found then return label end

  local grouped = hasbit(flags, 1) or hasbit(flags, 2) or hasbit(flags, 4)

  if hasbit(flags, TYPE_PLAYER) then
    if grouped and Tracked(name) then
      return CacheSet(guid, name, 60)
    elseif config.track_all_units == 1 then
      return CacheSet(guid, name, 60)
    end
    return CacheSet(guid, false, 10)
  end

  if hasbit(flags, TYPE_PET) or hasbit(flags, TYPE_GUARDIAN) then
    local owner = hasbit(flags, 1) and UnitName("player") or nil
    local label = PetLabel(guid, name, owner)
    if label then return CacheSet(guid, label, 30) end
  end

  if config.track_all_units == 1 and name ~= UNKNOWNOBJECT then
    return CacheSet(guid, name, 30)
  end

  return CacheSet(guid, false, 10)
end

-- arg12 onward depend on the subevent (see the ClassicAPI documentation)
local cleu = {}

cleu.SWING_DAMAGE = function(source, target)
  -- amount, overkill, school, ...
  return parser:AddData(source, autohit, target, arg12, "Physical", "damage")
end

cleu.SPELL_DAMAGE = function(source, target)
  -- spellId, spellName, spellSchool, amount, ...
  return parser:AddData(source, arg13 or UNKNOWN, target, arg15, school_mask[arg14] or "Physical", "damage")
end
cleu.SPELL_PERIODIC_DAMAGE = cleu.SPELL_DAMAGE
cleu.RANGE_DAMAGE = cleu.SPELL_DAMAGE

cleu.DAMAGE_SHIELD = function(source, target)
  -- the spell isn't named: name it like the chat parser does
  local school = school_mask[arg14] or "Physical"
  return parser:AddData(source, reflect[school], target, arg15, school, "damage")
end

cleu.SPELL_HEAL = function(source, target)
  -- spellId, spellName, spellSchool, amount, overhealing (always 0), ...
  return parser:AddData(source, arg13 or UNKNOWN, target, arg15, "Physical", "heal")
end
cleu.SPELL_PERIODIC_HEAL = cleu.SPELL_HEAL

local function CLEUEvent()
  local handler = cleu[arg2]
  if not handler or arg3 then return end

  local source = CLEUSource(arg4, arg5, arg6)
  if not source then return end

  handler(source, arg9 or UNKNOWN)
end

parser:RegisterSource("classicapi", {
  available = function()
    return CombatLogGetCurrentEventInfo and UnitOwnerGUID and true or nil
  end,
  why = function()
    -- ClassicAPI builds before the combat log was added have the rest of the API
    if UnitOwnerGUID or C_PlayerInfo then return "this ClassicAPI build has no combat log yet" end
    return "ClassicAPI isn't loaded"
  end,
  enable = function()
    parser:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    parser:SetScript("OnEvent", CLEUEvent)
  end,
})

-------------------------------------------------------------------------------
-- Nampower: damage, auto attack and heal events
-------------------------------------------------------------------------------

local function NPSource(guid)
  if not guid then return nil end

  local found, label = CacheGet(guid)
  if found then return label end

  if UnitIsPlayer(guid) then
    local name = UnitName(guid)
    if Tracked(name) then return CacheSet(guid, name, 60) end
    return CacheSet(guid, false, 10)
  end

  local label = PetLabel(guid)
  if label then return CacheSet(guid, label, 30) end

  if config.track_all_units == 1 then
    local name = UnitName(guid)
    if name then return CacheSet(guid, name, 30) end
  end

  return CacheSet(guid, false, 10)
end

-- target names: heals need them to find the target's health
local function NPTarget(guid)
  return guid and UnitName(guid) or UNKNOWN
end

-- spell id -> name
local spell_names = {}
local function SpellName(id)
  local name = spell_names[id]
  if not name then
    if GetSpellInfo then name = GetSpellInfo(id) end
    if not name and SpellInfo then name = SpellInfo(id) end
    name = name or UNKNOWN
    spell_names[id] = name
  end
  return name
end

local nampower = {}

nampower.SPELL_DAMAGE_EVENT_SELF = function()
  -- targetGuid, casterGuid, spellId, amount, mitigationStr, hitInfo, spellSchool
  if not arg4 or arg4 <= 0 then return end
  local source = NPSource(arg2)
  if not source then return end
  if arg1 == arg2 then return end -- damage to self

  -- the target's name is only used to skip self damage: don't look it up
  parser:AddData(source, SpellName(arg3), arg1, arg4, school_index[arg7] or "Physical", "damage")
end
nampower.SPELL_DAMAGE_EVENT_OTHER = nampower.SPELL_DAMAGE_EVENT_SELF

nampower.AUTO_ATTACK_SELF = function()
  -- attackerGuid, targetGuid, totalDamage, ...
  if not arg3 or arg3 <= 0 then return end
  local source = NPSource(arg1)
  if not source then return end
  if arg1 == arg2 then return end
  parser:AddData(source, autohit, arg2, arg3, "Physical", "damage")
end
nampower.AUTO_ATTACK_OTHER = nampower.AUTO_ATTACK_SELF

nampower.DAMAGE_SHIELD_SELF = function()
  -- unitGuid, targetGuid, damage, school
  if not arg3 or arg3 <= 0 then return end
  local source = NPSource(arg1)
  if not source then return end
  local school = school_index[arg4] or "Physical"
  parser:AddData(source, reflect[school], arg2, arg3, school, "damage")
end
nampower.DAMAGE_SHIELD_OTHER = nampower.DAMAGE_SHIELD_SELF

nampower.SPELL_HEAL_BY_SELF = function()
  -- targetGuid, casterGuid, spellId, amount, critical, periodic
  if not arg4 or arg4 <= 0 then return end
  local source = NPSource(arg2)
  if not source then return end
  parser:AddData(source, SpellName(arg3), NPTarget(arg1), arg4, "Physical", "heal")
end
nampower.SPELL_HEAL_BY_OTHER = nampower.SPELL_HEAL_BY_SELF

local function NampowerEvent()
  local handler = nampower[event]
  if handler then handler() end
end

parser:RegisterSource("nampower", {
  available = function()
    return GetNampowerVersion and GUIDTokensWork() and true or nil
  end,
  why = function()
    if not GetNampowerVersion then return "Nampower isn't loaded" end
    return "needs SuperWoW or ClassicAPI for GUID unit tokens"
  end,
  enable = function()
    -- auto attack and heal events are off by default in Nampower
    for _, cvar in pairs({ "NP_EnableAutoAttackEvents", "NP_EnableSpellHealEvents" }) do
      local ok, value = pcall(GetCVar, cvar)
      if ok and value == "0" then pcall(SetCVar, cvar, "1") end
    end

    for event in pairs(nampower) do
      parser:RegisterEvent(event)
    end
    parser:SetScript("OnEvent", NampowerEvent)
  end,
})
