-- load public variables into local
local parser = ShaguDPS.parser

local data = ShaguDPS.data
local config = ShaguDPS.config
local round = ShaguDPS.round

-- populate all valid player units
local validUnits = { ["player"] = true }
for i=1,4 do validUnits["party" .. i] = true end
for i=1,40 do validUnits["raid" .. i] = true end

-- populate all valid player pets
local validPets = { ["pet"] = true }
for i=1,4 do validPets["partypet" .. i] = true end
for i=1,40 do validPets["raidpet" .. i] = true end

-- find unitstr by name
local unit_cache = {}
local function UnitByName(name)
  -- skip all scans if cache is still valid
  if unit_cache[name] and UnitName(unit_cache[name]) == name then
    return unit_cache[name]
  end

  -- scan players for current name
  for unit in pairs(validUnits) do
    if UnitName(unit) == name then
      unit_cache[name] = unit
      return unit
    end
  end

  -- scan pets for current name
  for unit in pairs(validPets) do
    if UnitName(unit) == name then
      unit_cache[name] = unit
      return unit
    end
  end
end

-- trim leading and trailing spaces; names repeat on every hit, so remember
-- the results instead of building new strings each time
local trim_cache, trim_count = {}, 0
local function trim(str)
  local clean = trim_cache[str]
  if not clean then
    clean = gsub(str, "^%s*(.-)%s*$", "%1")
    if trim_count > 1000 then trim_cache, trim_count = {}, 0 end
    trim_cache[str] = clean
    trim_count = trim_count + 1
  end
  return clean
end

-- "Wolf (Hunter)" from the GUID-based sources is shown as "Pet: Wolf"
local pet_actions = {}
local function PetAction(source)
  local action = pet_actions[source]
  if not action then
    action = "Pet: " .. gsub(source, "%s%(.-%)$", "")
    pet_actions[source] = action
  end
  return action
end

local function combat()
  -- check if in combat
  if UnitAffectingCombat("player") or UnitAffectingCombat("pet") then
    return true
  end

  local raid = GetNumRaidMembers()
  local group = GetNumPartyMembers()

  if raid >= 1 then
    for i = 1, raid do
      -- check if any raid member is infight
      if UnitAffectingCombat("raid"..i) or UnitAffectingCombat("raidpet"..i) then return true end
    end
  else
    for i = 1, group do
      -- check if any group member is infight
      if UnitAffectingCombat("party"..i) or UnitAffectingCombat("partypet"..i) then return true end
    end
  end

  return nil
end

local start_next_segment = nil

-- fight timer: the time a fight lasted, shared by everyone in it. Used for the
-- "Fight Duration" time mode instead of each unit's own active time.
local fight = { active = nil, start = 0, last = 0, current = 0, total = 0 }
parser.fight = fight

local function FightStart(now)
  fight.active = true
  fight.start = now
  fight.last = now
  fight.current = 0
  if parser.OnFightStart then parser.OnFightStart() end
end

local function FightStop(now)
  if not fight.active then return end
  local duration = math.max(0, now - fight.start)
  fight.active = nil
  fight.current = duration
  fight.total = fight.total + duration
  if parser.OnFightEnd then parser.OnFightEnd(duration) end
end

-- duration of a segment (0: overall, 1: current) in seconds, never below 1
parser.GetFightTime = function(self, segment)
  local running = fight.active and (GetTime() - fight.start) or 0
  local time
  if segment == 0 then
    time = fight.total + running
  else
    time = fight.active and running or fight.current
  end
  return math.max(1, time)
end

parser.ResetFight = function(self, overall)
  fight.active = nil
  fight.current = 0
  if overall then fight.total = 0 end
end

parser.combat = CreateFrame("Frame", "ShaguDPSCombatState", UIParent)
parser.combat:RegisterEvent("PLAYER_REGEN_DISABLED")
parser.combat:RegisterEvent("PLAYER_REGEN_ENABLED")

-- scan and trigger combat state changes
parser.combat.UpdateState = function(self)
  local state = combat() == true and "COMBAT" or "NO_COMBAT"
  if not self.oldstate or self.oldstate ~= state then
    self.oldstate = state

    if state == "NO_COMBAT" then
      start_next_segment = true
      FightStop(GetTime())
    end
  elseif state == "NO_COMBAT" and fight.active and fight.last + 5 < GetTime() then
    -- data that came in while nobody was in combat (a heal or a dot after the
    -- fight): close that short segment at its last event
    FightStop(fight.last)
  end
end

-- check when player leaves/enters combat
parser.combat:SetScript("OnEvent", function()
  this:UpdateState()
end)

-- check each second
parser.combat:SetScript("OnUpdate", function()
  if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + 1 end
  this:UpdateState()

  -- keep "fight duration" windows ticking while a fight runs
  if fight.active and config.time_mode == 1 then
    for id, callback in pairs(parser.callbacks.refresh) do
      callback()
    end
  end
end)

parser.ScanName = function(self, name)
  -- ignore invalid messages
  if not name then return end

  -- check if name matches a real player
  for unit, _ in pairs(validUnits) do
    if UnitExists(unit) and UnitName(unit) == name then
      if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        data["classes"][name] = class
        return "PLAYER"
      end
    end
  end

  -- detect SuperWoW pet owner
  local match, _, owner = string.find(name, "%((.*)%)", 1)
  if match and owner then
    if parser:ScanName(owner) == "PLAYER" then
      data["classes"][name] = owner
      return "PET"
    end
  end

  -- check if name matches a player pet
  for unit, _ in pairs(validPets) do
    if UnitExists(unit) and UnitName(unit) == name then
      -- parse and set pet owners
      if strsub(unit,0,3) == "pet" then
        data["classes"][name] = UnitName("player")
      elseif strsub(unit,0,8) == "partypet" then
        data["classes"][name] = UnitName("party" .. strsub(unit,9))
      elseif strsub(unit,0,7) == "raidpet" then
        data["classes"][name] = UnitName("raid" .. strsub(unit,8))
      end

      return "PET"
    end
  end

  -- assign class other if tracking of all units is set
  if config.track_all_units == 1 then
    data["classes"][name] = data["classes"][name] or "__other__"
    return "OTHER"
  else
    return nil
  end
end

parser.AddData = function(self, source, action, target, value, school, datatype)
  -- abort on invalid input
  if type(source) ~= "string" then return end
  if not tonumber(value) then return end

  -- trim leading and trailing spaces
  source = trim(source)

  -- prevent self-damage from being tracked
  if datatype == "damage" and source == target then
    return
  end

  -- clear "current" on fight start
  if start_next_segment and data["classes"][source] and data["classes"][source] ~= "__other__" then
    data["damage"][1] = {}
    data["heal"][1] = {}

    start_next_segment = nil
    FightStart(GetTime())
  end

  -- calculate effective value (heal)
  local effective = 0
  if datatype == "heal" then
    local unitstr = UnitByName(target)

    if unitstr then
      -- calculate the effective healing of the current data
      effective = math.min(UnitHealthMax(unitstr) - UnitHealth(unitstr), value)
    end
  end

  -- write both (overall and current segment)
  for segment = 0, 1 do
    local entry = data[datatype][segment]

    -- detect source and write initial table
    if not entry[source] then
      local type = parser:ScanName(source)
      if type == "PET" then
        -- create owner table if not yet existing
        local owner = data["classes"][source]
        if not entry[owner] and parser:ScanName(owner) then
          entry[owner] = { ["_sum"] = 0, ["_ctime"] = 1 }
        end
      elseif not type then
        -- invalid or disabled unit type
        break
      end

      -- create base damage table
      entry[source] = { ["_sum"] = 0, ["_ctime"] = 1 }
    end

    -- write pet damage into owners data if enabled
    local action, source = action, source
    if config.merge_pets == 1 and                 -- merge pets?
      data["classes"][source] ~= "__other__" and  -- valid unit?
      entry[data["classes"][source]]              -- has owner?
    then
      -- remove pet data
      entry[source] = nil

      action = PetAction(source)
      source = data["classes"][source]

      -- write data into owner
      if not entry[source] then
        entry[source] = { ["_sum"] = 0, ["_ctime"] = 1 }
      end
    end

    if entry[source] then
      -- write overall value and per spell
      entry[source][action] = (entry[source][action] or 0) + tonumber(value)
      entry[source]["_sum"] = (entry[source]["_sum"] or 0) + tonumber(value)

      if datatype == "heal" then
        -- write effective healing sumary
        entry[source]["_esum"] = (entry[source]["_esum"] or 0) + tonumber(effective)

        -- write effective healing per spell
        entry[source]["_effective"] = entry[source]["_effective"] or {}
        entry[source]["_effective"][action] = (entry[source]["_effective"][action] or 0) + tonumber(effective)
      end

      -- the first data of a session starts the fight timer too
      if segment == 1 then
        if not fight.active then FightStart(GetTime()) end
        fight.last = GetTime()
      end

      entry[source]["_ctime"] = entry[source]["_ctime"] or 1
      entry[source]["_tick"] = entry[source]["_tick"] or GetTime()

      if entry[source]["_tick"] + 5 < GetTime() then
        entry[source]["_tick"] = GetTime()
        entry[source]["_ctime"] = entry[source]["_ctime"] + 5
      else
        entry[source]["_ctime"] = entry[source]["_ctime"] + (GetTime() - entry[source]["_tick"])
        entry[source]["_tick"] = GetTime()
      end
    end
  end

  for id, callback in pairs(parser.callbacks.refresh) do
    callback()
  end
end

parser.callbacks = {
  ["refresh"] = {}
}

-- data sources: each parser file registers one. Only one is active at a time,
-- picked by the "source" setting (1: best available, then a forced one).
--   available() returns true when the client can feed it
--   enable() registers its events and sets parser's OnEvent handler
local source_order = { "classicapi", "nampower", "combatlog" }
local source_ids = { classicapi = 2, nampower = 3, combatlog = 4 }

parser.sources = {}
parser.source_labels = {
  classicapi = "ClassicAPI",
  nampower = "Nampower",
  combatlog = "Chat Combat Log",
}

parser.RegisterSource = function(self, name, source)
  self.sources[name] = source
end

parser.SelectSource = function(self)
  local wanted = config.source or 1
  local pick

  for _, name in pairs(source_order) do
    local src = self.sources[name]
    if src and (wanted == 1 or source_ids[name] == wanted) and src.available() then
      pick = name
      break
    end
  end

  -- a forced source that is missing falls back to the best available one,
  -- and says why it couldn't be used
  self.unavailable = nil
  if not pick and wanted ~= 1 then
    for name, id in pairs(source_ids) do
      if id == wanted then
        local src = self.sources[name]
        self.unavailable = name
        self.unavailable_reason = src and src.why and src.why() or "not loaded"
      end
    end
  end

  if not pick then
    for _, name in pairs(source_order) do
      local src = self.sources[name]
      if src and src.available() then pick = name break end
    end
  end

  if pick == self.active_source then return pick end

  self:UnregisterAllEvents()
  self:SetScript("OnEvent", nil)
  if self.active_source and self.sources[self.active_source].disable then
    self.sources[self.active_source].disable()
  end

  self.active_source = pick
  if pick then self.sources[pick].enable() end
  return pick
end
