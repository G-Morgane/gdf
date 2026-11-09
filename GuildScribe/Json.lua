-- Encodeur / décodeur JSON minimal (aucune dépendance).
local _, ns = ...

---------------------------------------------------------------------------
-- Encodage
---------------------------------------------------------------------------

local function escapeString(s)
  s = s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"'
    elseif c == "\\" then return "\\\\"
    elseif c == "\n" then return "\\n"
    elseif c == "\r" then return "\\r"
    elseif c == "\t" then return "\\t"
    else return string.format("\\u%04x", c:byte()) end
  end)
  return '"' .. s .. '"'
end

local function isArray(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
    n = n + 1
  end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true, n
end

local encode

encode = function(v, out, depth)
  if depth > 40 then out[#out + 1] = "null" return end
  local tv = type(v)
  if tv == "nil" then
    out[#out + 1] = "null"
  elseif tv == "boolean" then
    out[#out + 1] = v and "true" or "false"
  elseif tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      out[#out + 1] = "null"
    elseif v % 1 == 0 and math.abs(v) < 2^53 then
      out[#out + 1] = string.format("%d", v)
    else
      out[#out + 1] = string.format("%.14g", v)
    end
  elseif tv == "string" then
    out[#out + 1] = escapeString(v)
  elseif tv == "table" then
    local arr, n = isArray(v)
    if arr and n > 0 then
      out[#out + 1] = "["
      for i = 1, n do
        if i > 1 then out[#out + 1] = "," end
        encode(v[i], out, depth + 1)
      end
      out[#out + 1] = "]"
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = tostring(k) end
      table.sort(keys)
      out[#out + 1] = "{"
      for i, k in ipairs(keys) do
        if i > 1 then out[#out + 1] = "," end
        out[#out + 1] = escapeString(k)
        out[#out + 1] = ":"
        local val = v[k]
        if val == nil then val = v[tonumber(k)] end
        encode(val, out, depth + 1)
      end
      out[#out + 1] = "}"
    end
  else
    out[#out + 1] = "null"
  end
end

ns.ToJSON = function(v)
  local out = {}
  encode(v, out, 0)
  return table.concat(out)
end

---------------------------------------------------------------------------
-- Décodage (pour les fiches reçues des autres membres)
---------------------------------------------------------------------------

local function fail(msg) error("json: " .. msg, 0) end

local function utf8char(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40) end
  if cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
  return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
    0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

local ESC = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }

local function skip(s, i)
  local _, e = s:find("^[ \n\r\t]*", i)
  return e + 1
end

local function decodeString(s, i)
  local out, j = {}, i + 1
  while true do
    local k = s:find('["\\]', j)
    if not k then fail("chaîne non terminée") end
    out[#out + 1] = s:sub(j, k - 1)
    if s:sub(k, k) == '"' then return table.concat(out), k + 1 end
    local e = s:sub(k + 1, k + 1)
    if e == "u" then
      local cp = tonumber(s:sub(k + 2, k + 5), 16)
      if not cp then fail("\\u invalide") end
      j = k + 6
      if cp >= 0xD800 and cp <= 0xDBFF and s:sub(j, j + 1) == "\\u" then
        local lo = tonumber(s:sub(j + 2, j + 5), 16)
        if lo and lo >= 0xDC00 and lo <= 0xDFFF then
          cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
          j = j + 6
        end
      end
      out[#out + 1] = utf8char(cp)
    elseif ESC[e] then
      out[#out + 1] = ESC[e]
      j = k + 2
    else
      fail("échappement invalide")
    end
  end
end

local decodeValue

decodeValue = function(s, i, depth)
  if depth > 40 then fail("trop imbriqué") end
  i = skip(s, i)
  local c = s:sub(i, i)
  if c == "{" then
    local obj = {}
    i = skip(s, i + 1)
    if s:sub(i, i) == "}" then return obj, i + 1 end
    while true do
      if s:sub(i, i) ~= '"' then fail("clé attendue") end
      local key
      key, i = decodeString(s, i)
      i = skip(s, i)
      if s:sub(i, i) ~= ":" then fail("':' attendu") end
      local val
      val, i = decodeValue(s, i + 1, depth + 1)
      obj[key] = val
      i = skip(s, i)
      local d = s:sub(i, i)
      if d == "}" then return obj, i + 1 end
      if d ~= "," then fail("',' attendu") end
      i = skip(s, i + 1)
    end
  elseif c == "[" then
    local arr, n = {}, 0
    i = skip(s, i + 1)
    if s:sub(i, i) == "]" then return arr, i + 1 end
    while true do
      local val
      val, i = decodeValue(s, i, depth + 1)
      n = n + 1
      arr[n] = val
      i = skip(s, i)
      local d = s:sub(i, i)
      if d == "]" then return arr, i + 1 end
      if d ~= "," then fail("',' attendu") end
      i = i + 1
    end
  elseif c == '"' then
    return decodeString(s, i)
  elseif s:sub(i, i + 3) == "true" then
    return true, i + 4
  elseif s:sub(i, i + 4) == "false" then
    return false, i + 5
  elseif s:sub(i, i + 3) == "null" then
    return nil, i + 4
  else
    local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if not num or num == "" then fail("valeur inattendue") end
    local v = tonumber(num)
    if not v then fail("nombre invalide") end
    return v, i + #num
  end
end

-- Renvoie ok, valeur (ou ok=false, message).
ns.FromJSON = function(s)
  if type(s) ~= "string" then return false, "pas une chaîne" end
  return pcall(function()
    local v, i = decodeValue(s, 1, 0)
    if skip(s, i) <= #s then fail("données en trop") end
    return v
  end)
end
