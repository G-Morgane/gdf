-- TankTarget : montre au groupe quel monstre le tank tient.
--
-- Un bouclier s'affiche au-dessus de la barre de nom (nameplate) du monstre
-- ciblé par le tank. Avec plusieurs tanks, chaque bouclier porte le numéro
-- du tank. En option : une pastille rouge sur les monstres qui tapent
-- quelqu'un d'autre que le tank, et le bouclier sur le cadre de cible.
--
-- Détection du tank, dans l'ordre :
--   1. rôle de groupe "TANK" (UnitGroupRolesAssigned) ;
--   2. Main Tank du raid (GetPartyAssignment) ;
--   3. choix manuel : /tank Nom (mémorisé dans TankTargetDB).
--
-- Sécurité : on ne touche à rien de protégé. On ajoute seulement un petit
-- cadre non sécurisé avec des textures sur les nameplates ennemies et sur
-- le cadre de cible. Toutes les API incertaines sur WoW Forever passent par
-- pcall. En combat, le moteur récent rend certaines réponses « secrètes » :
-- elles pilotent alors l'opacité des icônes via SetAlphaFromBoolean.
--
-- Lua 5.1 uniquement.

local ADDON = ...

local ICON = "Interface\\Icons\\INV_Shield_06"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local REFRESH = 0.25   -- rafraîchissement de fond (secondes)
local QUICK = 0.05     -- délai après un événement

local DEFAULTS = {
  manual = {},          -- noms choisis avec /tank Nom
  dot = true,           -- pastille rouge sur les monstres mal tenus
  targetFrame = true,   -- bouclier sur le cadre de cible
  size = 22,            -- taille du bouclier
  offsetY = 4,          -- décalage vertical au-dessus de la nameplate
}

local db                -- TankTargetDB une fois chargé
local tanks = {}        -- { {unit=, name=, source=}, ... }
local activePlates = {} -- unité de nameplate -> true
local widgets = {}      -- cadre de nameplate -> { holder, icon, label, dot }
local warned = {}

---------------------------------------------------------------------------
-- Utilitaires
---------------------------------------------------------------------------

local function Print(msg)
  local f = DEFAULT_CHAT_FRAME
  if f and f.AddMessage then
    f:AddMessage("|cff4fa3ffTankTarget|r : " .. tostring(msg))
  end
end

local function WarnOnce(key, msg)
  if warned[key] then return end
  warned[key] = true
  Print(msg)
end

local function IsSecret(v)
  if type(issecretvalue) == "function" then
    local ok, secret = pcall(issecretvalue, v)
    if ok and secret then return true end
  end
  return false
end

-- Appelle fn de façon protégée et renvoie sa première valeur, ou nil si la
-- fonction n'existe pas, plante, ou renvoie une valeur secrète.
local function Safe(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if not ok or IsSecret(v) then return nil end
  return v
end

-- Vrai seulement si l'appel renvoie une vraie valeur « vraie ».
local function Is(fn, ...)
  local v = Safe(fn, ...)
  if v then return true end
  return false
end

local function Trim(s)
  return (string.gsub(s or "", "^%s*(.-)%s*$", "%1"))
end

-- "Nom-Royaume" -> "nom"
local function NameKey(name)
  if type(name) ~= "string" then return nil end
  local short = string.match(name, "^([^%-]+)") or name
  return string.lower(short)
end

local function UnitShortName(unit)
  local n = Safe(UnitName, unit)
  if type(n) ~= "string" or n == "" then return nil end
  return n
end

local function TargetToken(unit)
  if unit == "player" then return "target" end
  return unit .. "target"
end

---------------------------------------------------------------------------
-- Groupe et tanks
---------------------------------------------------------------------------

local function InRaid()
  if type(IsInRaid) == "function" then
    return Is(IsInRaid)
  end
  local n = Safe(GetNumRaidMembers)
  return (n or 0) > 0
end

local function GroupUnits()
  local list = {}
  if InRaid() then
    local n = Safe(GetNumGroupMembers) or Safe(GetNumRaidMembers) or 0
    for i = 1, n do list[#list + 1] = "raid" .. i end
  else
    list[1] = "player"
    local n = Safe(GetNumSubgroupMembers) or Safe(GetNumPartyMembers) or 0
    for i = 1, n do list[#list + 1] = "party" .. i end
  end
  return list
end

local function FindTanks()
  local found = {}
  local units = GroupUnits()

  local function add(unit, source)
    if not Is(UnitExists, unit) then return end
    for _, t in ipairs(found) do
      if Is(UnitIsUnit, t.unit, unit) then return end
    end
    found[#found + 1] = { unit = unit, name = UnitShortName(unit) or unit, source = source }
  end

  -- 1. Rôle de groupe
  if type(UnitGroupRolesAssigned) == "function" then
    for _, u in ipairs(units) do
      if Safe(UnitGroupRolesAssigned, u) == "TANK" then add(u, "rôle") end
    end
  end

  -- 2. Main Tank du raid
  if #found == 0 and type(GetPartyAssignment) == "function" then
    for _, u in ipairs(units) do
      if Is(GetPartyAssignment, "MAINTANK", u) then add(u, "main tank") end
    end
  end

  -- 3. Choix manuel
  if #found == 0 and db and #db.manual > 0 then
    for _, wanted in ipairs(db.manual) do
      local key = NameKey(wanted)
      for _, u in ipairs(units) do
        if NameKey(UnitShortName(u)) == key then
          add(u, "manuel")
          break
        end
      end
    end
  end

  return found
end

---------------------------------------------------------------------------
-- Valeurs secrètes
---------------------------------------------------------------------------
-- Sur le moteur récent de WoW Forever, en combat, des réponses comme
-- UnitIsUnit("nameplate3", "party1target") peuvent être « secrètes » :
-- l'add-on ne peut pas les lire, mais il peut les passer à
-- SetAlphaFromBoolean, qui affiche ou masque l'élément tout seul.
-- On pilote donc tout par l'opacité : SetVis gère les deux cas.

local MAX_TANKS = 8

-- Appel protégé qui garde la valeur même si elle est secrète.
local function Raw(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if not ok then return nil end
  return v
end

-- Pareil, mais nil devient false. type() est sans danger sur une valeur
-- secrète, contrairement à « v or false » qui ferait un test dessus.
local function RawB(fn, ...)
  local v = Raw(fn, ...)
  if type(v) == "nil" then return false end
  return v
end

-- Opacité aTrue si v est vrai, aFalse sinon. Si v est secret et que le
-- client ne sait pas le traiter, l'élément est masqué (dans le doute, on
-- n'affiche rien).
local function SetVis(region, v, aTrue, aFalse)
  if IsSecret(v) then
    local ok = false
    if region.SetAlphaFromBoolean then
      ok = pcall(region.SetAlphaFromBoolean, region, v, aTrue, aFalse)
    end
    if not ok then region:SetAlpha(0) end
  elseif v then
    region:SetAlpha(aTrue)
  else
    region:SetAlpha(aFalse)
  end
end

local function ShowValue(v)
  if IsSecret(v) then return "secret" end
  return tostring(v)
end

---------------------------------------------------------------------------
-- Jeux d'icônes (un bouclier numéroté par tank, superposés)
---------------------------------------------------------------------------

local function NewShield(parent)
  local icon = parent:CreateTexture(nil, "OVERLAY")
  icon:SetTexture(ICON)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon:Hide()
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
  label:SetTextColor(1, 1, 1)
  label:Hide()
  return { icon = icon, label = label }
end

-- shields : liste de boucliers ; tests[i] = valeur « le tank i cible ça »
-- (nil pour ne pas afficher le bouclier i).
local function ApplyShields(shields, parent, tests, count, size, anchor, y)
  for i = 1, count do
    if not shields[i] then shields[i] = NewShield(parent) end
    local s = shields[i]
    s.icon:SetSize(size, size)
    s.icon:ClearAllPoints()
    s.icon:SetPoint("BOTTOM", anchor, "TOP", 0, y)
    if type(tests[i]) == "nil" then
      s.icon:Hide()
      s.label:Hide()
    else
      s.icon:Show()
      SetVis(s.icon, tests[i], 1, 0)
      if count > 1 then
        s.label:SetText(tostring(i))
        s.label:Show()
        SetVis(s.label, tests[i], 1, 0)
      else
        s.label:Hide()
      end
    end
  end
  for i = count + 1, #shields do
    shields[i].icon:Hide()
    shields[i].label:Hide()
  end
end

---------------------------------------------------------------------------
-- Nameplates
---------------------------------------------------------------------------

local function GetPlate(unit)
  if not C_NamePlate or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then
    return nil
  end
  local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
  if ok and type(plate) == "table" then return plate end
  return nil
end

local function GetWidgets(plate)
  local w = widgets[plate]
  if w then return w end

  local holder = CreateFrame("Frame", nil, plate)
  holder:SetAllPoints(plate)
  pcall(holder.SetFrameStrata, holder, "MEDIUM")
  pcall(holder.SetFrameLevel, holder, (plate:GetFrameLevel() or 0) + 50)

  -- Pastille : une chaîne de cadres imbriqués. L'opacité se multiplie de
  -- parent en enfant, donc la pastille n'est visible que si TOUTES les
  -- conditions (une par maillon) sont remplies, même secrètes.
  local dotRoot = CreateFrame("Frame", nil, holder)
  dotRoot:SetAllPoints(holder)
  local dot = dotRoot:CreateTexture(nil, "OVERLAY")
  dot:SetTexture(WHITE)
  dot:SetVertexColor(1, 0.1, 0.1, 1)
  dot:SetSize(8, 8)
  dot:SetPoint("BOTTOM", holder, "TOP", 0, 2)

  w = { holder = holder, shields = {}, dotRoot = dotRoot, chain = {}, dot = dot }
  widgets[plate] = w
  return w
end

local function HideWidgets(w)
  if not w then return end
  w.holder:Hide()
end

-- Renvoie le maillon n de la chaîne (le crée au besoin) et y range la pastille.
local function ChainLink(w, n)
  for k = #w.chain + 1, n do
    local parent = w.chain[k - 1] or w.dotRoot
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(w.holder)
    w.chain[k] = f
  end
  return w.chain[n]
end

-- conds = { {valeur, alphaSiVrai, alphaSiFaux}, ... }
local function ApplyDot(w, conds)
  local n = #conds
  if n == 0 then
    w.dotRoot:Hide()
    return
  end
  w.dotRoot:Show()
  for k = 1, n do
    local c = conds[k]
    SetVis(ChainLink(w, k), c[1], c[2], c[3])
  end
  for k = n + 1, #w.chain do w.chain[k]:SetAlpha(1) end
  local deepest = w.chain[#w.chain]
  if w.dot:GetParent() ~= deepest then w.dot:SetParent(deepest) end
  w.dot:Show()
end

local function UpdatePlate(unit)
  local plate = GetPlate(unit)
  if not plate then return end
  local w = GetWidgets(plate)

  if #tanks == 0 or not Is(UnitExists, unit) or not Is(UnitCanAttack, "player", unit) then
    HideWidgets(w)
    return
  end
  w.holder:Show()

  local count = math.min(#tanks, MAX_TANKS)
  local tests = {}
  for i = 1, count do
    tests[i] = RawB(UnitIsUnit, unit, TargetToken(tanks[i].unit))
  end
  local size = db and db.size or DEFAULTS.size
  local y = db and db.offsetY or DEFAULTS.offsetY
  ApplyShields(w.shields, w.holder, tests, count, size, w.holder, y)
  w.dot:ClearAllPoints()
  w.dot:SetPoint("BOTTOM", w.holder, "TOP", 0, y + size + 2)

  -- Pastille : en combat, cible amicale, et cette cible n'est aucun tank,
  -- et aucun tank n'a l'aggro d'après la menace.
  local conds = {}
  if db and db.dot then
    local mt = unit .. "target"
    conds[#conds + 1] = { RawB(UnitAffectingCombat, unit), 1, 0 }
    conds[#conds + 1] = { RawB(UnitExists, mt), 1, 0 }
    conds[#conds + 1] = { RawB(UnitIsFriend, "player", mt), 1, 0 }
    for i = 1, count do
      local t = tanks[i].unit
      conds[#conds + 1] = { RawB(UnitIsUnit, mt, t), 0, 1 }
      if type(UnitDetailedThreatSituation) == "function" then
        conds[#conds + 1] = { RawB(UnitDetailedThreatSituation, t, unit), 0, 1 }
      end
    end
  end
  ApplyDot(w, conds)
end

local function SafeUpdatePlate(unit)
  local ok, err = pcall(UpdatePlate, unit)
  if not ok then
    WarnOnce("plate", "erreur sur une barre de nom (signalée une seule fois) : " .. tostring(err))
  end
end

---------------------------------------------------------------------------
-- Cadre de cible
---------------------------------------------------------------------------

local targetHolder
local targetShields = {}

local function EnsureTargetHolder()
  if targetHolder then return true end
  local parent = _G.TargetFrame
  if not parent then return false end
  targetHolder = CreateFrame("Frame", nil, parent)
  targetHolder:SetSize(1, 1)
  pcall(targetHolder.SetFrameLevel, targetHolder, (parent:GetFrameLevel() or 0) + 10)
  local anchor = _G.TargetFramePortrait or parent
  targetHolder:SetPoint("BOTTOM", anchor, "TOP", 0, -4)
  return true
end

local function UpdateTargetFrame()
  if not EnsureTargetHolder() then return end
  local count = math.min(#tanks, MAX_TANKS)
  local tests = {}
  local active = db and db.targetFrame and Is(UnitExists, "target") and Is(UnitCanAttack, "player", "target")
  for i = 1, count do
    local t = tanks[i].unit
    -- Inutile d'afficher « ta cible est ta cible » quand on est le tank.
    if active and t ~= "player" and not Is(UnitIsUnit, t, "player") then
      tests[i] = RawB(UnitIsUnit, "target", TargetToken(t))
    else
      tests[i] = nil
    end
  end
  ApplyShields(targetShields, targetHolder, tests, count, 20, targetHolder, 0)
end

-- /tank debug : ce que voit l'add-on pour ta cible actuelle.
local function DebugTarget()
  Print("debug — SetAlphaFromBoolean : " .. tostring(UIParent.SetAlphaFromBoolean ~= nil)
    .. " | issecretvalue : " .. tostring(type(issecretvalue) == "function")
    .. " | C_NamePlate : " .. tostring(C_NamePlate ~= nil))
  if #tanks == 0 then
    Print("debug — aucun tank détecté.")
  end
  if not Is(UnitExists, "target") then
    Print("debug — pas de cible : cible un monstre (idéalement en combat) puis refais /tank debug.")
    return
  end
  Print("debug — cible en combat : " .. ShowValue(Raw(UnitAffectingCombat, "target"))
    .. " | sa cible existe : " .. ShowValue(Raw(UnitExists, "targettarget"))
    .. " | sa cible est amicale : " .. ShowValue(Raw(UnitIsFriend, "player", "targettarget")))
  for i, t in ipairs(tanks) do
    Print("debug — tank " .. i .. " " .. t.name .. " (" .. t.unit .. ") : le tank cible ça = "
      .. ShowValue(Raw(UnitIsUnit, "target", TargetToken(t.unit)))
      .. " | ça tape le tank = " .. ShowValue(Raw(UnitIsUnit, "targettarget", t.unit))
      .. " | aggro du tank = " .. ShowValue(Raw(UnitDetailedThreatSituation, t.unit, "target")))
  end
end

---------------------------------------------------------------------------
-- Rafraîchissement
---------------------------------------------------------------------------

local function RefreshAll()
  local ok, found = pcall(FindTanks)
  if ok then
    tanks = found
  else
    WarnOnce("tanks", "erreur pendant la détection du tank : " .. tostring(found))
    tanks = {}
  end
  for unit in pairs(activePlates) do SafeUpdatePlate(unit) end
  local ok2, err = pcall(UpdateTargetFrame)
  if not ok2 then
    WarnOnce("target", "erreur sur le cadre de cible : " .. tostring(err))
  end
end

local frame = CreateFrame("Frame")
local acc, dirty = 0, true

local function MarkDirty() dirty = true end

frame:SetScript("OnUpdate", function(self, elapsed)
  acc = acc + (elapsed or 0)
  if (dirty and acc >= QUICK) or acc >= REFRESH then
    acc = 0
    dirty = false
    RefreshAll()
  end
end)

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------

local EVENTS = {
  "ADDON_LOADED",
  "PLAYER_ENTERING_WORLD",
  "NAME_PLATE_UNIT_ADDED",
  "NAME_PLATE_UNIT_REMOVED",
  "UNIT_TARGET",
  "PLAYER_TARGET_CHANGED",
  "GROUP_ROSTER_UPDATE",
  "PLAYER_ROLES_ASSIGNED",
  "UNIT_THREAT_LIST_UPDATE",
  "UNIT_THREAT_SITUATION_UPDATE",
  -- Anciens noms (clients style 1.12), ignorés s'ils n'existent pas.
  "RAID_ROSTER_UPDATE",
  "PARTY_MEMBERS_CHANGED",
}

for _, ev in ipairs(EVENTS) do
  pcall(frame.RegisterEvent, frame, ev)
end

local function InitDB()
  if type(TankTargetDB) ~= "table" then TankTargetDB = {} end
  db = TankTargetDB
  for k, v in pairs(DEFAULTS) do
    if db[k] == nil then
      if type(v) == "table" then db[k] = {} else db[k] = v end
    end
  end
  if type(db.manual) ~= "table" then db.manual = {} end
end

frame:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then
      InitDB()
      if not C_NamePlate or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then
        Print("API des barres de nom absente sur ce client : seul le cadre de cible sera marqué.")
      end
    end
    return
  end

  if event == "NAME_PLATE_UNIT_ADDED" then
    if arg1 then
      activePlates[arg1] = true
      SafeUpdatePlate(arg1)
    end
    return
  end

  if event == "NAME_PLATE_UNIT_REMOVED" then
    if arg1 then
      activePlates[arg1] = nil
      local plate = GetPlate(arg1)
      if plate then HideWidgets(widgets[plate]) end
    end
    return
  end

  MarkDirty()
end)

---------------------------------------------------------------------------
-- Commande /tank
---------------------------------------------------------------------------

local function ShowStatus()
  if #tanks == 0 then
    Print("aucun tank détecté.")
  else
    local parts = {}
    for i, t in ipairs(tanks) do
      parts[#parts + 1] = i .. ". " .. t.name .. " (" .. t.source .. ")"
    end
    Print("tank(s) : " .. table.concat(parts, ", "))
  end
  if db and #db.manual > 0 then
    Print("choix manuel : " .. table.concat(db.manual, ", ")
      .. " (utilisé seulement si aucun rôle ni Main Tank n'est défini)")
  end
  Print("pastille rouge : " .. ((db and db.dot) and "oui" or "non")
    .. " | cadre de cible : " .. ((db and db.targetFrame) and "oui" or "non")
    .. " | taille " .. tostring(db and db.size) .. " | hauteur " .. tostring(db and db.offsetY))
end

local function ShowHelp()
  Print("commandes :")
  Print("  /tank : affiche le ou les tanks détectés")
  Print("  /tank Nom [Nom2 ...] : choisit le tank à la main")
  Print("  /tank moi | /tank cible : toi-même, ou le joueur que tu cibles")
  Print("  /tank effacer : oublie le choix manuel")
  Print("  /tank pastille | /tank cadre : active/désactive la pastille rouge ou l'icône du cadre de cible")
  Print("  /tank taille N | /tank hauteur N : taille et position du bouclier")
  Print("  /tank debug : ce que l'add-on voit pour ta cible (à faire en combat)")
end

local function HandleSlash(msg)
  if not db then InitDB() end
  msg = Trim(msg)
  local cmd, rest = string.match(msg, "^(%S*)%s*(.-)$")
  local lcmd = string.lower(cmd or "")

  if lcmd == "" then
    RefreshAll()
    ShowStatus()
    Print("tape /tank aide pour la liste des commandes.")
  elseif lcmd == "aide" or lcmd == "help" or lcmd == "?" then
    ShowHelp()
  elseif lcmd == "debug" then
    RefreshAll()
    DebugTarget()
  elseif lcmd == "effacer" or lcmd == "off" or lcmd == "reset" then
    db.manual = {}
    Print("choix manuel effacé.")
  elseif lcmd == "moi" then
    local n = UnitShortName("player")
    if n then
      db.manual = { n }
      Print("tank manuel : " .. n)
    end
  elseif lcmd == "cible" then
    local n = Is(UnitIsPlayer, "target") and UnitShortName("target") or nil
    if n then
      db.manual = { n }
      Print("tank manuel : " .. n)
    else
      Print("cible un joueur d'abord.")
    end
  elseif lcmd == "pastille" then
    db.dot = not db.dot
    Print("pastille rouge : " .. (db.dot and "activée" or "désactivée"))
  elseif lcmd == "cadre" then
    db.targetFrame = not db.targetFrame
    Print("icône du cadre de cible : " .. (db.targetFrame and "activée" or "désactivée"))
  elseif lcmd == "taille" then
    local n = tonumber(rest)
    if n and n >= 8 and n <= 64 then
      db.size = math.floor(n)
      Print("taille du bouclier : " .. db.size)
    else
      Print("usage : /tank taille 8-64 (actuelle : " .. tostring(db.size) .. ")")
    end
  elseif lcmd == "hauteur" then
    local n = tonumber(rest)
    if n and n >= -50 and n <= 150 then
      db.offsetY = math.floor(n)
      Print("hauteur du bouclier : " .. db.offsetY)
    else
      Print("usage : /tank hauteur -50 à 150 (actuelle : " .. tostring(db.offsetY) .. ")")
    end
  else
    local names = {}
    for word in string.gmatch(msg, "%S+") do
      local short = string.match(word, "^([^%-]+)") or word
      names[#names + 1] = short
    end
    db.manual = names
    Print("tank(s) manuel(s) : " .. table.concat(names, ", "))
  end
  MarkDirty()
end

SLASH_TANKTARGET1 = "/tank"
SLASH_TANKTARGET2 = "/tanktarget"
SlashCmdList["TANKTARGET"] = HandleSlash
