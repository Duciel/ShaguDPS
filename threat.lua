-- Threat view: the server's threat list for the current target.
--
-- 1.18.1 servers answer a threat query sent as an addon message with the
-- prefix "TWT_UDTSv4" and the text "limit=<n>" to the group channel. The
-- answer arrives as CHAT_MSG_ADDON whose text holds
--   "TWTv4=name:tank:threat:percent:melee;name:tank:threat:percent:melee;..."
-- for the target of the player who asked: tank is 1 for the unit's current
-- victim, percent is relative to the tank, melee is 1 for players in melee
-- range. Melee players pull aggro at 110% of the tank's threat, ranged ones
-- at 130%. Only works in a party or raid, on elite and boss targets.
--
-- This is the same server API the TWThreat addon uses. When another addon is
-- already asking, ShaguDPS only listens to the answers and doesn't ask twice.

local parser = ShaguDPS.parser
local config = ShaguDPS.config
local data = ShaguDPS.data
local window = ShaguDPS.window

local QUERY_PREFIX = "TWT_UDTSv4"
local ANSWER_TAG = "TWTv4="
local INTERVAL = 0.5

local PULL = "Pull Aggro"

-- view 5 shows data.threat: one entry per player, rebuilt on every answer
data.threat = {}

local threat = CreateFrame("Frame")
ShaguDPS.threat = threat

threat.target = nil      -- name of the unit the list belongs to
threat.pending = nil     -- we asked and wait for our answer
threat.last_foreign = 0  -- last answer to a question another addon asked

-- per player threat samples for threat per second: name -> { time, value }
local history = {}

local function Wipe(t)
  for k in pairs(t) do t[k] = nil end
end

local function Clear()
  Wipe(data.threat)
  Wipe(history)
end

-- threat per second over the last few seconds
local function TPS(name, value, now)
  local h = history[name]
  if not h then
    h = { now, value }
    history[name] = h
    return 0
  end

  local span = now - h[1]
  local tps = span > 0.9 and math.max(0, (value - h[2]) / span) or (h.tps or 0)

  -- move the window forward every five seconds
  if span > 5 then
    h[1], h[2] = now, value
  end

  h.tps = tps
  return tps
end

local function Entry(name)
  local entry = data.threat[name]
  if not entry then
    entry = { _ctime = 1 }
    data.threat[name] = entry
  end
  return entry
end

-- "name:tank:threat:percent:melee;..."
local function ParseAnswer(text)
  local _, start = string.find(text, ANSWER_TAG, 1, true)
  if not start then return end

  local list = string.sub(text, start + 1)

  -- tank mode answers append "#TMTv1=..." for other targets: ignore it
  local cut = string.find(list, "#", 1, true)
  if cut then list = string.sub(list, 1, cut - 1) end

  local now = GetTime()
  local seen = {}
  local tank_threat, my_melee = 0, nil
  local me = UnitName("player")

  for name, tank, value, perc, melee in string.gfind(list, "([^:;]+):(%d):(%-?%d+):(%-?%d+):(%d)") do
    value, perc = tonumber(value), tonumber(perc)
    local entry = Entry(name)
    entry._sum = value
    entry._perc = perc
    entry._tank = tank == "1" or nil
    entry._melee = melee == "1" or nil
    entry._tps = TPS(name, value, now)
    seen[name] = true

    if entry._tank then tank_threat = value end
    if name == me then my_melee = entry._melee end

    -- class colors for group members
    if not data.classes[name] then parser:ScanName(name) end
  end

  -- drop players that left the list
  for name in pairs(data.threat) do
    if not seen[name] and name ~= PULL then data.threat[name] = nil end
  end

  -- where you'd pull aggro: 110% of the tank in melee range, 130% at range
  if tank_threat > 0 then
    local pull = Entry(PULL)
    pull._sum = math.floor(tank_threat * (my_melee and 1.1 or 1.3))
    pull._perc = my_melee and 110 or 130
    pull._pull = true
  else
    data.threat[PULL] = nil
  end
end

-- does any visible window show threat? returns the most bars they show
local function ThreatBars()
  local bars
  for i = 1, 10 do
    local w = window[i]
    if w and config[i] and config[i].view == 5 and w:IsVisible() then
      bars = math.max(bars or 0, config[i].bars or 8)
    end
  end
  return bars
end

local function TargetUsable()
  if not UnitExists("target") or UnitIsPlayer("target") or UnitIsDead("target") then return nil end
  local class = UnitClassification("target")
  return class == "elite" or class == "worldboss" or class == "rareelite"
end

local function Refresh()
  for _, callback in pairs(parser.callbacks.refresh) do callback() end
end

threat:RegisterEvent("CHAT_MSG_ADDON")
threat:RegisterEvent("PLAYER_TARGET_CHANGED")
threat:RegisterEvent("PLAYER_REGEN_ENABLED")

threat:SetScript("OnEvent", function()
  if event == "CHAT_MSG_ADDON" then
    if not arg2 or not string.find(arg2, ANSWER_TAG, 1, true) then return end

    -- the first answer after our question is ours, any other one was asked
    -- for by another addon
    if threat.pending then
      threat.pending = nil
    else
      threat.last_foreign = GetTime()
    end

    -- answers are for the target of whoever asked: only take them while
    -- we look at a target that can have one
    if not TargetUsable() then return end
    threat.target = UnitName("target")
    ParseAnswer(arg2)
    Refresh()
  elseif event == "PLAYER_TARGET_CHANGED" then
    -- the list belongs to the old target
    Clear()
    threat.target = TargetUsable() and UnitName("target") or nil
    threat.tick = 0
    Refresh()
  elseif event == "PLAYER_REGEN_ENABLED" then
    Wipe(history)
  end
end)

-- ask the server twice a second while a threat window is shown
threat:SetScript("OnUpdate", function()
  local now = GetTime()
  if (this.tick or 0) > now then return end
  this.tick = now + INTERVAL

  if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then return end
  if not TargetUsable() or not UnitAffectingCombat("target") then return end

  local bars = ThreatBars()
  if not bars then return end

  -- another addon (TWThreat) is already asking: just listen to its answers
  if now - threat.last_foreign < INTERVAL * 2 then return end

  threat.pending = true
  local channel = GetNumRaidMembers() > 0 and "RAID" or "PARTY"
  SendAddonMessage(QUERY_PREFIX, "limit=" .. math.min(40, bars), channel)
end)
