-- Fiche détaillée du joueur, découpée en sections.
--
-- Chaque section est un tableau avec un champ "at" (date du dernier
-- changement). Le site garde toujours la version la plus récente de chaque
-- section, quelle que soit la personne qui l'a envoyée.
--
-- share = true : envoyée aussi aux autres membres par le canal de guilde
-- (pour les officiers qui ont l'uploader). Les sections non partagées
-- (sacs, banque, quêtes...) partent seulement avec l'uploader du joueur.
--
-- Chaque appel au jeu passe par ns.Safe : si une fonction n'existe pas sur
-- WoW Forever, la donnée est simplement absente, sans erreur.

local _, ns = ...
local Safe = ns.Safe

local function round(v, d)
  if type(v) ~= "number" then return nil end
  local m = 10 ^ (d or 2)
  return math.floor(v * m + 0.5) / m
end

local function linkName(link) return link and link:match("%[(.-)%]") end
local function linkString(link) return link and link:match("|H(item:[^|]+)|h") end

local function itemLevel(link)
  if not link then return nil end
  local l = Safe(GetDetailedItemLevelInfo, link)
  if l then return l end
  if C_Item and C_Item.GetDetailedItemLevelInfo then
    l = Safe(C_Item.GetDetailedItemLevelInfo, link)
    if l then return l end
  end
  return (select(4, Safe(GetItemInfo, link)))
end

local function itemQuality(link)
  local q = select(3, Safe(GetItemInfo, link))
  return q
end

---------------------------------------------------------------------------
-- Infobulle d'un objet, lue ligne par ligne dans une infobulle invisible :
-- c'est exactement ce que le joueur voit en jeu (stats, effets, bonus de
-- set...), y compris pour les objets propres à WoW Forever.
---------------------------------------------------------------------------

local tip
local durabilityPattern = "^" .. (DURABILITY_TEMPLATE or "Durability %d / %d"):gsub("%%d", "%%d+") .. "$"

local function cleanText(s)
  if not s then return nil end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

-- setter : nom de la méthode de GameTooltip (SetInventoryItem, SetBagItem...).
local function readTooltip(setter, ...)
  if not tip then
    tip = CreateFrame("GameTooltip", "GuildScribeTip", nil, "GameTooltipTemplate")
  end
  if not tip[setter] then return nil end
  tip:SetOwner(WorldFrame, "ANCHOR_NONE")
  tip:ClearLines()
  if not pcall(tip[setter], tip, ...) then tip:Hide() return nil end
  local lines = {}
  for i = 2, math.min(tip:NumLines() or 0, 40) do
    local L, R = _G["GuildScribeTipTextLeft" .. i], _G["GuildScribeTipTextRight" .. i]
    local lt = L and cleanText(L:GetText())
    if lt and lt ~= "" and not lt:match(durabilityPattern) then
      local e = { t = lt }
      local rt = R and R:IsShown() and cleanText(R:GetText())
      if rt and rt ~= "" then e.r = rt end
      local r, g, b = L:GetTextColor()
      if r then
        local hex = string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
        if hex ~= "ffffff" then e.c = hex end
      end
      lines[#lines + 1] = e
    end
  end
  tip:Hide()
  return #lines > 0 and lines or nil
end
ns.ReadTooltip = readTooltip

---------------------------------------------------------------------------
-- Collecteurs
---------------------------------------------------------------------------

local C = {}

function C.core()
  local _, race = Safe(UnitRace, "player")
  local _, classFile = Safe(UnitClass, "player")
  local _, ilvlEquipped = Safe(GetAverageItemLevel)
  local spec, specRole
  local s = Safe(GetSpecialization)
  if s then
    local _, name, _, _, role = Safe(GetSpecializationInfo, s)
    spec, specRole = name, role
  end
  local gName, gRank, gRankIndex = Safe(GetGuildInfo, "player")
  local version, build, buildDate, toc = Safe(GetBuildInfo)
  local title
  local titleId = Safe(GetCurrentTitle)
  if titleId and titleId > 0 then title = Safe(GetTitleName, titleId) end
  return {
    level = Safe(UnitLevel, "player"),
    race = race,
    raceLocalized = (Safe(UnitRace, "player")),
    class = classFile,
    classLocalized = (Safe(UnitClass, "player")),
    sex = Safe(UnitSex, "player"),
    faction = (Safe(UnitFactionGroup, "player")),
    ilvl = round(ilvlEquipped, 1),
    spec = spec,
    specRole = specRole,
    xp = Safe(UnitXP, "player"),
    xpMax = Safe(UnitXPMax, "player"),
    rested = Safe(GetXPExhaustion),
    guildRank = gRank,
    guildRankIndex = gRankIndex,
    title = title and title:gsub("^%s+", ""):gsub("%s+$", "") or nil,
    bind = Safe(GetBindLocation),
    achievementPoints = Safe(GetTotalAchievementPoints),
    hardcore = (C_GameRules and C_GameRules.IsHardcoreActive and Safe(C_GameRules.IsHardcoreActive)) or nil,
    client = { version = version, build = build, toc = toc },
  }
end

-- Emplacements 0 (munitions) à 19.
function C.gear()
  local items = {}
  for slot = 0, 19 do
    local link = Safe(GetInventoryItemLink, "player", slot)
    local id = ns.ItemIdFromLink(link) or Safe(GetInventoryItemID, "player", slot)
    if id then
      local str = linkString(link)
      local f = str and ns.Split(str, ":") or {}
      local gems = {}
      for k = 4, 7 do
        local gem = tonumber(f[k])
        if gem and gem > 0 then gems[#gems + 1] = gem end
      end
      items[#items + 1] = {
        slot = slot,
        id = id,
        n = linkName(link),
        s = str,
        q = itemQuality(link or id),
        l = itemLevel(link),
        e = tonumber(f[3]) ~= 0 and tonumber(f[3]) or nil,   -- enchantement
        gems = #gems > 0 and gems or nil,
        sfx = tonumber(f[8]) ~= 0 and tonumber(f[8]) or nil,  -- suffixe ("de l'aigle"...)
        tt = readTooltip("SetInventoryItem", "player", slot),
      }
    end
  end
  return { items = items }
end

function C.talents()
  local tabs = {}
  for t = 1, Safe(GetNumTalentTabs) or 0 do
    local info = { Safe(GetTalentTabInfo, t) }
    local tabName
    for i = 1, table.maxn(info) do
      if type(info[i]) == "string" then tabName = info[i] break end
    end
    local list, points = {}, 0
    for i = 1, Safe(GetNumTalents, t) or 0 do
      local r = { Safe(GetTalentInfo, t, i) }
      if type(r[1]) == "number" and type(r[2]) == "string" then table.remove(r, 1) end
      local name, _, tier, col, rank, maxRank = r[1], r[2], r[3], r[4], r[5], r[6]
      if type(name) == "string" and type(rank) == "number" and rank > 0 then
        list[#list + 1] = { n = name, r = rank, m = maxRank, t = tier, c = col }
        points = points + rank
      end
    end
    tabs[#tabs + 1] = { n = tabName, p = points, list = list }
  end
  if #tabs == 0 then return nil end
  return {
    tabs = tabs,
    group = Safe(GetActiveTalentGroup),
    groups = Safe(GetNumTalentGroups),
    unspent = Safe(UnitCharacterPoints, "player"),
  }
end

function C.professions()
  local list = {}
  if GetProfessions and GetProfessionInfo then
    for _, idx in pairs({ Safe(GetProfessions) }) do
      if idx then
        local name, _, rank, maxRank, _, _, skillLine = Safe(GetProfessionInfo, idx)
        if name then list[#list + 1] = { id = skillLine or 0, name = name, skill = rank or 0, max = maxRank or 0 } end
      end
    end
  elseif GetNumSkillLines and GetSkillLineInfo then
    -- Style Classic : on lit la liste des compétences.
    local section
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank, _, _, maxRank = Safe(GetSkillLineInfo, i)
      if isHeader then
        section = name
      elseif name and (section == (TRADE_SKILLS or "Professions") or section == (SECONDARY_SKILLS or "Secondary Skills")) then
        list[#list + 1] = { id = 0, name = name, skill = rank or 0, max = maxRank or 0 }
      end
    end
  end
  return { list = list }
end

-- Toutes les compétences (armes, armures, langues...).
function C.skills()
  if not GetNumSkillLines or not GetSkillLineInfo then return nil end
  local list, section = {}, nil
  for i = 1, GetNumSkillLines() do
    local name, isHeader, _, rank, _, mod, maxRank = Safe(GetSkillLineInfo, i)
    if isHeader then
      section = name
    elseif name then
      list[#list + 1] = { n = name, cat = section, r = rank, m = maxRank, b = mod ~= 0 and mod or nil }
    end
  end
  return { list = list }
end

function C.stats()
  local st = {}
  st.hp = Safe(UnitHealthMax, "player")
  st.power = Safe(UnitPowerMax, "player")
  st.powerType = select(2, Safe(UnitPowerType, "player"))
  local names = { "str", "agi", "sta", "int", "spi" }
  for i = 1, 5 do
    local _, eff = Safe(UnitStat, "player", i)
    st[names[i]] = eff
  end
  local _, armor = Safe(UnitArmor, "player")
  st.armor = armor
  local resist = { [2] = "fire", [3] = "nature", [4] = "frost", [5] = "shadow", [6] = "arcane" }
  st.resist = {}
  for i, n in pairs(resist) do
    local _, total = Safe(UnitResistance, "player", i)
    st.resist[n] = total
  end
  local b, pos, neg = Safe(UnitAttackPower, "player")
  if b then st.ap = b + (pos or 0) + (neg or 0) end
  b, pos, neg = Safe(UnitRangedAttackPower, "player")
  if b then st.rap = b + (pos or 0) + (neg or 0) end
  local sp = 0
  for school = 2, 7 do sp = math.max(sp, Safe(GetSpellBonusDamage, school) or 0) end
  st.spellPower = sp
  st.healing = Safe(GetSpellBonusHealing)
  st.crit = round((Safe(GetCritChance)))
  st.rangedCrit = round((Safe(GetRangedCritChance)))
  local sc = 0
  for school = 2, 7 do sc = math.max(sc, Safe(GetSpellCritChance, school) or 0) end
  st.spellCrit = round(sc)
  st.hit = round((Safe(GetHitModifier)))
  st.spellHit = round((Safe(GetSpellHitModifier)))
  st.dodge = round((Safe(GetDodgeChance)))
  st.parry = round((Safe(GetParryChance)))
  st.block = round((Safe(GetBlockChance)))
  local defBase, defMod = Safe(UnitDefense, "player")
  if defBase then st.defense = defBase + (defMod or 0) end
  local regenBase, regenCast = Safe(GetManaRegen)
  st.mp5 = round(regenBase and regenBase * 5, 0)
  st.mp5Casting = round(regenCast and regenCast * 5, 0)
  local mh, oh = Safe(UnitAttackSpeed, "player")
  st.speed = round(mh)
  st.speedOff = round(oh)
  local minD, maxD = Safe(UnitDamage, "player")
  st.dmgMin, st.dmgMax = round(minD, 0), round(maxD, 0)
  st.moveSpeed = round((Safe(GetUnitSpeed, "player")))
  -- Durabilité la plus basse de l'équipement (en %), hors section équipement
  -- pour ne pas renvoyer toutes les infobulles à chaque combat.
  local minDur
  for slot = 1, 19 do
    local cur, max = Safe(GetInventoryItemDurability, slot)
    if cur and max and max > 0 then
      local pct = round(cur / max * 100, 0)
      if not minDur or pct < minDur then minDur = pct end
    end
  end
  st.durability = minDur
  return st
end

function C.reputations()
  local list = {}
  local n = Safe(GetNumFactions) or (C_Reputation and Safe(C_Reputation.GetNumFactions)) or 0
  local header
  for i = 1, n do
    local name, standing, bmin, bmax, value, isHeader, hasRep, id
    if GetFactionInfo then
      local r = { Safe(GetFactionInfo, i) }
      name, standing, bmin, bmax, value, isHeader, hasRep, id = r[1], r[3], r[4], r[5], r[6], r[9], r[11], r[14]
    elseif C_Reputation and C_Reputation.GetFactionDataByIndex then
      local d = Safe(C_Reputation.GetFactionDataByIndex, i)
      if d then
        name, standing, bmin, bmax, value = d.name, d.reaction, d.currentReactionThreshold, d.nextReactionThreshold, d.currentStanding
        isHeader, hasRep, id = d.isHeader, d.isHeaderWithRep, d.factionID
      end
    end
    if name then
      if isHeader and not hasRep then
        header = name
      else
        list[#list + 1] = { n = name, id = id, s = standing, v = value, min = bmin, max = bmax, cat = header }
      end
    end
  end
  return { list = list }
end

function C.lockouts()
  local list = {}
  for i = 1, Safe(GetNumSavedInstances) or 0 do
    local name, id, reset, _, locked, extended, _, isRaid, maxPlayers, diffName, numEnc, encProg = Safe(GetSavedInstanceInfo, i)
    if name and (locked or extended) then
      list[#list + 1] = { n = name, id = id, reset = ns.Now() + (reset or 0), raid = isRaid and true or false,
        size = maxPlayers, d = diffName, done = encProg, total = numEnc }
    end
  end
  for i = 1, Safe(GetNumSavedWorldBosses) or 0 do
    local name, id, reset = Safe(GetSavedWorldBossInfo, i)
    if name then list[#list + 1] = { n = name, id = id, reset = ns.Now() + (reset or 0), worldBoss = true } end
  end
  return { list = list }
end

function C.pvp()
  local p = {}
  local hk, dk, highest = Safe(GetPVPLifetimeStats)
  p.hk, p.dk, p.highestRank = hk, dk, highest
  local rank = Safe(UnitPVPRank, "player")
  if rank and rank > 0 then
    p.rank = rank
    p.rankName = (Safe(GetPVPRankInfo, rank))
  end
  local wHK, wHonor = Safe(GetPVPThisWeekStats)
  p.weekHK, p.weekHonor = wHK, wHonor
  local lwHK, lwDK, lwHonor, lwRank = Safe(GetPVPLastWeekStats)
  p.lastWeekHK, p.lastWeekHonor, p.lastWeekRank = lwHK, lwHonor, lwRank
  p.rankProgress = round(Safe(GetPVPRankProgress), 3)
  p.honor = Safe(GetHonorCurrency)
  if next(p) == nil then return nil end
  return p
end

-- Sacs (non partagé) : objets regroupés par ID.
local function readContainers(bags)
  local GetNum = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local GetLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
  local items, byId, slots, free = {}, {}, 0, 0
  for _, bag in ipairs(bags) do
    local n = Safe(GetNum, bag) or 0
    slots = slots + n
    for slot = 1, n do
      local link = Safe(GetLink, bag, slot)
      local id = ns.ItemIdFromLink(link)
      if id then
        local count = 1
        if C_Container and C_Container.GetContainerItemInfo then
          local info = Safe(C_Container.GetContainerItemInfo, bag, slot)
          count = info and info.stackCount or 1
        elseif GetContainerItemInfo then
          local _, c = Safe(GetContainerItemInfo, bag, slot)
          count = c or 1
        end
        if not byId[id] then
          local tt
          if bag == (BANK_CONTAINER or -1) then
            local inv = Safe(BankButtonIDToInvSlotID, slot)
            if inv then tt = readTooltip("SetInventoryItem", "player", inv) end
          else
            tt = readTooltip("SetBagItem", bag, slot)
          end
          byId[id] = { i = id, c = 0, n = linkName(link), q = itemQuality(link), tt = tt }
          items[#items + 1] = byId[id]
        end
        byId[id].c = byId[id].c + count
      else
        free = free + 1
      end
    end
  end
  return items, slots, free
end

function C.inventory()
  local bags = { 0, 1, 2, 3, 4 }
  if KEYRING_CONTAINER then bags[#bags + 1] = KEYRING_CONTAINER end
  local items, slots, free = readContainers(bags)
  return { items = items, slots = slots, free = free }
end

local bankOpen = false
function C.bank()
  if not bankOpen then return nil end -- lisible seulement banque ouverte
  local bags = { BANK_CONTAINER or -1 }
  local first = (NUM_BAG_SLOTS or 4) + 1
  for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do bags[#bags + 1] = b end
  if REAGENTBANK_CONTAINER then bags[#bags + 1] = REAGENTBANK_CONTAINER end
  local items, slots, free = readContainers(bags)
  return { items = items, slots = slots, free = free }
end

function C.quests()
  local ids = {}
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    ids = Safe(C_QuestLog.GetAllCompletedQuestIDs) or {}
  elseif GetQuestsCompleted then
    local t = Safe(GetQuestsCompleted) or {}
    for id in pairs(t) do ids[#ids + 1] = id end
  end
  table.sort(ids)
  local active = {}
  for i = 1, Safe(GetNumQuestLogEntries) or 0 do
    local title, level, _, isHeader, _, isComplete, _, questID = Safe(GetQuestLogTitle, i)
    if title and not isHeader then active[#active + 1] = { n = title, l = level, id = questID, done = isComplete == 1 or nil } end
  end
  if #ids == 0 and #active == 0 then return nil end
  return { completed = ids, count = #ids, active = active }
end

function C.collections()
  local c = {}
  if C_MountJournal and C_MountJournal.GetMountIDs then
    local mounts = {}
    for _, id in ipairs(Safe(C_MountJournal.GetMountIDs) or {}) do
      local name, spellID, _, _, _, _, _, _, _, _, isCollected = Safe(C_MountJournal.GetMountInfoByID, id)
      if isCollected then mounts[#mounts + 1] = { n = name, sp = spellID } end
    end
    c.mounts = mounts
  elseif GetNumCompanions then
    for _, kind in ipairs({ "MOUNT", "CRITTER" }) do
      local list = {}
      for i = 1, Safe(GetNumCompanions, kind) or 0 do
        local _, name, spellID = Safe(GetCompanionInfo, kind, i)
        if name then list[#list + 1] = { n = name, sp = spellID } end
      end
      c[kind == "MOUNT" and "mounts" or "pets"] = list
    end
  end
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize then
    local cur = {}
    for i = 1, Safe(C_CurrencyInfo.GetCurrencyListSize) or 0 do
      local d = Safe(C_CurrencyInfo.GetCurrencyListInfo, i)
      if d and not d.isHeader and d.quantity and d.quantity > 0 then cur[#cur + 1] = { n = d.name, c = d.quantity } end
    end
    c.currencies = cur
  end
  if next(c) == nil then return nil end
  return c
end

---------------------------------------------------------------------------
-- Recettes : lues quand le joueur ouvre la fenêtre d'un métier.
-- Les recettes déjà vues sont gardées (une recherche ou un filtre dans la
-- fenêtre ne fait rien disparaître).
---------------------------------------------------------------------------

local function readTradeSkillWindow()
  local prof, rank, maxRank, list = nil, nil, nil, {}

  if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo then
    local base = Safe(C_TradeSkillUI.GetBaseProfessionInfo) or Safe(C_TradeSkillUI.GetChildProfessionInfo)
    if base then prof, rank, maxRank = base.professionName, base.skillLevel, base.maxSkillLevel end
    if not prof and C_TradeSkillUI.GetTradeSkillLine then
      local _, name, r, m = Safe(C_TradeSkillUI.GetTradeSkillLine)
      prof, rank, maxRank = name, r, m
    end
    for _, id in ipairs(Safe(C_TradeSkillUI.GetAllRecipeIDs) or {}) do
      local r = Safe(C_TradeSkillUI.GetRecipeInfo, id)
      if r and r.learned then
        local e = { n = r.name, sp = id }
        local out = C_TradeSkillUI.GetRecipeOutputItemData and Safe(C_TradeSkillUI.GetRecipeOutputItemData, id)
        if out and out.itemID then e.i = out.itemID end
        list[#list + 1] = e
      end
    end
    if prof and #list > 0 then return prof, rank, maxRank, list end
  end

  if GetTradeSkillLine and GetNumTradeSkills then
    prof, rank, maxRank = Safe(GetTradeSkillLine)
    if prof and prof ~= "UNKNOWN" then
      Safe(ExpandTradeSkillSubClass, 0)
      for i = 1, Safe(GetNumTradeSkills) or 0 do
        local name, kind = Safe(GetTradeSkillInfo, i)
        if name and kind ~= "header" and kind ~= "subheader" then
          local e = { n = name, d = kind }
          local il = Safe(GetTradeSkillItemLink, i)
          e.i = ns.ItemIdFromLink(il)
          local rl = Safe(GetTradeSkillRecipeLink, i)
          e.sp = rl and tonumber(rl:match("enchant:(%d+)") or rl:match("spell:(%d+)")) or (il and tonumber(il:match("enchant:(%d+)")))
          local cd = Safe(GetTradeSkillCooldown, i)
          if cd and cd > 0 then e.cd = ns.Now() + math.floor(cd) end
          list[#list + 1] = e
        end
      end
      return prof, rank, maxRank, list
    end
  end
  return nil
end

-- Fenêtre "Craft" de Classic (Enchantement, Dressage...).
local function readCraftWindow()
  if not GetNumCrafts or not GetCraftInfo then return nil end
  local prof, rank, maxRank = Safe(GetCraftDisplaySkillLine)
  if not prof then prof, rank, maxRank = Safe(GetCraftSkillLine, 1) end
  if not prof then return nil end
  local list = {}
  for i = 1, Safe(GetNumCrafts) or 0 do
    local name, sub, kind = Safe(GetCraftInfo, i)
    if name and kind ~= "header" then
      local e = { n = sub and sub ~= "" and (name .. " (" .. sub .. ")") or name, d = kind }
      local il = Safe(GetCraftItemLink, i)
      e.i = ns.ItemIdFromLink(il)
      e.sp = il and tonumber(il:match("enchant:(%d+)") or il:match("spell:(%d+)"))
      list[#list + 1] = e
    end
  end
  return prof, rank, maxRank, list
end

local recipeSource -- "trade" ou "craft" : quelle fenêtre vient de s'ouvrir

function C.recipes(old)
  local profs = {}
  for k, v in pairs(old and old.profs or {}) do profs[k] = v end

  local reader = recipeSource == "craft" and readCraftWindow or readTradeSkillWindow
  local prof, rank, maxRank, list = reader()
  if prof and list and #list > 0 then
    local prev = profs[prof] or {}
    local merged, byName = {}, {}
    for _, e in ipairs(prev.list or {}) do
      if e.n and not byName[e.n] then byName[e.n] = e; merged[#merged + 1] = e end
    end
    for _, e in ipairs(list) do
      if byName[e.n] then
        for k, v in pairs(e) do byName[e.n][k] = v end
      else
        byName[e.n] = e
        merged[#merged + 1] = e
      end
    end
    table.sort(merged, function(a, b) return a.n < b.n end)
    local entry = { skill = rank, max = maxRank, list = merged }
    local h = ns.Hash(ns.ToJSON(entry))
    if h ~= prev.h then
      entry.h = h
      entry.at = ns.Now()
      profs[prof] = entry
    end
  end
  if next(profs) == nil then return nil end
  return { profs = profs }
end

---------------------------------------------------------------------------
-- Enregistrement des sections
---------------------------------------------------------------------------

-- code : lettre utilisée par le protocole de guilde (Comm.lua).
ns.SECTIONS = {
  core        = { code = "c", share = true },
  gear        = { code = "g", share = true },
  talents     = { code = "t", share = true },
  professions = { code = "p", share = true },
  recipes     = { code = "r", share = true },
  stats       = { code = "s", share = true },
  lockouts    = { code = "l", share = true },
  pvp         = { code = "v", share = true },
  skills      = { code = "k", share = true },
  reputations = { code = "f", share = true },
  collections = { code = "o", share = false },
  inventory   = { code = "i", share = false },
  bank        = { code = "b", share = false },
  quests      = { code = "q", share = false },
}
ns.SECTION_BY_CODE = {}
for name, s in pairs(ns.SECTIONS) do ns.SECTION_BY_CODE[s.code] = name end

-- Recollecte les sections demandées (toutes si aucune). Renvoie la liste
-- des sections partagées qui ont changé.
function ns.Update(names)
  local m = ns.SelfRecord()
  if not m then return {} end
  local p = m.profile
  p.v = 2
  p.name = m.name
  p.addonVersion = ns.VERSION
  local list = names
  if not list then
    list = {}
    for name in pairs(ns.SECTIONS) do list[#list + 1] = name end
  end
  local changed = {}
  for _, name in ipairs(list) do
    local fn = C[name]
    if fn then
      local ok, data = pcall(fn, p[name])
      if ok and type(data) == "table" then
        data.at = nil
        local h = ns.Hash(ns.ToJSON(data))
        if m.hashes[name] ~= h or type(p[name]) ~= "table" then
          data.at = ns.Now()
          p[name] = data
          m.hashes[name] = h
          m.profileAt = ns.Now()
          if ns.SECTIONS[name].share then changed[#changed + 1] = name end
        end
      elseif not ok and ns.debug then
        ns.Print("erreur section", name, data)
      end
    end
  end
  -- Anciens champs à plat (version 0.1) remplacés par les sections.
  for _, k in ipairs({ "level", "race", "class", "sex", "faction", "ilvl", "spec" }) do p[k] = nil end
  if #changed > 0 and ns.OnSectionsChanged then ns.OnSectionsChanged(changed) end
  return changed
end

---------------------------------------------------------------------------
-- Déclencheurs
---------------------------------------------------------------------------

local function later(key, sec, names)
  ns.Debounce("upd:" .. key, sec, function() ns.Update(names) end)
end

ns.On("PLAYER_LEVEL_UP", function() later("lvl", 3, { "core", "stats", "talents", "skills" }) end)
ns.On("PLAYER_EQUIPMENT_CHANGED", function() later("gear", 3, { "gear", "core", "stats" }) end)
ns.On("UNIT_INVENTORY_CHANGED", function(unit) if unit == "player" then later("gear", 3, { "gear", "core", "stats" }) end end)
ns.On("SKILL_LINES_CHANGED", function() later("skills", 3, { "professions", "skills" }) end)
ns.On("CHARACTER_POINTS_CHANGED", function() later("tal", 3, { "talents", "stats" }) end)
ns.On("PLAYER_TALENT_UPDATE", function() later("tal", 3, { "talents", "core", "stats" }) end)
ns.On("ACTIVE_TALENT_GROUP_CHANGED", function() later("tal", 3, { "talents", "core", "stats" }) end)
ns.On("UPDATE_INSTANCE_INFO", function() later("lock", 2, { "lockouts" }) end)
ns.On("UPDATE_FACTION", function() later("rep", 10, { "reputations" }) end)
ns.On("PLAYER_PVP_RANK_CHANGED", function() later("pvp", 5, { "pvp" }) end)
ns.On("PLAYER_PVP_KILLS_CHANGED", function() later("pvp", 30, { "pvp" }) end)
ns.On("QUEST_TURNED_IN", function() later("quest", 5, { "quests", "core" }) end)
ns.On("PLAYER_XP_UPDATE", function() later("xp", 30, { "core" }) end)
ns.On("BAG_UPDATE_DELAYED", function() later("bags", 5, { "inventory" }) end)
ns.On("BAG_UPDATE", function() later("bags", 5, { "inventory" }) end)
ns.On("NEW_MOUNT_ADDED", function() later("coll", 5, { "collections" }) end)
ns.On("COMPANION_LEARNED", function() later("coll", 5, { "collections" }) end)

ns.On("BANKFRAME_OPENED", function() bankOpen = true; later("bank", 1, { "bank" }) end)
ns.On("PLAYERBANKSLOTS_CHANGED", function() if bankOpen then later("bank", 2, { "bank" }) end end)
ns.On("BANKFRAME_CLOSED", function() ns.Update({ "bank" }); bankOpen = false end)

local function onTrade() recipeSource = "trade"; later("recipes", 1, { "recipes", "professions" }) end
local function onCraft() recipeSource = "craft"; later("recipes", 1, { "recipes", "professions" }) end
ns.On("TRADE_SKILL_SHOW", onTrade)
ns.On("TRADE_SKILL_UPDATE", onTrade)
ns.On("TRADE_SKILL_LIST_UPDATE", onTrade)
ns.On("NEW_RECIPE_LEARNED", onTrade)
ns.On("CRAFT_SHOW", onCraft)
ns.On("CRAFT_UPDATE", onCraft)

-- À la déconnexion : dernière photo complète (sauvée par WoW juste après).
ns.On("PLAYER_LOGOUT", function()
  if IsInGuild() then
    pcall(ns.Update, { "core", "gear", "stats", "inventory", "professions", "skills", "reputations", "quests", "collections", "pvp" })
  end
end)
