-- Commandes /gs et fenêtre d'export JSON (copier-coller vers l'app).
local _, ns = ...

local exportFrame

local function showExport(text)
  if not exportFrame then
    local f = CreateFrame("Frame", "GuildScribeExportFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(620, 440)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOP", 0, -5)
    f.title:SetText("GuildScribe – Ctrl+A puis Ctrl+C pour copier")

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetMaxLetters(0)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(560)
    edit:SetAutoFocus(true)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(edit)

    f.edit = edit
    exportFrame = f
  end
  exportFrame.edit:SetText(text)
  exportFrame.edit:HighlightText()
  exportFrame:Show()
  exportFrame.edit:SetFocus()
end

local function countMembers(g)
  local total, withAddon = 0, 0
  for _, m in pairs(g.members) do
    if m.inGuild then
      total = total + 1
      if m.profile and m.profile.level then withAddon = withAddon + 1 end
    end
  end
  return total, withAddon
end

SLASH_GUILDSCRIBE1 = "/gs"
SLASH_GUILDSCRIBE2 = "/guildscribe"
SlashCmdList.GUILDSCRIBE = function(msg)
  local cmd = (msg or ""):lower():match("^%s*(%S*)")
  local g = ns.GuildDB()

  if cmd == "scan" then
    if not g then return ns.Print("tu n'es pas dans une guilde.") end
    ns.ScanNow()
    local total, withAddon = countMembers(g)
    ns.Print(("roster scanné : %d membres, %d fiches détaillées."):format(total, withAddon))
  elseif cmd == "sync" then
    if not g then return ns.Print("tu n'es pas dans une guilde.") end
    ns.RequestAll()
    ns.Print("demande envoyée : les membres avec l'add-on vont renvoyer leur fiche dans les prochaines secondes.")
  elseif cmd == "export" then
    if not g then return ns.Print("tu n'es pas dans une guilde.") end
    ns.ScanNow()
    showExport(ns.ToJSON({ schema = GuildScribeDB.schema, exportedAt = time(), guild = g }))
  elseif cmd == "stats" then
    if not g then return ns.Print("tu n'es pas dans une guilde.") end
    local total, withAddon = countMembers(g)
    ns.Print(("%s : %d membres, %d avec l'add-on. Dernier scan : %s."):format(
      g.name, total, withAddon, g.scannedAt and date("%d/%m %H:%M", g.scannedAt) or "jamais"))
  else
    ns.Print("commandes :")
    print("  /gs scan   – relire le roster de guilde")
    print("  /gs sync   – demander leur fiche aux membres qui ont l'add-on")
    print("  /gs stats  – résumé")
    print("  /gs export – afficher le JSON à copier")
  end
end
