-- GuildScribe : collecte des infos de guilde pour WoW Forever.
--
-- Trois sources :
--   1. Le roster de guilde (tout le monde, même sans l'add-on) : nom, rang,
--      niveau, classe, zone, notes, dernière connexion... (Core.lua)
--   2. La fiche détaillée du joueur, découpée en sections horodatées :
--      équipement, talents, métiers, recettes, stats, réputations... (Collect.lua)
--   3. Les fiches des autres membres qui ont l'add-on, reçues par le canal
--      caché de la guilde (Comm.lua).
-- Tout est stocké dans GuildScribeDB (SavedVariables), lu ensuite par l'uploader.

local ADDON, ns = ...
local SCHEMA = 2

ns.ADDON = ADDON
ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
  or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "?"

---------------------------------------------------------------------------
-- Utilitaires
---------------------------------------------------------------------------

function ns.Print(...)
  print("|cff33ccffGuildScribe|r:", ...)
end

function ns.Now() return time() end

function ns.After(sec, fn)
  if C_Timer and C_Timer.After then C_Timer.After(sec, fn) end
end

-- Appel protégé : renvoie les résultats, ou rien si la fonction n'existe pas
-- sur ce client ou plante. Toute la collecte passe par là.
function ns.Safe(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  return unpack(r, 2, table.maxn(r))
end

local debounces = {}
function ns.Debounce(key, sec, fn)
  if debounces[key] then return end
  debounces[key] = true
  ns.After(sec, function()
    debounces[key] = nil
    local ok, err = pcall(fn)
    if not ok and ns.debug then ns.Print("erreur", key, err) end
  end)
end

function ns.Split(s, sep)
  local out = {}
  if not s or s == "" then return out end
  for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do
    out[#out + 1] = part
  end
  return out
end

-- Hash court et stable d'une chaîne (pour savoir si une section a changé).
function ns.Hash(s)
  local h = 5381
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 2147483648 -- reste sous 2^31 pour string.format
  end
  return string.format("%08x", h)
end

function ns.RealmName()
  return (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName() or ""):gsub("%s", "")
end

function ns.FullName(name)
  if not name or name == "" then return nil end
  if name:find("-", 1, true) then return name end
  return name .. "-" .. ns.RealmName()
end

function ns.PlayerName()
  return ns.FullName(UnitName("player"))
end

-- Compare deux versions "1.2.3" : renvoie true si a > b.
function ns.NewerVersion(a, b)
  local pa, pb = ns.Split(a or "", "."), ns.Split(b or "", ".")
  for i = 1, math.max(#pa, #pb) do
    local x, y = tonumber(pa[i]) or 0, tonumber(pb[i]) or 0
    if x ~= y then return x > y end
  end
  return false
end

---------------------------------------------------------------------------
-- Événements : chaque fichier s'abonne avec ns.On(événement, fonction).
-- Les événements absents de ce client sont ignorés sans erreur.
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    pcall(frame.RegisterEvent, frame, event)
  end
  table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(handlers[event] or {}) do
    local ok, err = pcall(fn, ...)
    if not ok and ns.debug then ns.Print("erreur", event, err) end
  end
end)

---------------------------------------------------------------------------
-- Base de données
---------------------------------------------------------------------------

local db

function ns.DB() return db end

function ns.GuildDB()
  if not db or not IsInGuild() then return nil end
  local gName = GetGuildInfo("player")
  if not gName then return nil end
  local key = gName .. "-" .. ns.RealmName()
  db.guilds[key] = db.guilds[key] or { members = {} }
  local g = db.guilds[key]
  g.name = gName
  g.realm = ns.RealmName()
  g.members = g.members or {}
  g.info = g.info or {}
  return g
end

function ns.Member(g, name)
  g.members[name] = g.members[name] or {}
  local m = g.members[name]
  m.name = name
  return m
end

-- Fiche du joueur local (dans la guilde courante).
function ns.SelfRecord()
  local g = ns.GuildDB()
  if not g then return nil end
  local m = ns.Member(g, ns.PlayerName())
  m.profile = m.profile or {}
  m.hashes = m.hashes or {}
  return m, g
end

-- Le joueur collecte-t-il les fiches des autres ? Oui pour les officiers
-- (ils ont l'uploader), ou si activé avec /gs collecteur.
function ns.IsCollector()
  if db and db.collector ~= nil then return db.collector end
  return (C_GuildInfo and C_GuildInfo.CanViewOfficerNote and C_GuildInfo.CanViewOfficerNote())
    or (CanViewOfficerNote and CanViewOfficerNote()) or false
end

ns.On("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  GuildScribeDB = GuildScribeDB or {}
  db = GuildScribeDB
  db.schema = SCHEMA
  db.guilds = db.guilds or {}
  db.addonVersion = ns.VERSION
end)

---------------------------------------------------------------------------
-- 1. Scan du roster
---------------------------------------------------------------------------

local function requestRoster()
  if C_GuildInfo and C_GuildInfo.GuildRoster then
    C_GuildInfo.GuildRoster()
  elseif GuildRoster then
    GuildRoster()
  end
end

local function scanRoster()
  local g = ns.GuildDB()
  if not g then return end

  local canOfficer = (C_GuildInfo and C_GuildInfo.CanViewOfficerNote and C_GuildInfo.CanViewOfficerNote())
    or (CanViewOfficerNote and CanViewOfficerNote())
  local total, online = GetNumGuildMembers()
  local seen = {}
  local now = ns.Now()

  for i = 1, total or 0 do
    local name, rankName, rankIndex, level, classDisplayName, zone, publicNote, officerNote,
          isOnline, status, classFile, achievementPoints, achievementRank, isMobile, _, repStanding, guid =
          GetGuildRosterInfo(i)
    if name then
      name = ns.FullName(name)
      seen[name] = true
      local m = ns.Member(g, name)
      m.guid = guid
      m.rank = rankName
      m.rankIndex = rankIndex
      m.level = level
      m.class = classFile
      m.classLocalized = classDisplayName
      m.zone = zone
      m.publicNote = publicNote
      if canOfficer then m.officerNote = officerNote end
      m.online = isOnline and true or false
      m.mobile = isMobile and true or false
      m.status = status
      m.achievementPoints = achievementPoints
      m.achievementRank = achievementRank
      m.guildRep = repStanding

      if isOnline then
        m.lastOnline = now
      elseif GetGuildRosterLastOnline then
        local y, mo, d, h = GetGuildRosterLastOnline(i)
        if y then
          -- Approximation : 1 an = 365 j, 1 mois = 30 j.
          local hoursAgo = (((y or 0) * 365 + (mo or 0) * 30 + (d or 0)) * 24) + (h or 0)
          m.lastOnline = now - hoursAgo * 3600
        end
      end
      m.inGuild = true
      m.leftAt = nil
      m.rosterSeenAt = now
    end
  end

  -- Les anciens membres sont gardés mais marqués comme partis.
  for name, m in pairs(g.members) do
    if not seen[name] and m.inGuild then
      m.inGuild = false
      m.leftAt = now
    end
  end

  g.info.motd = ns.Safe(GetGuildRosterMOTD)
  g.info.text = ns.Safe(GetGuildInfoText)
  g.info.numMembers = total
  g.info.numOnline = online
  local _, _, _, guildRealm = ns.Safe(GetGuildInfo, "player")
  g.info.guildRealm = guildRealm
  local fName, _, standingID, barMin, barMax, barValue = ns.Safe(GetGuildFactionInfo)
  if fName then g.info.reputation = { at = now, standing = standingID, value = barValue, min = barMin, max = barMax } end
  g.ranks = {}
  if GuildControlGetNumRanks then
    for r = 1, GuildControlGetNumRanks() do
      g.ranks[r] = GuildControlGetRankName(r)
    end
  end
  g.scannedAt = now
  g.scannedBy = ns.PlayerName()
end

---------------------------------------------------------------------------
-- 1b. Annuaire des métiers de guilde (si l'API existe sur ce client)
---------------------------------------------------------------------------

local function scanGuildTradeSkills()
  local g = ns.GuildDB()
  if not g or not GetNumGuildTradeSkill or not GetGuildTradeSkillInfo then return end

  if ExpandGuildTradeSkillHeader then
    for i = 1, GetNumGuildTradeSkill() do
      local skillID, isCollapsed, _, headerName = GetGuildTradeSkillInfo(i)
      if headerName and isCollapsed then ExpandGuildTradeSkillHeader(skillID) end
    end
  end

  local currentSkillID, currentName
  for i = 1, GetNumGuildTradeSkill() do
    local skillID, _, _, headerName, _, _, _, playerName, playerFullName_, _, _, _, skill =
      GetGuildTradeSkillInfo(i)
    if headerName then
      currentSkillID, currentName = skillID, headerName
    elseif currentSkillID and (playerFullName_ or playerName) then
      local m = ns.Member(g, ns.FullName(playerFullName_ or playerName))
      m.guildProfessions = m.guildProfessions or {}
      m.guildProfessions[tostring(currentSkillID)] = { id = currentSkillID, name = currentName, skill = skill, seenAt = ns.Now() }
    end
  end
end

---------------------------------------------------------------------------
-- 1c. Banque de guilde (si ce client en a une) : lue quand on l'ouvre.
---------------------------------------------------------------------------

local function itemIdFromLink(link)
  return link and tonumber(link:match("item:(%d+)"))
end
ns.ItemIdFromLink = itemIdFromLink

local function scanGuildBank()
  local g = ns.GuildDB()
  if not g or not GetNumGuildBankTabs then return end
  local bank = { at = ns.Now(), money = ns.Safe(GetGuildBankMoney), tabs = {} }
  local perTab = MAX_GUILDBANK_SLOTS_PER_TAB or 98
  for tab = 1, GetNumGuildBankTabs() or 0 do
    local name, icon, isViewable = ns.Safe(GetGuildBankTabInfo, tab)
    local t = { name = name, viewable = isViewable and true or false, items = {} }
    if isViewable then
      local counts = {}
      for slot = 1, perTab do
        local link = ns.Safe(GetGuildBankItemLink, tab, slot)
        local id = itemIdFromLink(link)
        if id then
          local _, count = ns.Safe(GetGuildBankItemInfo, tab, slot)
          if not counts[id] then
            counts[id] = { i = id, c = 0, n = link:match("%[(.-)%]") }
            t.items[#t.items + 1] = counts[id]
          end
          counts[id].c = counts[id].c + (count or 1)
        end
      end
    end
    bank.tabs[#bank.tabs + 1] = t
  end
  g.info.bank = bank
end

ns.On("GUILDBANKFRAME_OPENED", function()
  if GetNumGuildBankTabs and QueryGuildBankTab then
    for tab = 1, GetNumGuildBankTabs() or 0 do ns.Safe(QueryGuildBankTab, tab) end
  end
  ns.Debounce("gbank", 2, scanGuildBank)
end)
ns.On("GUILDBANKBAGSLOTS_CHANGED", function() ns.Debounce("gbank", 2, scanGuildBank) end)

---------------------------------------------------------------------------
-- Planification
---------------------------------------------------------------------------

function ns.ScanNow()
  requestRoster()
  if QueryGuildRecipes then ns.Safe(QueryGuildRecipes) end
  scanRoster()
  scanGuildTradeSkills()
end

ns.On("GUILD_ROSTER_UPDATE", function()
  ns.Debounce("roster", 2, function() scanRoster() scanGuildTradeSkills() end)
end)
ns.On("GUILD_TRADESKILL_UPDATE", function()
  ns.Debounce("roster", 2, function() scanRoster() scanGuildTradeSkills() end)
end)
ns.On("PLAYER_GUILD_UPDATE", function()
  ns.Debounce("roster", 2, function() scanRoster() end)
end)
