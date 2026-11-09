-- GuildScribe : collecte des infos de guilde pour WoW Forever.
--
-- Deux sources :
--   1. Le roster de guilde (tout le monde, même sans l'add-on) : nom, rang,
--      niveau, classe, zone, notes, dernière connexion...
--   2. Les membres qui ont l'add-on s'envoient leur fiche détaillée par canal
--      d'add-on (métiers, niveau d'objet, équipement, race...).
-- Tout est stocké dans GuildScribeDB (SavedVariables), lu ensuite par l'app.

local ADDON, ns = ...
local PREFIX = "GSCRIBE"
local PROTO = 1
local SCHEMA = 1

local frame = CreateFrame("Frame")
local db, guildKey
local lastBroadcast = 0
local pendingRoster = false

---------------------------------------------------------------------------
-- Utilitaires
---------------------------------------------------------------------------

local function print_(...)
  print("|cff33ccffGuildScribe|r:", ...)
end
ns.Print = print_

local function realmName()
  return (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName() or ""):gsub("%s", "")
end

local function fullName(name)
  if not name or name == "" then return nil end
  if name:find("-", 1, true) then return name end
  return name .. "-" .. realmName()
end

local function playerFullName()
  return fullName(UnitName("player"))
end

local function now() return time() end

local function after(sec, fn)
  if C_Timer and C_Timer.After then C_Timer.After(sec, fn) end
end

local function split(s, sep)
  local out = {}
  if not s or s == "" then return out end
  for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do
    out[#out + 1] = part
  end
  return out
end

-- Les champs envoyés ne doivent pas contenir nos séparateurs.
local function clean(s)
  return (tostring(s or ""):gsub("[|~;:,]", " "))
end

local function requestRoster()
  if C_GuildInfo and C_GuildInfo.GuildRoster then
    C_GuildInfo.GuildRoster()
  elseif GuildRoster then
    GuildRoster()
  end
end

local function sendAddon(msg)
  if not IsInGuild() then return end
  local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  if send then send(PREFIX, msg, "GUILD") end
end

---------------------------------------------------------------------------
-- Base de données
---------------------------------------------------------------------------

local function guildDB()
  if not IsInGuild() then return nil end
  local gName = GetGuildInfo("player")
  if not gName then return nil end
  guildKey = gName .. "-" .. realmName()
  db.guilds[guildKey] = db.guilds[guildKey] or { members = {} }
  local g = db.guilds[guildKey]
  g.name = gName
  g.realm = realmName()
  g.members = g.members or {}
  return g
end
ns.GuildDB = guildDB

local function memberRecord(g, name)
  g.members[name] = g.members[name] or {}
  return g.members[name]
end

---------------------------------------------------------------------------
-- 1. Scan du roster
---------------------------------------------------------------------------

local function scanRoster()
  local g = guildDB()
  if not g then return end

  local canOfficer = C_GuildInfo and C_GuildInfo.CanViewOfficerNote and C_GuildInfo.CanViewOfficerNote()
  local total, online = GetNumGuildMembers()
  local seen = {}

  for i = 1, total do
    local name, rankName, rankIndex, level, classDisplayName, zone, publicNote, officerNote,
          isOnline, status, classFile, achievementPoints, _, isMobile, _, repStanding, guid =
          GetGuildRosterInfo(i)
    if name then
      name = fullName(name)
      seen[name] = true
      local m = memberRecord(g, name)
      m.name = name
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
      m.guildRep = repStanding

      if isOnline then
        m.lastOnline = now()
      elseif GetGuildRosterLastOnline then
        local y, mo, d, h = GetGuildRosterLastOnline(i)
        if y then
          -- Approximation : 1 an = 365 j, 1 mois = 30 j.
          local hoursAgo = (((y or 0) * 365 + (mo or 0) * 30 + (d or 0)) * 24) + (h or 0)
          m.lastOnline = now() - hoursAgo * 3600
        end
      end
      m.inGuild = true
      m.rosterSeenAt = now()
    end
  end

  -- Les anciens membres sont gardés mais marqués comme partis.
  for name, m in pairs(g.members) do
    if not seen[name] and m.inGuild then
      m.inGuild = false
      m.leftAt = now()
    end
  end

  g.info = g.info or {}
  g.info.motd = GetGuildRosterMOTD and GetGuildRosterMOTD() or nil
  g.info.text = GetGuildInfoText and GetGuildInfoText() or nil
  g.info.numMembers = total
  g.info.numOnline = online
  g.ranks = {}
  if GuildControlGetNumRanks then
    for r = 1, GuildControlGetNumRanks() do
      g.ranks[r] = GuildControlGetRankName(r)
    end
  end
  g.scannedAt = now()
  g.scannedBy = playerFullName()
end

---------------------------------------------------------------------------
-- 1b. Annuaire des métiers de guilde (si l'API existe sur ce client)
---------------------------------------------------------------------------

local function scanGuildTradeSkills()
  local g = guildDB()
  if not g or not GetNumGuildTradeSkill or not GetGuildTradeSkillInfo then return end

  -- On déplie toutes les catégories pour voir tous les artisans.
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
      local m = memberRecord(g, fullName(playerFullName_ or playerName))
      m.guildProfessions = m.guildProfessions or {}
      m.guildProfessions[tostring(currentSkillID)] = { id = currentSkillID, name = currentName, skill = skill, seenAt = now() }
    end
  end
end

---------------------------------------------------------------------------
-- 2. Fiche du joueur local
---------------------------------------------------------------------------

local SLOTS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }

local function collectProfessions()
  local profs = {}
  if GetProfessions and GetProfessionInfo then
    local list = { GetProfessions() }
    for _, idx in pairs(list) do
      if idx then
        local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(idx)
        if name then
          profs[#profs + 1] = { id = skillLine or 0, name = name, skill = rank or 0, max = maxRank or 0 }
        end
      end
    end
  elseif GetNumSkillLines and GetSkillLineInfo then
    -- Repli style Classic : on lit la liste des compétences.
    local section
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
      if isHeader then
        section = name
      elseif section == (TRADE_SKILLS or "Professions") or section == (SECONDARY_SKILLS or "Secondary Skills") then
        profs[#profs + 1] = { id = 0, name = name, skill = rank or 0, max = maxRank or 0 }
      end
    end
  end
  return profs
end

local function collectGear()
  local gear = {}
  for _, slot in ipairs(SLOTS) do
    local id = GetInventoryItemID("player", slot)
    gear[#gear + 1] = id or 0
  end
  return gear
end

local function collectSelf()
  local _, race = UnitRace("player")
  local _, classFile = UnitClass("player")
  local _, ilvlEquipped
  if GetAverageItemLevel then _, ilvlEquipped = GetAverageItemLevel() end
  local spec
  if GetSpecialization and GetSpecializationInfo then
    local s = GetSpecialization()
    if s then spec = select(2, GetSpecializationInfo(s)) end
  end
  local faction = UnitFactionGroup("player")
  return {
    name = playerFullName(),
    level = UnitLevel("player"),
    race = race,
    class = classFile,
    sex = UnitSex("player"),
    faction = faction,
    ilvl = ilvlEquipped and math.floor(ilvlEquipped * 10 + 0.5) / 10 or nil,
    spec = spec,
    professions = collectProfessions(),
    gear = collectGear(),
    addonVersion = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or nil,
  }
end

local function applyProfile(name, p)
  local g = guildDB()
  if not g then return end
  local m = memberRecord(g, name)
  m.name = name
  m.profile = p
  m.profileAt = now()
end

---------------------------------------------------------------------------
-- 3. Protocole d'échange entre add-ons
--   P~proto~level~race~class~sex~faction~ilvl~spec~version
--   R~proto~id:nom:skill:max;id:nom:skill:max
--   G~proto~id,id,id,... (19 emplacements)
--   Q~proto            (demande : tout le monde renvoie sa fiche)
---------------------------------------------------------------------------

local function broadcastSelf(force)
  if not IsInGuild() then return end
  if not force and now() - lastBroadcast < 30 then return end
  lastBroadcast = now()

  local p = collectSelf()
  applyProfile(p.name, p)

  sendAddon(table.concat({ "P", PROTO, p.level or "", clean(p.race), clean(p.class), p.sex or "",
    clean(p.faction), p.ilvl or "", clean(p.spec), clean(p.addonVersion) }, "~"))

  local pr = {}
  for _, x in ipairs(p.professions) do
    pr[#pr + 1] = table.concat({ x.id, clean(x.name), x.skill, x.max }, ":")
  end
  sendAddon("R~" .. PROTO .. "~" .. table.concat(pr, ";"))
  sendAddon("G~" .. PROTO .. "~" .. table.concat(p.gear, ","))
end
ns.BroadcastSelf = broadcastSelf

local function onAddonMessage(prefix, msg, channel, sender)
  if prefix ~= PREFIX or channel ~= "GUILD" then return end
  sender = fullName(sender)
  local parts = split(msg, "~")
  local kind, proto = parts[1], tonumber(parts[2])
  if not proto or proto > PROTO then return end

  if kind == "Q" then
    if sender ~= playerFullName() then
      -- Délai aléatoire pour ne pas que toute la guilde réponde en même temps.
      after(1 + math.random() * 8, function() broadcastSelf(true) end)
    end
    return
  end
  if sender == playerFullName() then return end

  local g = guildDB()
  if not g then return end
  local m = memberRecord(g, sender)
  m.name = sender
  m.profile = m.profile or {}
  local p = m.profile

  if kind == "P" then
    p.name = sender
    p.level = tonumber(parts[3])
    p.race = parts[4]
    p.class = parts[5]
    p.sex = tonumber(parts[6])
    p.faction = parts[7]
    p.ilvl = tonumber(parts[8])
    p.spec = parts[9] ~= "" and parts[9] or nil
    p.addonVersion = parts[10]
  elseif kind == "R" then
    p.professions = {}
    for _, entry in ipairs(split(parts[3] or "", ";")) do
      local f = split(entry, ":")
      if f[2] then
        p.professions[#p.professions + 1] = { id = tonumber(f[1]) or 0, name = f[2], skill = tonumber(f[3]) or 0, max = tonumber(f[4]) or 0 }
      end
    end
  elseif kind == "G" then
    p.gear = {}
    for _, id in ipairs(split(parts[3] or "", ",")) do
      p.gear[#p.gear + 1] = tonumber(id) or 0
    end
  end
  m.profileAt = now()
end

local function requestAll()
  sendAddon("Q~" .. PROTO)
  broadcastSelf(true)
end
ns.RequestAll = requestAll

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------

local function scheduleRosterScan()
  if pendingRoster then return end
  pendingRoster = true
  after(2, function()
    pendingRoster = false
    scanRoster()
    scanGuildTradeSkills()
  end)
end
ns.ScanNow = function()
  requestRoster()
  if QueryGuildRecipes then QueryGuildRecipes() end
  scanRoster()
  scanGuildTradeSkills()
end

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    GuildScribeDB = GuildScribeDB or {}
    db = GuildScribeDB
    db.schema = SCHEMA
    db.guilds = db.guilds or {}
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
      C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    local isLogin, isReload = ...
    if isLogin or isReload then
      after(8, function()
        if not IsInGuild() then return end
        ns.ScanNow()
        broadcastSelf(true)
      end)
    end
  elseif event == "GUILD_ROSTER_UPDATE" or event == "GUILD_TRADESKILL_UPDATE" then
    scheduleRosterScan()
  elseif event == "CHAT_MSG_ADDON" then
    onAddonMessage(...)
  elseif event == "PLAYER_LEVEL_UP" or event == "SKILL_LINES_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then
    after(3, function() broadcastSelf(false) end)
  elseif event == "PLAYER_LOGOUT" then
    if IsInGuild() then
      local p = collectSelf()
      applyProfile(p.name, p)
    end
  end
end)

for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "GUILD_ROSTER_UPDATE", "CHAT_MSG_ADDON",
  "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LOGOUT" }) do
  frame:RegisterEvent(e)
end
-- Cet événement n'existe peut-être pas sur tous les clients.
pcall(frame.RegisterEvent, frame, "GUILD_TRADESKILL_UPDATE")
