-- Classic theme: the stock Blizzard look. Tooltip-style panels in a neutral
-- dark fill with the silver border, gold titles, drop-shadow text instead of
-- outlines, silver rules that fade out at the ends, quest-log hover glow and
-- the marbled dialog box with the gold header plate for the settings.

local skin = {}
ShaguDPS.skin = skin

skin.colors = {
  bg     = { 0.090, 0.085, 0.090 },
  border = { 0.900, 0.850, 0.900 },
  gold   = { 1, 0.82, 0 },
  white  = { 1, 1, 1 },
  rule   = { 0.8, 0.8, 0.8, 0.6 },
}

skin.backdrop_window = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

skin.backdrop_border = {
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

skin.backdrop_panel = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 }
}

skin.backdrop_dialog = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 }
}

-- stock font with the 1px drop shadow and no outline
skin.Font = function(fs, size)
  fs:SetFont(STANDARD_TEXT_FONT, size or 10, "")
  fs:SetShadowColor(0, 0, 0, 1)
  fs:SetShadowOffset(1, -1)
end

-- tooltip-style panel in the neutral dark fill
skin.Panel = function(frame, alpha)
  local c = skin.colors
  frame:SetBackdrop(skin.backdrop_panel)
  frame:SetBackdropColor(c.bg[1], c.bg[2], c.bg[3], alpha or 0.95)
  frame:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], 1)
end

-- a 1px silver line that fades out toward both ends
skin.Rule = function(parent)
  local c = skin.colors.rule
  local rule = CreateFrame("Frame", nil, parent)
  rule:SetHeight(1)

  local left = rule:CreateTexture(nil, "ARTWORK")
  left:SetTexture("Interface\\Buttons\\WHITE8X8")
  left:SetPoint("TOPLEFT", rule, "TOPLEFT", 0, 0)
  left:SetPoint("BOTTOMRIGHT", rule, "BOTTOM", 0, 0)
  left:SetGradientAlpha("HORIZONTAL", c[1], c[2], c[3], 0, c[1], c[2], c[3], c[4])

  local right = rule:CreateTexture(nil, "ARTWORK")
  right:SetTexture("Interface\\Buttons\\WHITE8X8")
  right:SetPoint("TOPLEFT", rule, "TOP", 0, 0)
  right:SetPoint("BOTTOMRIGHT", rule, "BOTTOMRIGHT", 0, 0)
  right:SetGradientAlpha("HORIZONTAL", c[1], c[2], c[3], c[4], c[1], c[2], c[3], 0)

  return rule
end

-- same line, but only fading out to the right ("Label ———")
skin.TrailingRule = function(parent)
  local c = skin.colors.rule
  local rule = CreateFrame("Frame", nil, parent)
  rule:SetHeight(1)

  local tex = rule:CreateTexture(nil, "ARTWORK")
  tex:SetTexture("Interface\\Buttons\\WHITE8X8")
  tex:SetAllPoints(rule)
  tex:SetGradientAlpha("HORIZONTAL", c[1], c[2], c[3], c[4], c[1], c[2], c[3], 0)

  return rule
end

-- quest-log style hover glow, hidden until shown
skin.Glow = function(parent, layer, alpha)
  local glow = parent:CreateTexture(nil, layer or "HIGHLIGHT")
  glow:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  glow:SetBlendMode("ADD")
  glow:SetAlpha(alpha or 0.5)
  glow:SetAllPoints(parent)
  return glow
end

-- gold title plate across the top edge of a dialog, like the stock option
-- windows. Three slices of the stock header art (left cap, middle, right cap)
-- so the middle stretches to fit the title without squashing the caps.
skin.HeaderPlate = function(frame, text)
  local file = "Interface\\DialogFrame\\UI-DialogBox-Header"

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetText(text)

  local mid = frame:CreateTexture(nil, "ARTWORK")
  mid:SetTexture(file)
  mid:SetTexCoord(0.31, 0.67, 0, 0.63)
  mid:SetHeight(40)
  mid:SetWidth(math.ceil(title:GetStringWidth() or 100) + 16)
  mid:SetPoint("TOP", frame, "TOP", 0, 12)

  local left = frame:CreateTexture(nil, "ARTWORK")
  left:SetTexture(file)
  left:SetTexCoord(0.21, 0.31, 0, 0.63)
  left:SetWidth(30)
  left:SetHeight(40)
  left:SetPoint("RIGHT", mid, "LEFT", 0, 0)

  local right = frame:CreateTexture(nil, "ARTWORK")
  right:SetTexture(file)
  right:SetTexCoord(0.67, 0.77, 0, 0.63)
  right:SetWidth(30)
  right:SetHeight(40)
  right:SetPoint("LEFT", mid, "RIGHT", 0, 0)

  title:SetPoint("TOP", mid, "TOP", 0, -14)
  return title
end

-- small icon button: gold icon that lights up white on hover, no box
skin.IconButton = function(button)
  local c = skin.colors.gold
  button:SetBackdrop(nil)
  if button.tex then
    button.tex:SetWidth(11)
    button.tex:SetHeight(11)
    button.tex:SetVertexColor(c[1], c[2], c[3])
  end

  button.hoverOn = function(self)
    if self.tex then self.tex:SetVertexColor(1, 1, 1) end
  end

  button.hoverOff = function(self)
    if self.tex then self.tex:SetVertexColor(c[1], c[2], c[3]) end
  end
end

-- text button: gold caption that turns white on hover, with the glow behind
skin.TextButton = function(button, size)
  local c = skin.colors.gold
  button:SetBackdrop(nil)
  skin.Font(button.caption, size or 10)
  button.caption:SetTextColor(c[1], c[2], c[3], 1)
  button.glow = button.glow or skin.Glow(button, "BACKGROUND", 0.35)
  button.glow:Hide()

  button.hoverOn = function(self)
    self.caption:SetTextColor(1, 1, 1, 1)
    self.glow:Show()
  end

  button.hoverOff = function(self)
    self.caption:SetTextColor(c[1], c[2], c[3], 1)
    self.glow:Hide()
  end
end

-- entry of a dropdown list: white caption (gold when selected), glow on hover
skin.MenuEntry = function(button)
  button:SetBackdrop(nil)
  skin.Font(button.caption, 10)
  button.glow = button.glow or skin.Glow(button, "BACKGROUND", 0.5)
  button.glow:Hide()

  button.hoverOn = function(self) self.glow:Show() end
  button.hoverOff = function(self) self.glow:Hide() end
end
