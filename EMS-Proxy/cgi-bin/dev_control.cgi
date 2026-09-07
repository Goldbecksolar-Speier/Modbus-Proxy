#!/usr/bin/lua
-- =====================================================================
-- dev_control.cgi - MANUELLE Befehle fuer Geraeteslots
--   ?slot=N&cmd=on|off             Einspeisung EIN/AUS (SunSpec Conn)
--   ?slot=N&cmd=limit&pct=0..100   Leistungslimit setzen (WMaxLimPct+Ena)
--   ?slot=N&cmd=nolimit            Leistungslimit aufheben (Ena=0)
--
-- SICHERHEIT (Phase 1.5):
--   * Funktioniert NUR, wenn das Profil einen control-Block mit
--     manual_only=true hat (z.B. kaco_nx3_sunspec).
--   * Schreibt nur die im control-Block definierten Einzelregister
--     per FC6 - sonst nichts.
--   * Wird ausschliesslich per Button (devices.html) mit
--     Bestaetigungsdialog aufgerufen - niemals automatisch.
--   * Jeder Versuch wird nach /tmp/ems_control.log protokolliert.
--
-- ABLAUF:
--   1. Slot-Konfig lesen (/etc/tesvolt_devN_*)
--   2. Profil laden, control-Block pruefen
--   3. Modell-Adresse aus Scan-Cache (/tmp/emsproxy_devN_scan) holen;
--      wenn kein Cache: eigener SunSpec-Scan
--   4. FC6-Write(s), je 2 Versuche
--   5. Ergebnis als Klartext (OK ... / FEHLER:...)
--
-- HINWEIS KACO NX3: Der WR muss Modbus-SCHREIBZUGRIFF freigeschaltet
-- haben, sonst antwortet er mit EXC:1 (illegal function) oder EXC:2/3.
-- RvtTms=300s: der WR kann Befehle nach der Rueckfallzeit
-- selbststaendig aufheben (gilt fuer Conn UND WMaxLimPct).
-- =====================================================================

print("Content-Type: text/plain")
print("")

local L = dofile("/usr/local/bin/profile_loader.lua")
local ok_socket, socket = pcall(require, "socket")

local function logline(msg)
  local f = io.open("/tmp/ems_control.log", "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S"), " ", msg, "\n")
    f:close()
  end
end

local function out(msg)
  print(msg)
  logline(msg)
  os.exit(0)
end

-- ---------- Query parsen ---------------------------------------------------

local qs = os.getenv("QUERY_STRING") or ""
local slot = tonumber(qs:match("slot=(%d)"))
local cmd  = qs:match("cmd=(%a+)")
local pct  = tonumber(qs:match("pct=(%d+)") or "")

if not slot or slot < 1 or slot > 4 then out("FEHLER:slot=1..4 fehlt") end
if cmd ~= "on" and cmd ~= "off" and cmd ~= "limit" and cmd ~= "nolimit" then
  out("FEHLER:cmd=on|off|limit|nolimit fehlt")
end

-- ---------- Slot-Konfig + Profil -------------------------------------------

local function cfg(key)
  return L.read_file("/etc/tesvolt_dev" .. slot .. "_" .. key)
end

local pname = cfg("profile")
if not pname then out("FEHLER:Slot " .. slot .. " hat kein Profil") end

local prof, perr = L.load_profile(pname)
if not prof then out("FEHLER:" .. tostring(perr)) end

local ctl = prof.control
if not (ctl and ctl.manual_only) then
  out("FEHLER:Profil '" .. pname .. "' erlaubt keine manuelle Steuerung (kein control-Block)")
end

local ip = cfg("ip")
if not ip then out("FEHLER:Slot " .. slot .. " hat keine IP") end
local port = tonumber(cfg("port") or "") or prof.port or 502
local unit = tonumber(cfg("unit") or "") or prof.unit_id or 1

-- ---------- Zieladressen: Scan-Cache oder eigener Scan -----------------------

local function load_scan_cache()
  local f = io.open("/tmp/emsproxy_dev" .. slot .. "_scan", "r")
  if not f then return nil end
  local scan = { models = {} }
  for line in f:lines() do
    local mid, ds, len = line:match("^(%d+)=(%d+),(%d+)$")
    if mid then
      scan.models[tonumber(mid)] = { data_start = tonumber(ds), len = tonumber(len) }
    end
  end
  f:close()
  if next(scan.models) then return scan end
  return nil
end

local scan = load_scan_cache()
if not scan and prof.sunspec and prof.sunspec.scan_required then
  local s, serr = L.sunspec_scan(ip, port, unit, prof.sunspec)
  if not s then out("FEHLER:" .. tostring(serr)) end
  scan = s
end

local function model_addr(model, offset)
  if not (scan and scan.models and scan.models[model]) then
    return nil, "FEHLER:Modell " .. tostring(model) .. " nicht im Scan (erst Poll ausfuehren)"
  end
  return scan.models[model].data_start + (offset or 0)
end

-- ---------- FC6 Write Single Register ---------------------------------------

local function write_reg(w_addr, w_val)
  if not ok_socket then return nil, "ERR:luasocket fehlt" end
  local c = socket.tcp()
  c:settimeout(5)
  local ok, err = c:connect(ip, port)
  if not ok then c:close() return nil, "ERR:connect " .. tostring(err) end
  local function hi(v) return math.floor(v / 256) % 256 end
  local function lo(v) return v % 256 end
  local pdu = string.char(6, hi(w_addr), lo(w_addr), hi(w_val), lo(w_val))
  c:send(string.char(0, 1, 0, 0, 0, #pdu + 1, unit) .. pdu)
  local h = c:receive(7)
  if not h then c:close() return nil, "ERR:timeout header" end
  local len = h:byte(5) * 256 + h:byte(6)
  local body = c:receive(len - 1)
  c:close()
  if not body then return nil, "ERR:timeout body" end
  if body:byte(1) == 6 + 0x80 then return nil, "EXC:" .. body:byte(2) end
  if body:byte(1) ~= 6 then return nil, "ERR:bad fc " .. body:byte(1) end
  return true
end

-- 2 Versuche (NX3 mag keine schnellen Verbindungsfolgen)
local function write_retry(w_addr, w_val)
  local wok, werr
  for t = 1, 2 do
    wok, werr = write_reg(w_addr, w_val)
    if wok then return true end
    L.sleep(1)
  end
  return nil, werr
end

local function fail_write(werr)
  if tostring(werr):find("^EXC:") then
    out("FEHLER:" .. werr .. " - Schreibzugriff am WR freigeschaltet? (MODBUS/SunSpec-Menue)")
  end
  out("FEHLER:" .. tostring(werr))
end

local function request_poll()
  local pf = io.open("/tmp/emsproxy_poll_req", "w")
  if pf then pf:close() end
end

-- ---------- Befehle ----------------------------------------------------------

if cmd == "on" or cmd == "off" then
  local cp = ctl.conn
  if not cp then out("FEHLER:Profil hat keinen conn-Punkt") end
  local addr, aerr = cp.addr
  if not addr and cp.model then addr, aerr = model_addr(cp.model, cp.offset) end
  if not addr then out(aerr or "FEHLER:keine Adresse im control-Block") end
  local value = (cmd == "on") and (cp.on or 1) or (cp.off or 0)

  logline("BEFEHL slot=" .. slot .. " profil=" .. pname .. " ip=" .. ip ..
          " unit=" .. unit .. " cmd=" .. cmd .. " addr=" .. addr .. " val=" .. value)
  local wok, werr = write_retry(addr, value)
  if not wok then fail_write(werr) end
  request_poll()
  out("OK - Befehl '" .. cmd .. "' gesendet (Register " .. addr .. "=" .. value ..
      "). Status aktualisiert sich nach dem naechsten Poll.")
end

-- cmd == "limit" oder "nolimit"
local lp = ctl.limit
if not lp then out("FEHLER:Profil hat keinen limit-Punkt") end

local pct_addr, perr1 = model_addr(lp.model, lp.pct_offset)
if not pct_addr then out(perr1) end
local ena_addr, perr2 = model_addr(lp.model, lp.ena_offset)
if not ena_addr then out(perr2) end

if cmd == "nolimit" then
  logline("BEFEHL slot=" .. slot .. " profil=" .. pname .. " ip=" .. ip ..
          " unit=" .. unit .. " cmd=nolimit addr=" .. ena_addr .. " val=0")
  local wok, werr = write_retry(ena_addr, 0)
  if not wok then fail_write(werr) end
  request_poll()
  out("OK - Leistungslimit aufgehoben (Register " .. ena_addr .. "=0).")
end

-- cmd == "limit": erst Prozentwert, dann Enable
if not pct then out("FEHLER:pct=0..100 fehlt") end
local pmin = lp.pct_min or 0
local pmax = lp.pct_max or 100
if pct < pmin or pct > pmax then
  out("FEHLER:pct " .. pct .. " ausserhalb " .. pmin .. ".." .. pmax)
end
local raw = math.floor(pct * (lp.pct_scale or 100) + 0.5)

logline("BEFEHL slot=" .. slot .. " profil=" .. pname .. " ip=" .. ip ..
        " unit=" .. unit .. " cmd=limit pct=" .. pct ..
        " addr_pct=" .. pct_addr .. " raw=" .. raw .. " addr_ena=" .. ena_addr)

local wok, werr = write_retry(pct_addr, raw)
if not wok then fail_write(werr) end
L.sleep(0.5)
wok, werr = write_retry(ena_addr, 1)
if not wok then
  logline("WARNUNG: WMaxLimPct geschrieben, aber Enable fehlgeschlagen: " .. tostring(werr))
  fail_write(werr)
end
request_poll()
out("OK - Leistungslimit " .. pct .. "% gesetzt (Reg " .. pct_addr .. "=" .. raw ..
    ", Reg " .. ena_addr .. "=1). ACHTUNG: Rueckfallzeit 300 s moeglich.")
