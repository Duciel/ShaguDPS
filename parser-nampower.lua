-- [OctoWoW] nampower data source for ShaguDPS.
--
-- When nampower is loaded, damage and heals come from its structured combat
-- events (GUIDs, spell IDs, amounts) instead of matching ~40 localized text
-- patterns against every combat-log chat line. The chat parser from
-- parser-vanilla.lua stays as the fallback when nampower is missing.
-- Set ShaguDPS_DisableNative = true before login to force the old parser.

local parser = ShaguDPS.parser
local config = ShaguDPS.config

if ShaguDPS_DisableNative then return end
if not (GetNampowerVersion or GetUnitGUID) then return end

-- make sure the optional event families are switched on
for _, cvar in pairs({ "NP_EnableAutoAttackEvents", "NP_EnableSpellHealEvents" }) do
  local ok, value = pcall(GetCVar, cvar)
  if ok and value == "0" then pcall(SetCVar, cvar, "1") end
end

-- drop every combat-log chat event the text parser registered
parser:UnregisterAllEvents()

local events = {
  "SPELL_DAMAGE_EVENT_SELF", "SPELL_DAMAGE_EVENT_OTHER",
  "AUTO_ATTACK_SELF", "AUTO_ATTACK_OTHER",
  "DAMAGE_SHIELD_SELF", "DAMAGE_SHIELD_OTHER",
  "SPELL_HEAL_BY_SELF", "SPELL_HEAL_BY_OTHER",
}
for _, event in pairs(events) do
  parser:RegisterEvent(event)
end

local schools = { [0] = "physical", [1] = "holy", [2] = "fire", [3] = "nature", [4] = "frost", [5] = "shadow", [6] = "arcane" }
local autohit = "Auto Hit"

-- spell id -> name
local spellNames = {}
local function SpellName(id)
  local name = spellNames[id]
  if name == nil then
    if GetSpellInfo then name = GetSpellInfo(id) end
    if not name and SpellInfo then name = SpellInfo(id) end
    name = name or UNKNOWN
    spellNames[id] = name
  end
  return name
end

-- guid -> display name, in the same format the SuperWoW combat log uses:
-- "Name" for players, "Pet (Owner)" for player pets, so ShaguDPS' existing pet
-- detection keeps working. Returns nil for units ShaguDPS would not track,
-- before any of its (expensive) name scans run.
local function SourceName(guid)
  if not guid then return nil end
  if UnitIsPlayer(guid) then return UnitName(guid) end

  local owner = guid .. "owner"
  if UnitExists(owner) and UnitIsPlayer(owner) then
    local name, ownerName = UnitName(guid), UnitName(owner)
    if name and ownerName then return name .. " (" .. ownerName .. ")" end
    return name
  end

  if config.track_all_units == 1 then
    return UnitName(guid)
  end
end

local function TargetName(guid)
  return guid and UnitName(guid) or UNKNOWN
end

local handlers = {}

handlers.SPELL_DAMAGE_EVENT_SELF = function(targetGuid, casterGuid, spellId, amount, mitigation, hitInfo, school)
  if not amount or amount <= 0 then return end
  local source = SourceName(casterGuid)
  if not source then return end
  parser:AddData(source, SpellName(spellId), TargetName(targetGuid), amount, schools[school] or "physical", "damage")
end
handlers.SPELL_DAMAGE_EVENT_OTHER = handlers.SPELL_DAMAGE_EVENT_SELF

handlers.AUTO_ATTACK_SELF = function(attackerGuid, targetGuid, totalDamage)
  if not totalDamage or totalDamage <= 0 then return end
  local source = SourceName(attackerGuid)
  if not source then return end
  parser:AddData(source, autohit, TargetName(targetGuid), totalDamage, "physical", "damage")
end
handlers.AUTO_ATTACK_OTHER = handlers.AUTO_ATTACK_SELF

handlers.DAMAGE_SHIELD_SELF = function(unitGuid, targetGuid, damage, school)
  if not damage or damage <= 0 then return end
  local source = SourceName(unitGuid)
  if not source then return end
  local schoolName = schools[school] or "physical"
  parser:AddData(source, "Reflect (" .. schoolName .. ")", TargetName(targetGuid), damage, schoolName, "damage")
end
handlers.DAMAGE_SHIELD_OTHER = handlers.DAMAGE_SHIELD_SELF

handlers.SPELL_HEAL_BY_SELF = function(targetGuid, casterGuid, spellId, amount)
  if not amount or amount <= 0 then return end
  local source = SourceName(casterGuid)
  if not source then return end
  parser:AddData(source, SpellName(spellId), TargetName(targetGuid), amount, "physical", "heal")
end
handlers.SPELL_HEAL_BY_OTHER = handlers.SPELL_HEAL_BY_SELF

parser:SetScript("OnEvent", function()
  local handler = handlers[event]
  if handler then handler(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8) end
end)
