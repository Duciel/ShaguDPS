-- check for expansion
local tbc = ShaguDPS.expansion() == "tbc" and true or nil

-- load public variables into local
local window = ShaguDPS.window
local parser = ShaguDPS.parser

local data = ShaguDPS.data
local config = ShaguDPS.config
local internals = ShaguDPS.internals

local textures = ShaguDPS.textures
local spairs = ShaguDPS.spairs
local round = ShaguDPS.round
local skin = ShaguDPS.skin

-- time used for "per second" values: each unit's own active time, or with the
-- "Fight Duration" time mode the time the whole segment lasted (set by Refresh)
local fight_time = nil
local function ctime(unitdata)
  return fight_time or unitdata["_ctime"]
end

-- title row: two icons left, three right, so the two text buttons sit a bit
-- left of the center and the window needs this much width
local MIN_WIDTH = 186
local TITLE_SHIFT = -8.5

local function SetFightTime(segment)
  fight_time = config.time_mode == 1 and parser:GetFightTime(segment or 1) or nil
end

-- all known classes
local classes = {
  WARRIOR = true, MAGE = true, ROGUE = true, DRUID = true, HUNTER = true,
  SHAMAN = true, PRIEST = true, WARLOCK = true, PALADIN = true,
}

-- default backdrops
local backdrop = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 8,
  insets = { left = 2, right = 2, top = 2, bottom = 2 }
}

local backdrop_window = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

local backdrop_border = {
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

-- templates describing the window contents
local view_templates = {
  [1] = { -- damage
    name = "Damage",
    sort = "normal",
    bar_max = "best",
    bar_val = "value",
    bar_lower_max = nil,
    bar_lower_val = nil,
    chat_string = "%s (%.1f%%)",
    bar_string = "%s (%.1f%%)",
    bar_string_params = { "value", "percent" },
  },
  [2] = { -- dps
    name = "DPS",
    sort = "per_second",
    bar_max = "persecond_best",
    bar_val = "value_persecond",
    bar_lower_max = nil,
    bar_lower_val = nil,
    chat_string = "%s (%.1f%%)",
    bar_string = "%s (%.1f%%)",
    bar_string_params = { "value_persecond", "percent_persecond" },
  },
  [3] = { -- heal
    name = "Heal",
    sort = "normal",
    bar_max = "best",
    bar_val = "effective_value",
    bar_lower_max = "best",
    bar_lower_val = "value",
    chat_string = "[+%s] %s (%.1f%%)",
    bar_string = "%s (%.1f%%)",
    bar_string_params = { "effective_value", "effective_percent" },
  },
  [4] = { -- hps
    name = "HPS",
    sort = "per_second",
    bar_max = "persecond_best",
    bar_val = "effective_value_persecond",
    bar_lower_max = "persecond_best",
    bar_lower_val = "value_persecond",
    chat_string = "[+%s] %s (%.1f%%)",
    bar_string = "%s (%.1f%%)",
    bar_string_params = { "effective_value_persecond", "effective_percent" },
  },
}

-- panel button templates
local menubuttons = {
  -- segments
  ["Current"]  = { 0, 1, -25.5, "Current Segment", "|cffffffffShow current fight",      "segment" },
  ["Overall"]  = { 1, 0, -25.5, "Overall Segment", "|cffffffffShow all fights",         "segment" },

  -- modes
  ["Damage"]   = { 0, 1, 25.5,  "Damage View",     "|cffffffffShow Damage Done",        "view" },
  ["DPS"]      = { 1, 2, 25.5,  "DPS View",        "|cffffffffShow Damage Per Second",  "view" },
  ["Heal"]     = { 2, 3, 25.5,  "Heal View",       "|cffffffffShow Healing Done",       "view" },
  ["HPS"]      = { 3, 4, 25.5,  "HPS View",        "|cffffffffShow Heal Per Second",    "view" },
}

-- default colors of chat types
local chatcolors = {
  ["SAY"] = "|cffFFFFFF",
  ["EMOTE"] = "|cffFF7E40",
  ["YELL"] = "|cffFF3F40",
  ["PARTY"] = "|cffAAABFE",
  ["GUILD"] = "|cff3CE13F",
  ["OFFICER"] = "|cff40BC40",
  ["RAID"] = "|cffFF7D01",
  ["RAID_WARNING"] = "|cffFF4700",
  ["BATTLEGROUND"] = "|cffFF7D01",
  ["WHISPER"] = "|cffFF7EFF",
  ["CHANNEL"] = "|cffFEC1C0"
}

local sort_algorithms = {
  normal = function(t,a,b)
    if t[a]["_esum"] and t[b]["_esum"] and t[a]["_esum"] ~= t[b]["_esum"] then
      return t[b]["_esum"] < t[a]["_esum"]
    else
      return t[b]["_sum"] < t[a]["_sum"]
    end
  end,
  per_second = function(t,a,b)
    if t[a]["_esum"] and t[b]["_esum"] and t[a]["_esum"] ~= t[b]["_esum"] then
      return t[b]["_esum"] / ctime(t[b]) < t[a]["_esum"] / ctime(t[a])
    else
      return t[b]["_sum"] / ctime(t[b]) < t[a]["_sum"] / ctime(t[a])
    end
  end,
  single_spell = function(t,a,b)
    if t["_effective"] and t["_effective"][a] and t["_effective"][b] and t["_effective"][a] ~= t["_effective"][b] then
      return t["_effective"][b] < t["_effective"][a]
    else
      if tonumber(t[b]) and tonumber(t[a]) then return t[b] < t[a] end
    end
  end
}

local rgbcache = {}
local function str2rgb(text)
  if not text then return 1, 1, 1 end
  if rgbcache[text] then return unpack(rgbcache[text]) end
  local counter = 1
  local l = string.len(text)
  for i = 1, l, 3 do
    counter = mod(counter*8161, 4294967279) +
        (string.byte(text,i)*16776193) +
        ((string.byte(text,i+1) or (l-i+256))*8372226) +
        ((string.byte(text,i+2) or (l-i+256))*3932164)
  end
  local hash = mod(mod(counter, 4294967291),16777216)
  local r = (hash - (mod(hash,65536))) / 65536
  local g = ((hash - r*65536) - ( mod((hash - r*65536),256)) ) / 256
  local b = hash - r*65536 - g*256
  rgbcache[text] = { r / 255, g / 255, b / 255 }
  return unpack(rgbcache[text])
end

local function spairs(t, order)
  -- collect the keys
  local keys = {}
  for k in pairs(t) do keys[table.getn(keys)+1] = k end

  -- if order function given, sort by it by passing the table and keys a, b,
  -- otherwise just sort the keys
  if order then
    table.sort(keys, function(a,b) return order(t, a, b) end)
  else
    table.sort(keys)
  end

  -- return the iterator function
  local i = 0
  return function()
    i = i + 1
    if keys[i] then
      return keys[i], t[keys[i]]
    end
  end
end

-- sorted keys of a segment without building a new table and closure on every
-- refresh: each window keeps its own buffer
local function SortedKeys(self, t, order)
  local keys = self.sortkeys
  if not keys then
    keys = {}
    self.sortkeys = keys
    self.sortcmp = function(a, b) return self.sortorder(self.sorttable, a, b) end
  end

  local n = 0
  for k in pairs(t) do
    n = n + 1
    keys[n] = k
  end

  for j = n + 1, table.getn(keys) do keys[j] = nil end
  if table.setn then table.setn(keys, n) end

  self.sorttable, self.sortorder = t, order
  table.sort(keys, self.sortcmp)
  self.sorttable = nil
  return keys, n
end

local function barTooltipShow()
  GameTooltip:SetOwner(this, "ANCHOR_RIGHT")

  local segment = this.parent.segment
  local wid = this.parent:GetID()
  if not segment[this.unit] then return end

  SetFightTime(config[wid].segment)
  local time = ctime(segment[this.unit])
  local value = segment[this.unit]["_sum"]
  local persec = round(value / time, 1)

  if this.glow then this.glow:Show() end

  GameTooltip:AddLine(this.title .. ":")

  if config[wid].view == 1 or config[wid].view == 2 then
    GameTooltip:AddDoubleLine("|cffffffffDamage", "|cffffffff" .. value)
    GameTooltip:AddDoubleLine("|cffffffffDamage Per Second", "|cffffffff" .. persec)
  elseif config[wid].view == 3 or config[wid].view == 4 then
    local evalue = segment[this.unit]["_esum"]
    local epersec = round(evalue / time, 1)

    GameTooltip:AddDoubleLine("|cffffffffHealing", "|cffffffff" .. evalue)
    GameTooltip:AddDoubleLine("|cffaaaaaaOverheal", "|cffcc8888+" .. value - evalue)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("|cffffffffHealing Per Second", "|cffffffff" .. epersec)
    GameTooltip:AddDoubleLine("|cffaaaaaaOverheal Per Second", "|cffcc8888+" .. persec - epersec)
  end

  -- active time vs. fight duration
  local active = segment[this.unit]["_ctime"] or 1
  if config.time_mode == 1 then
    GameTooltip:AddDoubleLine("|cffaaaaaaFight Duration", "|cffaaaaaa" .. SecondsToTime(math.floor(time)))
    GameTooltip:AddDoubleLine("|cffaaaaaaActive Time", "|cffaaaaaa" .. SecondsToTime(math.floor(active)) ..
      string.format(" (%d%%)", math.min(100, active / time * 100)))
  else
    GameTooltip:AddDoubleLine("|cffaaaaaaActive Time", "|cffaaaaaa" .. SecondsToTime(math.floor(active)))
  end

  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Details:")

  for attack, damage in spairs(segment[this.unit], sort_algorithms.single_spell) do
    if attack and not internals[attack] then
      local percent = damage == 0 and 0 or round(damage / segment[this.unit]["_sum"] * 100,1)
      if segment[this.unit]["_effective"] and segment[this.unit]["_effective"][attack] then
        -- heal / effective heal
        local effective = segment[this.unit]["_effective"][attack]
        local epercent = effective == 0 and 0 or round(effective / segment[this.unit]["_esum"] * 100,1)

        local str = string.format("|cffcc8888+%s|cffffffff %s (%.1f%%)", damage - effective, effective, epercent)
        GameTooltip:AddDoubleLine("|cffffffff" .. attack, str)
      else
        -- damage
        local str = string.format("|cffffffff %s (%.1f%%)", damage, percent)
        GameTooltip:AddDoubleLine("|cffffffff" .. attack, str)
      end
    end
  end
  GameTooltip:Show()
end

local function barTooltipHide()
  if this.glow then this.glow:Hide() end
  GameTooltip:Hide()
end

local function barScrollWheel()
  this.scroll = arg1 > 0 and this.scroll - 1 or this.scroll
  this.scroll = arg1 < 0 and this.scroll + 1 or this.scroll

  local count = 0
  for k,v in pairs(this.segment) do
    count = count + 1
  end

  this.scroll = math.min(this.scroll, count + 1 - config[this:GetID()].bars)
  this.scroll = math.max(this.scroll, 0)

  this:Refresh()
end

local function ResetData()
  -- clear overall damage data
  for k, v in pairs(data.damage[0]) do
    data.damage[0][k] = nil
  end

  -- clear current damage data
  for k, v in pairs(data.damage[1]) do
    data.damage[1][k] = nil
  end

  -- clear overall heal data
  for k, v in pairs(data.heal[0]) do
    data.heal[0][k] = nil
  end

  -- clear current heal data
  for k, v in pairs(data.heal[1]) do
    data.heal[1][k] = nil
  end

  for i=1,10 do
    if window[i] then window[i].scroll = 0 end
  end

  -- reset the fight timers too
  parser:ResetFight(true)

  -- reload all windows
  window.Refresh()
end

local function CreateBar(parent, i, background)
  local prefix = "ShaguDPS" .. (parent:GetID() == 1 and "" or parent:GetID())
  parent.bars[i] = parent.bars[i] or CreateFrame("StatusBar", prefix .. "Bar" .. i, parent)
  parent.bars[i].parent = parent

  parent.bars[i]:SetStatusBarTexture(textures[config.texture] or textures[1])
  parent.bars[i]:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -config.height * (i-1) - 22)
  parent.bars[i]:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -config.height * (i-1) - 22)
  parent.bars[i]:SetHeight(config.height - config.spacing)
  parent.bars[i]:SetFrameLevel(4)

  parent.bars[i].lowerBar = parent.bars[i].lowerBar or CreateFrame("StatusBar", prefix .. "LowerBar" .. i, parent)
  parent.bars[i].lowerBar:SetStatusBarTexture(textures[config.texture] or textures[1])
  parent.bars[i].lowerBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -config.height * (i-1) - 22)
  parent.bars[i].lowerBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -config.height * (i-1) - 22)
  parent.bars[i].lowerBar:SetStatusBarColor(1, 1, 1, .4)
  parent.bars[i].lowerBar:SetHeight(config.height - config.spacing)
  parent.bars[i].lowerBar:SetFrameLevel(2)

  parent.bars[i].textLeft = parent.bars[i].textLeft or parent.bars[i]:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  parent.bars[i].textLeft:SetFont(STANDARD_TEXT_FONT, 10, "THINOUTLINE")
  parent.bars[i].textLeft:SetJustifyH("LEFT")
  parent.bars[i].textLeft:SetFontObject(GameFontWhite)
  parent.bars[i].textLeft:SetParent(parent.bars[i])
  parent.bars[i].textLeft:ClearAllPoints()
  parent.bars[i].textLeft:SetPoint("TOPLEFT", parent.bars[i], "TOPLEFT", 5, 1)
  parent.bars[i].textLeft:SetPoint("BOTTOMRIGHT", parent.bars[i], "BOTTOMRIGHT", -5, 0)

  parent.bars[i].textRight = parent.bars[i].textRight or parent.bars[i]:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  parent.bars[i].textRight:SetFont(STANDARD_TEXT_FONT, 10, "THINOUTLINE")
  parent.bars[i].textRight:SetJustifyH("RIGHT")
  parent.bars[i].textRight:SetFontObject(GameFontWhite)
  parent.bars[i].textRight:SetParent(parent.bars[i])
  parent.bars[i].textRight:ClearAllPoints()
  parent.bars[i].textRight:SetPoint("TOPLEFT", parent.bars[i], "TOPLEFT", 5, 1)
  parent.bars[i].textRight:SetPoint("BOTTOMRIGHT", parent.bars[i], "BOTTOMRIGHT", -5, 0)

  -- classic: shadowed text, a dark track behind the bar and a hover glow
  local bar = parent.bars[i]
  if ShaguDPS.classic then
    local size = math.max(8, math.min(13, config.height - 4))
    skin.Font(bar.textLeft, size)
    skin.Font(bar.textRight, size)
    bar.textLeft:SetTextColor(1, 1, 1)
    bar.textRight:SetTextColor(1, 1, 1)

    -- the track sits below the overheal bar, and follows the bar's visibility
    if not bar.track then
      bar.track = CreateFrame("Frame", nil, parent)
      bar.track:SetFrameLevel(1)
      bar.track.tex = bar.track:CreateTexture(nil, "BACKGROUND")
      bar.track.tex:SetAllPoints(bar.track)
      bar:SetScript("OnShow", function() this.track:Show() end)
      bar:SetScript("OnHide", function() this.track:Hide() end)
    end
    bar.track:SetAllPoints(bar)
    bar.track.tex:SetTexture(textures[config.texture] or textures[1])
    bar.track.tex:SetVertexColor(0.2, 0.2, 0.2, 0.35)
    if not bar:IsShown() then bar.track:Hide() end

    bar.glow = bar.glow or skin.Glow(bar, "OVERLAY", 0.35)
    bar.glow:Hide()
  end

  parent.bars[i]:EnableMouse(true)
  parent.bars[i]:SetScript("OnEnter", barTooltipShow)
  parent.bars[i]:SetScript("OnLeave", barTooltipHide)

  return parent.bars[i]
end

local function btnEnter()
  if this.tooltip then
    GameTooltip_SetDefaultAnchor(GameTooltip, this)
    for i, data in pairs(this.tooltip) do
      if type(data) == "string" then
        GameTooltip:AddLine(data)
      elseif type(data) == "table" then
        GameTooltip:AddDoubleLine(data[1], data[2])
      end
    end
    GameTooltip:Show()
  end

  if this.hoverOn then return this:hoverOn() end
  this:SetBackdropBorderColor(1,.8,0,1)
end

local function btnLeave()
  if this.tooltip then
    GameTooltip:Hide()
  end

  if this.hoverOff then return this:hoverOff() end
  this:SetBackdropBorderColor(.4,.4,.4,1)
end

local function announce(text)
  local type = tbc and ChatFrameEditBox:GetAttribute("chatType") or ChatFrameEditBox.chatType
  local language = tbc and ChatFrameEditBox:GetAttribute("language") or ChatFrameEditBox.language
  local channel = tbc and ChatFrameEditBox:GetAttribute("channelTarget") or ChatFrameEditBox.channelTarget
  local target = tbc and ChatFrameEditBox:GetAttribute("tellTarget") or ChatFrameEditBox.tellTarget

  if type == "WHISPER" then
    SendChatMessage(text, type, language, target)
  elseif type == "CHANNEL" then
    SendChatMessage(text, type, language, channel);
  else
    SendChatMessage(text, type, language);
  end
end

local function GetCaps(view, values)
  local values = values or {}

  -- reset/empty values
  values.best = 0
  values.all = 0
  values.persecond_best = 0
  values.persecond_all = 0
  values.effective_best = 0
  values.effective_all = 0
  values.effective_persecond_best = 0
  values.effective_persecond_all = 0

  for name, data in pairs(view) do
    local val = 0

    -- calculate normal values
    if data["_sum"] and data["_ctime"] then
      local time = ctime(data)
      values.all = values.all + data["_sum"]
      if data["_sum"] > values.best then
        values.best = data["_sum"]
      end

      values.persecond_all = values.persecond_all + data["_sum"] / time
      if data["_sum"] / time > values.persecond_best then
        values.persecond_best = data["_sum"] / time
      end
    end

    -- calculate effective values
    if data["_esum"] and data["_ctime"] then
      local time = ctime(data)
      values.effective_all = values.effective_all + data["_esum"]
      if data["_esum"] > values.effective_best then
        values.effective_best = data["_esum"]
      end

      values.effective_persecond_all = values.effective_persecond_all + data["_esum"] / time
      if data["_esum"] / time > values.effective_persecond_best then
        values.effective_persecond_best = data["_esum"] / time
      end
    end
  end

  return values
end

local function GetData(unitdata, values)
  local values = values or {}

  -- read normal values
  values.value = unitdata["_sum"]
  values.value_persecond = round(values.value / ctime(unitdata), 1)
  values.percent = values.value == 0 and 0 or round(values.value / values.all * 100,1)
  values.percent_persecond = values.value_persecond == 0 and 0 or round(values.value_persecond / values.persecond_all * 100, 1)

  -- read effective values
  if unitdata["_esum"] then
    values.effective_value = unitdata["_esum"]
    values.effective_value_persecond = round(values.effective_value / ctime(unitdata), 1)
    values.effective_percent = values.effective_value == 0 and 0 or round(values.effective_value / values.effective_all * 100, 1)
    values.effective_percent_persecond = values.effective_value_persecond == 0 and 0 or round(values.effective_value_persecond / values.effective_persecond_all * 100,1)
    values.uneffective_value = values.value - values.effective_value
    values.uneffective_value_persecond = values.value_persecond - values.effective_value_persecond
  else
    values.effective_value = 0
    values.effective_value_persecond = 0
    values.effective_percent = 0
    values.effective_percent_persecond = 0
    values.uneffective_value = 0
    values.uneffective_value_persecond = 0
  end

  -- check pet and detect owner/unit names
  local pet  = not classes[data["classes"][values.name]] and data["classes"][values.name] ~= "__other__"
  local unit = pet and data["classes"][values.name] or values.name

  -- merge pet/owner strings if option is set
  if config.merge_pets == 0 then
    -- "Wolf (Hunter)" becomes "Hunter - Wolf"
    local petname = pet and string.gsub(values.name, "%s%(.-%)$", "") or nil
    values.name = pet and unit .. " - " .. petname or unit
  else
    values.name = unit
  end

  -- write color into view
  -- default to faded name colors
  local r, g, b = str2rgb(values.name)
  values.color = values.color or {}
  values.color.r = r / 4 + .4
  values.color.g = g / 4 + .4
  values.color.b = b / 4 + .4

  -- replace color by class colors if possible
  if classes[data["classes"][unit]] then
    -- set color to player class colors
    values.color.r = RAID_CLASS_COLORS[data["classes"][unit]].r
    values.color.g = RAID_CLASS_COLORS[data["classes"][unit]].g
    values.color.b = RAID_CLASS_COLORS[data["classes"][unit]].b

    if config.pastel == 1 then
      values.color.r = (values.color.r + .5) * .5
      values.color.g = (values.color.g + .5) * .5
      values.color.b = (values.color.b + .5) * .5
    end
  end

  return values
end

local function Refresh(self, force, report)
  -- skip refreshs on legacy calls
  if not self or type(self) == "boolean" then return end

  -- assign shortcuts
  local values, buttons = self.values, self.buttons
  local wid = self:GetID()

  -- config changes
  if force then
    if config.visible == 1 then
      self:Show()
    else
      self:Hide()
    end

    for _, button in pairs(buttons) do
      button.caption:SetTextColor(1,1,1,1)
    end

    if self.titleRule then
      if config.backdrop == 1 then self.titleRule:Show() else self.titleRule:Hide() end
    end

    -- update backdrop borders
    if config.backdrop == 1 and ShaguDPS.classic then
      local c = skin.colors
      self:SetBackdrop(skin.backdrop_window)
      self:SetBackdropColor(c.bg[1], c.bg[2], c.bg[3], .9)

      self.border:SetBackdrop(skin.backdrop_border)
      self.border:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], 1)
    elseif config.backdrop == 1 then
      -- window background
      self:SetBackdrop(backdrop_window)
      self:SetBackdropColor(.5,.5,.5,.5)

      -- window border
      self.border:SetBackdrop(backdrop_border)
      self.border:SetBackdropBorderColor(.7,.7,.7,1)
    else
      self:SetBackdrop(nil)
      self.border:SetBackdrop(nil)
    end

    -- update panel button appearance
    if config[wid].view == 1 then
      self.btnDamage.caption:SetTextColor(1,.9,0,1)
      self.btnMode.caption:SetText("Damage")
    elseif config[wid].view == 2 then
      self.btnDPS.caption:SetTextColor(1,.9,0,1)
      self.btnMode.caption:SetText("DPS")
    elseif config[wid].view == 3 then
      self.btnHeal.caption:SetTextColor(1,.9,0,1)
      self.btnMode.caption:SetText("Heal")
    elseif config[wid].view == 4 then
      self.btnHPS.caption:SetTextColor(1,.9,0,1)
      self.btnMode.caption:SetText("HPS")
    end

    if config[wid].segment == 0 then
      self.btnOverall.caption:SetTextColor(1,.9,0,1)
      self.btnSegment.caption:SetText("Overall")
    elseif config[wid].segment == 1 then
      self.btnCurrent.caption:SetTextColor(1,.9,0,1)
      self.btnSegment.caption:SetText("Current")
    end

    -- lock icon of the title row
    if self.btnLock then
      local locked = config.lock == 1
      self.btnLock.tex:SetTexture("Interface\\AddOns\\ShaguDPS\\img\\" .. (locked and "lock" or "unlock"))
      self.btnLock.tooltip = {
        locked and "Unlock Windows" or "Lock Windows",
        locked and "|cffffffffAllow moving and resizing" or "|cffffffffPrevent moving and resizing",
      }
    end

    self:SetWidth(math.max(MIN_WIDTH, config[wid].width or MIN_WIDTH))
    self:SetHeight(config.height * (config[wid].bars or 8) + 22 + (config[wid].bars == 0 and 2 or 3))
  end

  -- hidden windows catch up when they are shown again
  if not force and not report and not self:IsVisible() then
    self.needs_refresh = true
    return
  end

  -- clear previous results
  for id, bar in pairs(self.bars) do
    bar.lowerBar:Hide()
    bar:Hide()
  end

  -- set view to damage or heal
  if config[wid].view == 1 or config[wid].view == 2 then
    self.segment = data.damage[(config[wid].segment or 0)]
  elseif config[wid].view == 3 or config[wid].view == 4 then
    self.segment = data.heal[(config[wid].segment or 0)]
  end

  -- read view settings
  local view_effective  = (config[wid].view == 3 or config[wid].view == 4) and true or nil
  local view_per_second = (config[wid].view == 2 or config[wid].view == 4) and true or nil

  local template = view_templates[config[wid].view]
  local sort = sort_algorithms[template.sort]

  -- report to chat if flag is set
  if report then
    local name = view_templates[config[wid].view].name
    local seg = config[wid].segment == 1 and "Current" or "Overall"
    announce("ShaguDPS - " .. seg .. " " .. name .. ":")
  end

  -- load caps of the current view
  SetFightTime(config[wid].segment)
  self.values = self.GetCaps(self.segment, self.values)

  local keys, count = SortedKeys(self, self.segment, sort)
  local first = self.scroll + 1
  local last = math.min(count, self.scroll + (config[wid].bars or 8))
  if report then first, last = 1, math.min(count, math.max(last, 10)) end

  -- only the units that get a bar (or a chat line) need their values read
  for i = first, last do
    local name = keys[i]
    local unitdata = self.segment[name]

    -- attach name to values
    self.values.name = name

    -- load data values of the current unit
    self.values = self.GetData(unitdata, self.values)

    local a = template.bar_string_params
    local bar = i - self.scroll
    if bar >= 1 and bar <= (config[wid].bars or 8) then
      self.bars[bar] = not force and self.bars[bar] or CreateBar(self, bar)

      -- attach unit and titles to bar
      self.bars[bar].title = self.values.name
      self.bars[bar].unit = name

      self.bars[bar]:SetMinMaxValues(0, self.values[template.bar_max])
      self.bars[bar]:SetValue(self.values[template.bar_val])

      -- enable lower bar if template requires it
      if template.bar_lower_max and template.bar_lower_val then
        self.bars[bar].lowerBar:SetMinMaxValues(0, self.values[template.bar_lower_max])
        self.bars[bar].lowerBar:SetValue(self.values[template.bar_lower_val])
        self.bars[bar].lowerBar:Show()
      else
        self.bars[bar].lowerBar:Hide()
      end

      self.bars[bar]:SetStatusBarColor(self.values.color.r, self.values.color.g, self.values.color.b)
      self.bars[bar].textLeft:SetText(i .. ". " .. self.values.name)

      local line = string.format(template.bar_string,
        self.values[a[1]], self.values[a[2]], self.values[a[3]], self.values[a[4]], self.values[a[5]])

      self.bars[bar].textRight:SetText(line)

      -- keep long names from running into the values
      self.bars[bar].textLeft:SetPoint("BOTTOMRIGHT", self.bars[bar], "BOTTOMRIGHT",
        -math.ceil(self.bars[bar].textRight:GetStringWidth() or 0) - 10, 0)

      self.bars[bar]:Show()
    end

    -- report to chat if flag is set
    if report and i <= 10 then
      local chat = string.format(template.chat_string,
        self.values[a[1]], self.values[a[2]], self.values[a[3]], self.values[a[4]], self.values[a[5]])

      announce(i .. ". " .. self.values.name .. " " .. chat)
    end
  end
end

local function Resize(self)
  local wid = self:GetID()
  local width = self:GetWidth()
  local height = self:GetTop() - self:GetBottom()
  local bars = (height - 22) / config.height
  bars = math.floor(bars)

  config[wid].width = width
  if config[wid].bars ~= bars then
    config[wid].bars = bars
    self:Refresh()
  end
end

local function CreateWindow(wid)
  -- create default config
  config[wid] = config[wid] or {}
  config[wid].bars = config[wid].bars or 8
  config[wid].width = math.max(MIN_WIDTH, config[wid].width or MIN_WIDTH)
  config[wid].segment = config[wid].segment or 1
  config[wid].view = config[wid].view or 1

  local frame = CreateFrame("Frame", "ShaguDPSWindow" .. (wid == 1 and "" or wid), UIParent)
  frame.scroll = 0
  frame.GetCaps = GetCaps
  frame.GetData = GetData
  frame.Refresh = Refresh
  frame.Resize = Resize

  frame.LoadPosition = function()
    if ShaguDPS_Config and ShaguDPS_Config[frame:GetID()] and ShaguDPS_Config[frame:GetID()].pos then
      -- load config position if existing
      frame:ClearAllPoints()
      frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", unpack(ShaguDPS_Config[frame:GetID()].pos))
    else
      -- use default window position
      frame:ClearAllPoints()
      frame:SetPoint("RIGHT", UIParent, "RIGHT", -100, -100)
    end
  end

  frame:SetID(wid)
  frame:EnableMouse(true)
  frame:EnableMouseWheel(1)
  frame:SetResizable(true)
  frame:SetMinResize(MIN_WIDTH, 22)
  frame:RegisterForDrag("LeftButton")
  frame:SetMovable(true)
  frame:SetScript("OnDragStart", function()
    if config.lock == 0 then
      frame:StartMoving()
    end
  end)

  frame:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    ShaguDPS_Config[frame:GetID()].pos = { frame:GetCenter() }
  end)

  frame:SetScript("OnMouseWheel", barScrollWheel)
  frame:SetClampedToScreen(true)

  frame:SetScript("OnUpdate", function()
    -- update config on resize
    if this.sizing then
      this:Resize()
    end

    -- only check for updates every .2 seconds
    if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + .2 end

    -- check for resize button
    if config.lock == 0 and MouseIsOver(this) then
      this.btnResize:SetAlpha(.5)
    else
      this.btnResize:SetAlpha(0)
    end

    -- refresh window if needed
    if this.needs_refresh then
      this.needs_refresh = nil
      this:Refresh()
    end
  end)

  frame:RegisterEvent("PLAYER_LOGIN")
  frame:SetScript("OnEvent", frame.LoadPosition)
  frame.LoadPosition()

  frame.title = frame:CreateTexture(nil, "NORMAL")
  frame.title:SetTexture(0,0,0,.6)
  frame.title:SetHeight(20)
  frame.title:SetPoint("TOPLEFT", 2, -2)
  frame.title:SetPoint("TOPRIGHT", -2, -2)

  frame.btnSegment = CreateFrame("Button", "ShaguDPSDamage", frame)
  frame.btnSegment:SetPoint("RIGHT", frame.title, "CENTER", TITLE_SHIFT - .5, 0)
  frame.btnSegment:SetFrameStrata("MEDIUM")
  frame.btnSegment:SetHeight(16)
  frame.btnSegment:SetWidth(50)
  frame.btnSegment:SetBackdrop(backdrop)
  frame.btnSegment:SetBackdropColor(.2,.2,.2,1)
  frame.btnSegment:SetBackdropBorderColor(.4,.4,.4,1)

  frame.btnSegment.caption = frame.btnSegment:CreateFontString("ShaguDPSTitle", "OVERLAY", "GameFontWhite")
  frame.btnSegment.caption:SetFont(STANDARD_TEXT_FONT, 9)
  frame.btnSegment.caption:SetText("Overall")
  frame.btnSegment.caption:SetAllPoints()
  frame.btnSegment.tooltip = { "Select Segment", "|cffffffffOverall, Current" }
  frame.btnSegment:SetScript("OnEnter", btnEnter)
  frame.btnSegment:SetScript("OnLeave", btnLeave)
  frame.btnSegment:SetScript("OnClick", function()
    if frame.btnCurrent:IsShown() then
      frame.btnDamage:Hide()
      frame.btnDPS:Hide()
      frame.btnHeal:Hide()
      frame.btnHPS:Hide()
      frame.btnOverall:Hide()
      frame.btnCurrent:Hide()
    else
      frame.btnDamage:Hide()
      frame.btnDPS:Hide()
      frame.btnHeal:Hide()
      frame.btnHPS:Hide()
      frame.btnOverall:Show()
      frame.btnCurrent:Show()
    end
  end)

  frame.btnMode = CreateFrame("Button", "ShaguDPSDamage", frame)
  frame.btnMode:SetPoint("LEFT", frame.title, "CENTER", TITLE_SHIFT + .5, 0)
  frame.btnMode:SetFrameStrata("MEDIUM")
  frame.btnMode:SetHeight(16)
  frame.btnMode:SetWidth(50)
  frame.btnMode:SetBackdrop(backdrop)
  frame.btnMode:SetBackdropColor(.2,.2,.2,1)
  frame.btnMode:SetBackdropBorderColor(.4,.4,.4,1)

  frame.btnMode.caption = frame.btnMode:CreateFontString("ShaguDPSTitle", "OVERLAY", "GameFontWhite")
  frame.btnMode.caption:SetFont(STANDARD_TEXT_FONT, 9)
  frame.btnMode.caption:SetText("Mode: Damage")
  frame.btnMode.caption:SetAllPoints()
  frame.btnMode.tooltip = { "Select Mode", "|cffffffffDamage, DPS, Heal, HPS" }
  frame.btnMode:SetScript("OnEnter", btnEnter)
  frame.btnMode:SetScript("OnLeave", btnLeave)
  frame.btnMode:SetScript("OnClick", function()
    if frame.btnDamage:IsShown() then
      frame.btnDamage:Hide()
      frame.btnDPS:Hide()
      frame.btnHeal:Hide()
      frame.btnHPS:Hide()
      frame.btnOverall:Hide()
      frame.btnCurrent:Hide()
    else
      frame.btnDamage:Show()
      frame.btnDPS:Show()
      frame.btnHeal:Show()
      frame.btnHPS:Show()
      frame.btnOverall:Hide()
      frame.btnCurrent:Hide()
    end
  end)

  for name, template in pairs(menubuttons) do
    frame["btn"..name] = CreateFrame("Button", "ShaguDPS" .. name, frame)

    local button = frame["btn"..name]
    local template = template

    button:SetPoint("CENTER", frame.title, "CENTER", template[3] + TITLE_SHIFT, -17-template[1]*14)
    button:SetFrameStrata("HIGH")
    button:SetHeight(16)
    button:SetWidth(50)
    button:SetBackdrop(backdrop)
    button:SetBackdropColor(.2,.2,.2,1)
    button:SetBackdropBorderColor(.4,.4,.4,1)
    button:Hide()

    button.caption = button:CreateFontString("ShaguDPS"..name.."Title", "OVERLAY", "GameFontWhite")
    button.caption:SetFont(STANDARD_TEXT_FONT, 9)
    button.caption:SetText(name)
    button.caption:SetAllPoints()
    button.tooltip = { template[4], template[5] }
    button:SetScript("OnEnter", btnEnter)
    button:SetScript("OnLeave", btnLeave)
    button:SetScript("OnClick", function()
      config[frame:GetID()][template[6]] = template[2]

      frame.scroll = 0
      frame:Refresh(true)

      for button in pairs(menubuttons) do
        frame["btn"..button]:Hide()
      end
    end)
  end

  frame.btnAnnounce = CreateFrame("Button", "ShaguDPSReset", frame)
  frame.btnAnnounce:SetPoint("LEFT", frame.title, "LEFT", 2, 0)
  frame.btnAnnounce:SetFrameStrata("MEDIUM")
  frame.btnAnnounce:SetHeight(16)
  frame.btnAnnounce:SetWidth(16)
  frame.btnAnnounce:SetBackdrop(backdrop)
  frame.btnAnnounce:SetBackdropColor(.2,.2,.2,1)
  frame.btnAnnounce:SetBackdropBorderColor(.4,.4,.4,1)
  frame.btnAnnounce.tooltip = {
    "Send to Chat",
    { "|cffffffffClick", "|cffaaaaaaAsk to anounce all data."},
    { "|cffffffffShift-Click", "|cffaaaaaaAnnounce all data."},
  }

  frame.btnAnnounce.tex = frame.btnAnnounce:CreateTexture()
  frame.btnAnnounce.tex:SetWidth(10)
  frame.btnAnnounce.tex:SetHeight(10)
  frame.btnAnnounce.tex:SetPoint("CENTER", 0, 0)
  frame.btnAnnounce.tex:SetTexture("Interface\\AddOns\\ShaguDPS" .. (tbc and "-tbc" or "") .. "\\img\\announce")
  frame.btnAnnounce:SetScript("OnEnter", btnEnter)
  frame.btnAnnounce:SetScript("OnLeave", btnLeave)
  frame.btnAnnounce:SetScript("OnClick", function()
    if IsShiftKeyDown() then
      -- reload / anounce
      frame:Refresh(nil, true)
    else
      local ctype = tbc and ChatFrameEditBox:GetAttribute("chatType") or ChatFrameEditBox.chatType
      local color = chatcolors[ctype]
      if not color then color = "|cff00FAF6" end

      local name = view_templates[config[frame:GetID()].view].name
      local text = "Post |cffffdd00" .. name .. "|r data into /" .. color..string.lower(ctype) .. "|r?"

      local dialog = StaticPopupDialogs["SHAGUMETER_QUESTION"]
      dialog.text = text

      dialog.OnAccept = function() frame:Refresh(nil, true) end
      StaticPopup_Show("SHAGUMETER_QUESTION")
    end
  end)

  frame.btnSettings = CreateFrame("Button", "ShaguDPSReset", frame)
  frame.btnSettings:SetPoint("LEFT", frame.btnAnnounce, "RIGHT", 1, 0)
  frame.btnSettings:SetFrameStrata("MEDIUM")
  frame.btnSettings:SetHeight(16)
  frame.btnSettings:SetWidth(16)
  frame.btnSettings:SetBackdrop(backdrop)
  frame.btnSettings:SetBackdropColor(.2,.2,.2,1)
  frame.btnSettings:SetBackdropBorderColor(.4,.4,.4,1)
  frame.btnSettings.tooltip = {
    "Settings",
    "|cffffffffShow Configuration Window"
  }

  frame.btnSettings.tex = frame.btnSettings:CreateTexture()
  frame.btnSettings.tex:SetWidth(10)
  frame.btnSettings.tex:SetHeight(10)
  frame.btnSettings.tex:SetPoint("CENTER", 0, 0)
  frame.btnSettings.tex:SetTexture("Interface\\AddOns\\ShaguDPS" .. (tbc and "-tbc" or "") .. "\\img\\settings")
  frame.btnSettings:SetScript("OnEnter", btnEnter)
  frame.btnSettings:SetScript("OnLeave", btnLeave)
  frame.btnSettings:SetScript("OnClick", function()
    if ShaguDPS.settings:IsShown() then
      ShaguDPS.settings:Hide()
    else
      ShaguDPS.settings:Show()
    end
  end)

  frame.btnReset = CreateFrame("Button", "ShaguDPSReset", frame)
  frame.btnReset:SetPoint("RIGHT", frame.title, "RIGHT", -2, 0)
  frame.btnReset:SetFrameStrata("MEDIUM")
  frame.btnReset:SetHeight(16)
  frame.btnReset:SetWidth(16)
  frame.btnReset:SetBackdrop(backdrop)
  frame.btnReset:SetBackdropColor(.2,.2,.2,1)
  frame.btnReset:SetBackdropBorderColor(.4,.4,.4,1)
  frame.btnReset.tooltip = {
    "Reset Data",
    { "|cffffffffClick", "|cffaaaaaaAsk to reset all data."},
    { "|cffffffffShift-Click", "|cffaaaaaaReset all data."},
  }

  frame.btnReset.tex = frame.btnReset:CreateTexture()
  frame.btnReset.tex:SetWidth(10)
  frame.btnReset.tex:SetHeight(10)
  frame.btnReset.tex:SetPoint("CENTER", 0, 0)
  frame.btnReset.tex:SetTexture("Interface\\AddOns\\ShaguDPS" .. (tbc and "-tbc" or "") .. "\\img\\reset")
  frame.btnReset:SetScript("OnEnter", btnEnter)
  frame.btnReset:SetScript("OnLeave", btnLeave)
  frame.btnReset:SetScript("OnClick", function()
    if IsShiftKeyDown() then
      ResetData()
    else
      local dialog = StaticPopupDialogs["SHAGUMETER_QUESTION"]
      dialog.text = "Do you wish to reset the data?"
      dialog.OnAccept = ResetData
      StaticPopup_Show("SHAGUMETER_QUESTION")
    end
  end)

  frame.btnWindow = CreateFrame("Button", "ShaguDPSReset", frame)
  frame.btnWindow:SetPoint("RIGHT", frame.btnReset, "LEFT", -1, 0)
  frame.btnWindow:SetFrameStrata("MEDIUM")
  frame.btnWindow:SetHeight(16)
  frame.btnWindow:SetWidth(16)
  frame.btnWindow:SetBackdrop(backdrop)
  frame.btnWindow:SetBackdropColor(.2,.2,.2,1)
  frame.btnWindow:SetBackdropBorderColor(.4,.4,.4,1)

  frame.btnWindow.tex = frame.btnWindow:CreateTexture()
  frame.btnWindow.tex:SetWidth(10)
  frame.btnWindow.tex:SetHeight(10)
  frame.btnWindow.tex:SetPoint("CENTER", 0, 0)

  if frame:GetID() == 1 then
    frame.btnWindow.tex:SetTexture("Interface\\AddOns\\ShaguDPS" .. (tbc and "-tbc" or "") .. "\\img\\plus")
    frame.btnWindow.tooltip = {
      "New Window",
      "|cffffffffCreate a new window"
    }

    frame.btnWindow:SetScript("OnClick", function()
      for i=1,10 do
        if not ShaguDPS.window[i] then
          -- new windows start with the size and view of the first one
          config[i] = {
            width = config[1].width, bars = config[1].bars,
            view = config[1].view, segment = config[1].segment,
          }

          ShaguDPS.window[i] = CreateWindow(i)
          ShaguDPS.window.Refresh(true)
          return
        end
      end
    end)
  else
    frame.btnWindow.tex:SetTexture("Interface\\AddOns\\ShaguDPS" .. (tbc and "-tbc" or "") .. "\\img\\minus")
    frame.btnWindow.tooltip = {
      "Remove Window",
      "|cffffffffDelete this window"
    }

    frame.btnWindow:SetScript("OnClick", function()
      local wid = frame:GetID()
      window[wid]:Hide()
      window[wid] = nil
      config[wid] = nil
      window.Refresh(true)
    end)
  end

  frame.btnWindow:SetScript("OnEnter", btnEnter)
  frame.btnWindow:SetScript("OnLeave", btnLeave)

  -- lock / unlock all windows
  frame.btnLock = CreateFrame("Button", nil, frame)
  frame.btnLock:SetPoint("RIGHT", frame.btnWindow, "LEFT", -1, 0)
  frame.btnLock:SetFrameStrata("MEDIUM")
  frame.btnLock:SetHeight(16)
  frame.btnLock:SetWidth(16)
  frame.btnLock:SetBackdrop(backdrop)
  frame.btnLock:SetBackdropColor(.2,.2,.2,1)
  frame.btnLock:SetBackdropBorderColor(.4,.4,.4,1)

  frame.btnLock.tex = frame.btnLock:CreateTexture()
  frame.btnLock.tex:SetWidth(10)
  frame.btnLock.tex:SetHeight(10)
  frame.btnLock.tex:SetPoint("CENTER", 0, 0)
  frame.btnLock.tex:SetTexture("Interface\\AddOns\\ShaguDPS\\img\\unlock")
  frame.btnLock:SetScript("OnEnter", btnEnter)
  frame.btnLock:SetScript("OnLeave", btnLeave)
  frame.btnLock:SetScript("OnClick", function()
    config.lock = config.lock == 1 and 0 or 1
    window.Refresh(true)

    local check = ShaguDPS.settings.checks and ShaguDPS.settings.checks.lock
    if check then check:SetChecked(config.lock == 1) end

    -- show the new state right away while the mouse is still on it
    GameTooltip:Hide()
    btnEnter()
  end)

  frame.btnResize = CreateFrame("Frame", nil, frame)
  frame.btnResize:SetPoint("BOTTOMRIGHT", -3, 3)
  frame.btnResize:SetWidth(12)
  frame.btnResize:SetHeight(12)
  frame.btnResize:EnableMouse(1)
  frame.btnResize.tex = frame.btnResize:CreateTexture(nil, "BACKGROUND")
  frame.btnResize.tex:SetAllPoints()
  frame.btnResize.tex:SetTexture("Interface\\AddOns\\ShaguDPS" .. (tbc and "-tbc" or "") .. "\\img\\resize")
  frame.btnResize:SetFrameLevel(50)
  frame.btnResize:SetScript("OnMouseDown", function()
    if not this:GetParent().sizing and config.lock == 0 then
      this:GetParent().sizing = true
      this:GetParent():StartSizing()
    end
  end)

  frame.btnResize:SetScript("OnMouseUp", function()
    this:GetParent().sizing = nil
    this:GetParent():StopMovingOrSizing()
    this:GetParent():Refresh(true)
  end)

  frame.border = CreateFrame("Frame", "ShaguDPSBorder", frame)
  frame.border:ClearAllPoints()
  frame.border:SetPoint("TOPLEFT", frame, "TOPLEFT", -1,1)
  frame.border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1,-1)
  frame.border:SetFrameLevel(100)

  frame.bars = {}
  frame.values = {}
  frame.buttons = {
    frame.btnDamage,
    frame.btnDPS,
    frame.btnHeal,
    frame.btnHPS,
    frame.btnOverall,
    frame.btnCurrent
  }

  table.insert(parser.callbacks.refresh, function()
    frame.needs_refresh = true
  end)

  if ShaguDPS.classic then window.ApplyClassic(frame) end

  return frame
end

-- classic theme: no boxes around the title buttons, gold text and icons,
-- a silver rule under the title and the dropdown lists as tooltip panels
window.ApplyClassic = function(frame)
  if frame.classic then return end
  frame.classic = true

  frame.title:SetTexture(0, 0, 0, 0)

  frame.titleRule = skin.Rule(frame)
  frame.titleRule:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -21)
  frame.titleRule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -21)
  frame.titleRule:SetFrameLevel(frame:GetFrameLevel() + 3)

  skin.IconButton(frame.btnAnnounce)
  skin.IconButton(frame.btnSettings)
  skin.IconButton(frame.btnReset)
  skin.IconButton(frame.btnWindow)
  skin.IconButton(frame.btnLock)
  skin.TextButton(frame.btnSegment, 10)
  skin.TextButton(frame.btnMode, 10)

  -- one tooltip panel behind each dropdown list
  local function MenuPanel(first, last)
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetFrameStrata("HIGH")
    panel:SetFrameLevel(first:GetFrameLevel() > 1 and first:GetFrameLevel() - 1 or 1)
    panel:SetPoint("TOPLEFT", first, "TOPLEFT", -6, 6)
    panel:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", 6, -6)
    skin.Panel(panel)
    panel:Hide()

    first:SetScript("OnShow", function() panel:Show() end)
    first:SetScript("OnHide", function() panel:Hide() end)
    return panel
  end

  frame.menuSegment = MenuPanel(frame.btnCurrent, frame.btnOverall)
  frame.menuView = MenuPanel(frame.btnDamage, frame.btnHPS)

  for name in pairs(menubuttons) do
    local button = frame["btn" .. name]
    button:SetFrameLevel(frame.menuView:GetFrameLevel() + 2)
    skin.MenuEntry(button)
  end
end

-- the theme is known once the saved variables are loaded
window.ApplyTheme = function()
  if not ShaguDPS.classic then return end
  for i=1,10 do
    if window[i] then window.ApplyClassic(window[i]) end
  end
end

-- make sure to always create first window
window[1] = window[1] or CreateWindow(1)

-- update all available windows
window.Refresh = function(force, report)
  for i=1,10 do
    if config[i] then
      window[i] = window[i] or CreateWindow(i)
      window[i]:Refresh(force, report)
    end
  end
end

window.Refresh(true)
