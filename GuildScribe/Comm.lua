-- Échange des fiches entre membres par le canal caché de la guilde.
--
-- Protocole 2 (préfixe GSCRIBE) :
--   H~2~version~c:hash,g:hash,...   "voici l'état de mes sections"
--   W~2~Nom-Royaume~c,g,r           "envoie-moi ces sections"
--   D~2~id~i~n~morceau              une section en JSON, découpée en n morceaux
--   Q~2                             "tout le monde : envoyez votre H"
--
-- Les collecteurs (officiers, ou /gs collecteur) demandent ce qui leur
-- manque ; les autres se contentent d'annoncer leur état. Une section reçue
-- est stockée telle quelle, même si elle vient d'une version plus récente de
-- l'add-on : les anciennes versions relaient donc aussi les nouvelles données.
--
-- Protocole 1 (version 0.1.0 : messages P, R, G) toujours accepté en lecture.

local _, ns = ...
local PREFIX = "GSCRIBE"
local PROTO = 2
local CHUNK = 220
local MAX_PARTS = 400

local queue = {}
local pumping = false
local sentAt = {}      -- section -> dernier envoi (anti-doublon)
local wantedAt = {}    -- membre -> dernière demande vue sur le canal
local inbox = {}       -- morceaux en cours de réception
local msgCounter = 0
local warnedVersion = false

---------------------------------------------------------------------------
-- Envoi (file d'attente : 1 message par seconde pour rester sous la limite)
---------------------------------------------------------------------------

local function rawSend(msg)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    return C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD")
  elseif SendAddonMessage then
    return SendAddonMessage(PREFIX, msg, "GUILD")
  end
end

local function pump()
  if #queue == 0 or not IsInGuild() then pumping = false return end
  local item = table.remove(queue, 1)
  local ok, res = pcall(rawSend, item.msg)
  -- Limite atteinte : on réessaie plus tard (Enum.SendAddonMessageResult 0 = succès).
  local throttled = ok and ((res == false) or (type(res) == "number" and res ~= 0))
  if throttled and (item.tries or 0) < 5 then
    item.tries = (item.tries or 0) + 1
    table.insert(queue, 1, item)
    ns.After(3, pump)
    return
  end
  ns.After(1, pump)
end

local function send(msg, urgent)
  if not IsInGuild() then return end
  if urgent then table.insert(queue, 1, { msg = msg }) else queue[#queue + 1] = { msg = msg } end
  if not pumping then
    pumping = true
    ns.After(0.2, pump)
  end
end

-- Découpe sans couper un caractère accentué en deux.
local function chunks(s)
  local out, i = {}, 1
  while i <= #s do
    local j = math.min(i + CHUNK - 1, #s)
    while j < #s and j > i do
      local b = s:byte(j + 1)
      if b < 0x80 or b >= 0xC0 then break end
      j = j - 1
    end
    out[#out + 1] = s:sub(i, j)
    i = j + 1
  end
  return out
end

local function sendSection(name)
  local m = ns.SelfRecord()
  if not m or type(m.profile[name]) ~= "table" then return end
  local s = ns.SECTIONS[name]
  if not s or not s.share then return end
  if sentAt[name] and ns.Now() - sentAt[name] < 20 then return end
  sentAt[name] = ns.Now()
  -- "|" est interdit dans les messages : on l'échappe en JSON.
  local json = ns.ToJSON({ s = name, c = s.code, h = m.hashes[name], d = m.profile[name] }):gsub("|", "\\u007c")
  local parts = chunks(json)
  if #parts > MAX_PARTS then return end
  msgCounter = (msgCounter + 1) % 100000
  local id = tostring(msgCounter)
  for i, part in ipairs(parts) do
    send(table.concat({ "D", PROTO, id, i, #parts, part }, "~"))
  end
end

local function sendHello()
  local m = ns.SelfRecord()
  if not m then return end
  local list = {}
  for name, s in pairs(ns.SECTIONS) do
    if s.share and m.hashes[name] and type(m.profile[name]) == "table" then
      list[#list + 1] = s.code .. ":" .. m.hashes[name]:sub(1, 6)
    end
  end
  table.sort(list)
  send(table.concat({ "H", PROTO, ns.VERSION, table.concat(list, ",") }, "~"), true)
end
ns.SendHello = sendHello

-- Appelé par Collect.lua quand une section partagée change.
function ns.OnSectionsChanged()
  ns.Debounce("hello", 5, sendHello)
end

function ns.RequestAll()
  send("Q~" .. PROTO, true)
  sendHello()
end

---------------------------------------------------------------------------
-- Réception
---------------------------------------------------------------------------

local function memberProfile(sender)
  local g = ns.GuildDB()
  if not g then return nil end
  local m = ns.Member(g, sender)
  m.profile = m.profile or {}
  m.hashes = m.hashes or {}
  return m
end

local function onHello(sender, version, list)
  local m = memberProfile(sender)
  if not m then return end
  m.profile.addonVersion = version
  m.profile.name = sender
  if not warnedVersion and ns.NewerVersion(version, ns.VERSION) then
    warnedVersion = true
    ns.Print(("une version plus récente de l'add-on existe (%s, tu as %s) : redemande le zip sur le Discord de la guilde."):format(version, ns.VERSION))
  end
  if not ns.IsCollector() then return end

  local want = {}
  for _, entry in ipairs(ns.Split(list or "", ",")) do
    local code, hash = entry:match("^(%w+):(%x+)$")
    if code then
      local known = m.codeHashes and m.codeHashes[code]
      if not known or known:sub(1, #hash) ~= hash then want[#want + 1] = code end
    end
  end
  if #want == 0 then return end
  -- Petit délai : si un autre officier demande déjà, on profite de sa réponse.
  ns.Debounce("want:" .. sender, 1 + math.random() * 4, function()
    if wantedAt[sender] and ns.Now() - wantedAt[sender] < 30 then return end
    wantedAt[sender] = ns.Now()
    send(table.concat({ "W", PROTO, sender, table.concat(want, ",") }, "~"), true)
  end)
end

local function onWant(target, codes)
  wantedAt[target] = ns.Now()
  if target ~= ns.PlayerName() then return end
  for _, code in ipairs(ns.Split(codes or "", ",")) do
    local name = ns.SECTION_BY_CODE[code]
    if name then sendSection(name) end
  end
end

local RESERVED = { v = true, name = true, addonVersion = true }

local function onData(sender, id, i, n, part)
  if n < 1 or n > MAX_PARTS or i < 1 or i > n then return end
  local key = sender .. "#" .. id
  local now = ns.Now()
  for k, box in pairs(inbox) do
    if now - box.t > 180 then inbox[k] = nil end
  end
  local box = inbox[key]
  if not box then
    box = { n = n, parts = {}, got = 0, t = now }
    inbox[key] = box
  end
  if not box.parts[i] then
    box.parts[i] = part
    box.got = box.got + 1
  end
  if box.got < box.n then return end
  inbox[key] = nil

  local ok, obj = ns.FromJSON(table.concat(box.parts))
  if not ok or type(obj) ~= "table" or type(obj.d) ~= "table" then return end
  local name = obj.s
  if type(name) ~= "string" or not name:match("^[%w_]+$") or #name > 32 or RESERVED[name] then return end
  local m = memberProfile(sender)
  if not m then return end
  m.profile[name] = obj.d
  m.profile.v = m.profile.v or 2
  if type(obj.h) == "string" then m.hashes[name] = obj.h end
  if type(obj.c) == "string" and type(obj.h) == "string" then
    m.codeHashes = m.codeHashes or {}
    m.codeHashes[obj.c] = obj.h
  end
  m.profileAt = now
end

-- Ancien protocole (0.1.0).
local function onLegacy(sender, kind, parts)
  local m = memberProfile(sender)
  if not m then return end
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
    local list = {}
    for _, entry in ipairs(ns.Split(parts[3] or "", ";")) do
      local f = ns.Split(entry, ":")
      if f[2] then
        list[#list + 1] = { id = tonumber(f[1]) or 0, name = f[2], skill = tonumber(f[3]) or 0, max = tonumber(f[4]) or 0 }
      end
    end
    p.professions = { at = ns.Now(), list = list }
  elseif kind == "G" then
    local items = {}
    for slot, id in ipairs(ns.Split(parts[3] or "", ",")) do
      id = tonumber(id)
      if id and id > 0 then items[#items + 1] = { slot = slot, id = id } end
    end
    p.gear = { at = ns.Now(), items = items }
  else
    return
  end
  m.profileAt = ns.Now()
end

ns.On("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
  if prefix ~= PREFIX or channel ~= "GUILD" then return end
  sender = ns.FullName(sender)
  local kind, proto = msg:match("^(%a)~(%d+)")
  proto = tonumber(proto)
  if not kind or not proto then return end
  local me = ns.PlayerName()

  if proto == 1 then
    if sender ~= me then onLegacy(sender, kind, ns.Split(msg, "~")) end
    if kind == "Q" and sender ~= me then ns.Debounce("helloQ", 1 + math.random() * 8, sendHello) end
    return
  end

  -- Protocole 2 et suivants : on lit ce qu'on comprend, on ignore le reste.
  if kind == "Q" then
    if sender ~= me then ns.Debounce("helloQ", 1 + math.random() * 8, sendHello) end
  elseif kind == "W" then
    local target, codes = msg:match("^W~%d+~([^~]+)~([^~]*)")
    if target then onWant(target, codes) end
  elseif sender == me then
    return
  elseif kind == "H" then
    local version, list = msg:match("^H~%d+~([^~]*)~([^~]*)")
    if version then onHello(sender, version, list) end
  elseif kind == "D" then
    local id, i, n, part = msg:match("^D~%d+~(%w+)~(%d+)~(%d+)~(.*)$")
    if id then onData(sender, id, tonumber(i), tonumber(n), part) end
  end
end)

---------------------------------------------------------------------------
-- Démarrage
---------------------------------------------------------------------------

ns.On("ADDON_LOADED", function(name)
  if name ~= ns.ADDON then return end
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  elseif RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(PREFIX)
  end
end)

ns.On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
  if not (isLogin or isReload) then return end
  ns.Safe(RequestRaidInfo)
  ns.After(8, function()
    if not IsInGuild() then return end
    ns.ScanNow()
    ns.Update()
    sendHello()
    if ns.IsCollector() then send("Q~" .. PROTO, true) end
  end)
end)
