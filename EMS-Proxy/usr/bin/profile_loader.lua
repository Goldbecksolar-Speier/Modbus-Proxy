-- =====================================================================
-- profile_loader.lua - Geraeteprofil-Lader + Modbus-Leser (READ-ONLY)
--
-- Modul (dofile-Stil, kein require-Pfad noetig):
--   local L = dofile("/usr/local/bin/profile_loader.lua")
--
-- Funktionen:
--   L.load_profile(name)          Profil aus PROFILE_DIR laden (dofile)
--   L.read_regs(ip,port,unit,fc,addr,count[,timeout])
--                                 N Holding/Input-Register lesen
--   L.sunspec_scan(ip,port,unit,cfg)
--                                 SunS-Marker suchen + Modellkette lesen
--   L.read_point(dev,prof,p,scan,sf_cache)
--                                 einen Messpunkt aufloesen und lesen
--   L.decode / L.apply_sf / L.is_not_impl / L.sleep / L.read_file
--
-- Regeln (SunSpec Device Information Model Spec v1.2.1):
--   * "SunS" (0x53756E53) an 0, 40000 oder 50000; Kette bis ID 0xFFFF
--   * sunssf: s16, -10..+10, NOT IMPLEMENTED = 0x8000 (-32768)
--     Echtwert = Rohwert * 10^SF; SF ist statisch -> sf_cache
--   * NOT-IMPLEMENTED-Sentinels je Typ -> Wert verwerfen ("NA:")
--
-- ROBUSTHEIT (Learning Kaco NX3, 2026-09-07):
--   Der NX3 beantwortet schnell aufeinanderfolgende TCP-Verbindungen
--   teils mit Timeout. Der Modell-Scan nutzt deshalb 5 s Timeout,
--   bis zu 3 Versuche pro Header-Read und kurze Pausen dazwischen.
--
-- STRIKT READ-ONLY: dieses Modul enthaelt KEINE Schreibfunktion.
-- =====================================================================

local ok_socket, socket = pcall(require, "socket")

local M = {}

M.PROFILE_DIR = "/usr/local/bin/profiles/"

-- ---------- Helfer -------------------------------------------------------

function M.read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*l")
  f:close()
  if s then s = s:gsub("%s+$", "") end
  if s == "" then return nil end
  return s
end

function M.sleep(sec)
  if ok_socket and sec and sec > 0 then socket.sleep(sec) end
end

-- ---------- Modbus TCP: N Register lesen ---------------------------------

function M.read_regs(ip, port, unit, fc, addr, count, timeout)
  if not ok_socket then return nil, "ERR:luasocket fehlt" end
  local c = socket.tcp()
  c:settimeout(timeout or 2)
  local ok, err = c:connect(ip, port)
  if not ok then c:close() return nil, "ERR:connect " .. tostring(err) end
  local function hi(v) return math.floor(v / 256) % 256 end
  local function lo(v) return v % 256 end
  local pdu = string.char(fc, hi(addr), lo(addr), hi(count), lo(count))
  c:send(string.char(0, 1, 0, 0, 0, #pdu + 1, unit) .. pdu)
  local h = c:receive(7)
  if not h then c:close() return nil, "ERR:timeout header" end
  local len = h:byte(5) * 256 + h:byte(6)
  local body = c:receive(len - 1)
  c:close()
  if not body then return nil, "ERR:timeout body" end
  if body:byte(1) == fc + 0x80 then return nil, "EXC:" .. body:byte(2) end
  if body:byte(1) ~= fc then return nil, "ERR:bad fc " .. body:byte(1) end
  local n = math.floor((body:byte(2) or 0) / 2)
  if n < count then return nil, "ERR:short reply" end
  local words = {}
  for i = 1, n do
    words[i] = body:byte(2 * i + 1) * 256 + body:byte(2 * i + 2)
  end
  return words
end

-- Wie read_regs, aber mit Wiederholversuchen (fuer zickige Geraete
-- wie den Kaco NX3, der schnelle Verbindungsfolgen mit Timeout quittiert)
function M.read_regs_retry(ip, port, unit, fc, addr, count, timeout, tries, pause)
  tries = tries or 3
  pause = pause or 0.5
  local last
  for t = 1, tries do
    local w, e = M.read_regs(ip, port, unit, fc, addr, count, timeout)
    if w then return w end
    last = e
    if t < tries then M.sleep(pause) end
  end
  return nil, last
end

-- ---------- Dekodierung ---------------------------------------------------

function M.word_count(t)
  if t == "u32be" or t == "s32be" or t == "f32be" then return 2 end
  return 1
end

function M.decode(words, t)
  t = t or "u16"
  if t == "u16" then return words[1] end
  if t == "s16" then
    local v = words[1]
    if v > 32767 then v = v - 65536 end
    return v
  end
  if t == "u32be" or t == "s32be" then
    local v = words[1] * 65536 + words[2]
    if t == "s32be" and v > 2147483647 then v = v - 4294967296 end
    return v
  end
  if t == "f32be" then
    -- IEEE-754 float aus 2 Woertern (Big-Endian), Lua 5.1 ohne bitops
    local hiw, low = words[1], words[2]
    local sign = 1
    if hiw >= 0x8000 then sign = -1 hiw = hiw - 0x8000 end
    local exp = math.floor(hiw / 128)
    local mant = (hiw % 128) * 65536 + low
    if exp == 0 and mant == 0 then return 0 end
    if exp == 255 then return nil end -- Inf/NaN -> ungueltig
    if exp == 0 then return sign * (mant / 8388608) * (2 ^ -126) end
    return sign * (1 + mant / 8388608) * (2 ^ (exp - 127))
  end
  return nil
end

function M.is_not_impl(words, t, ni)
  if not ni then return false end
  if M.word_count(t) == 2 then
    return (words[1] * 65536 + words[2]) == ni
  end
  return words[1] == ni
end

-- sunssf anwenden: sf_raw ist das ROHE u16-Registerwort
function M.apply_sf(value, sf_raw)
  if sf_raw == nil then return value end
  local sf = sf_raw
  if sf > 32767 then sf = sf - 65536 end
  if sf == -32768 then return nil end -- 0x8000 = NOT IMPLEMENTED
  return value * (10 ^ sf)
end

-- ---------- Profil laden ---------------------------------------------------

function M.load_profile(name)
  if not name or name == "" or name:find("[^%w_%-]") then
    return nil, "ERR:ungueltiger Profilname"
  end
  local path = M.PROFILE_DIR .. name .. ".lua"
  local okp, prof = pcall(dofile, path)
  if not okp or type(prof) ~= "table" then
    return nil, "ERR:Profil nicht ladbar (" .. path .. ")"
  end
  return prof
end

-- ---------- SunSpec Model Scan ---------------------------------------------

-- Ergebnis: { base = <addr>, models = { [id] = {data_start=, len=} } }
-- Robust: 5 s Timeout, 3 Versuche pro Read, Pausen zwischen den Reads
-- (Kaco NX3 laesst nur langsame Verbindungsfolgen zu). Bricht die Kette
-- mitten drin ab, wird ein ECHTER Fehler gemeldet statt einer leeren Liste.
function M.sunspec_scan(ip, port, unit, cfg)
  local bases = (cfg and cfg.base_candidates) or { 40000, 0, 50000 }
  local end_id = (cfg and cfg.end_model_id) or 0xFFFF
  local tmo = (cfg and cfg.scan_timeout) or 5
  for _, base in ipairs(bases) do
    local w = M.read_regs_retry(ip, port, unit, 3, base, 2, tmo, 2, 0.5)
    if w and w[1] == 0x5375 and w[2] == 0x6E53 then -- "Su" "nS"
      local models, addr = {}, base + 2
      for _ = 1, 60 do -- Schutz gegen Endlos-Kette
        M.sleep(0.3)
        local h, herr = M.read_regs_retry(ip, port, unit, 3, addr, 2, tmo, 3, 0.5)
        if not h then
          return nil, "ERR:Scan-Abbruch bei addr=" .. addr .. " (" .. tostring(herr) .. ")"
        end
        if h[1] == end_id then break end
        models[h[1]] = { data_start = addr + 2, len = h[2] }
        addr = addr + 2 + h[2]
      end
      return { base = base, models = models }
    end
  end
  return nil, "ERR:SunS-Marker nicht gefunden (0/40000/50000)"
end

-- ---------- Messpunkt lesen -------------------------------------------------

-- dev = { ip=, port=, unit= }; p = Punktdefinition aus dem Profil;
-- scan = Ergebnis von sunspec_scan (nur fuer model+offset-Punkte);
-- sf_cache = Tabelle (SF-Register sind statisch -> einmal lesen)
function M.read_point(dev, prof, p, scan, sf_cache)
  sf_cache = sf_cache or {}
  -- 1. Adresse aufloesen (absolut ODER modell-relativ)
  local addr = p.addr
  if not addr and p.model then
    if not (scan and scan.models and scan.models[p.model]) then
      return nil, "ERR:Modell " .. tostring(p.model) .. " nicht im Scan"
    end
    addr = scan.models[p.model].data_start + (p.offset or 0)
  end
  if not addr then return nil, "ERR:keine Adresse im Punkt" end
  local fc = p.fc or 3
  -- 2. Rohwert lesen
  local n = M.word_count(p.type)
  local words, err = M.read_regs_retry(dev.ip, dev.port, dev.unit, fc, addr, n, 3, 2, 0.3)
  if not words then return nil, err end
  if M.is_not_impl(words, p.type, p.not_impl) then
    return nil, "NA:not implemented"
  end
  local v = M.decode(words, p.type)
  if v == nil then return nil, "ERR:decode " .. tostring(p.type) end
  -- 3. SunSpec Scale Factor (sf_addr absolut oder sf_offset modell-relativ)
  local sf_addr = p.sf_addr
  if not sf_addr and p.sf_offset and p.model and scan
     and scan.models[p.model] then
    sf_addr = scan.models[p.model].data_start + p.sf_offset
  end
  if sf_addr then
    local sfv = sf_cache[sf_addr]
    if sfv == nil then
      local sw, serr = M.read_regs_retry(dev.ip, dev.port, dev.unit, fc, sf_addr, 1, 3, 2, 0.3)
      if not sw then return nil, serr end
      sfv = sw[1]
      sf_cache[sf_addr] = sfv
    end
    v = M.apply_sf(v, sfv)
    if v == nil then return nil, "NA:SF not implemented" end
  end
  -- 4. Feste Skalierung aus dem Profil (z.B. 0.1 V)
  if p.scale and p.scale ~= 1 then v = v * p.scale end
  -- 5. Richtungsregister (z.B. Solis 33135: 0=Laden, 1=Entladen)
  --    Proxy-Konvention: >0 = Entladen
  if p.dir_reg then
    local dw, derr = M.read_regs_retry(dev.ip, dev.port, dev.unit, fc, p.dir_reg, 1, 3, 2, 0.3)
    if not dw then return nil, derr end
    local mag = math.abs(v)
    if dw[1] == (p.dir_discharge or 1) then v = mag else v = -mag end
  end
  return v
end

return M
