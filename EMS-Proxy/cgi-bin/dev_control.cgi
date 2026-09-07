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
--   * Schreibt nur die im control-Block definierten Einzelregister -
--     sonst nichts.
--   * Wird ausschliesslich per Button (devices.html) mit
--     Bestaetigungsdialog aufgerufen - niemals automatisch.
--   * Jeder Versuch wird nach /tmp/ems_control.log protokolliert.
--
-- WRITE-STRATEGIE (Learning 2026-09-07):
--   Viele SunSpec-Geraete akzeptieren nur FC16 (Write Multiple),
--   nicht FC6 (Write Single) - oder umgekehrt. Deshalb:
--     1. FC6 versuchen; bei EXC:1 (illegal function) -> FC16
--     2. Nach erfolgreichem Write das Register RUECKLESEN und den
--        Ist-Wert mit ausgeben - "OK" heisst sonst nur, dass der WR
--        die Anfrage quittiert hat, NICHT dass er den Wert uebernahm!
--
-- HINWEIS KACO NX3: Der WR muss Modbus-SCHREIBZUGRIFF freigeschaltet
-- haben, sonst EXC:2/3 oder Quittung ohne Wirkung. RvtTms=300s:
-- der WR kann Befehle nach der Rueckfallzeit selbststaendig aufheben.
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

-- ---------- Modbus Write (FC6, Fallback FC16) --------------------------------

local function hi(v) return math.floor(v / 256) % 256 end
local function lo(v) return v % 256 end

-- Ein Register schreiben. fc = 6 oder 16.
local function write_reg_fc(w_addr, w_val, fc)
  if not ok_socket then return nil, "ERR:luasocket fehlt" end
  local c = socket.tcp()
  c:settimeout(5)
  local ok, err = c:connect(ip, port)
  if not ok then c:close() return nil, "ERR:connect " .. tostring(err) end
  local pdu
  if fc == 16 then
    pdu = string.char(16, hi(w_addr), lo(w_addr), 0, 1, 2, hi(w_val), lo(w_val))
  else
    pdu = string.char(6, hi(w_addr), lo(w_addr), hi(w_val), lo(w_val))
  end
  c:send(string.char(0, 1, 0, 0, 0, #pdu + 1, unit) .. pdu)
  local h = c:receive(7)
  if not h then c:close() return nil, "ERR:timeout header" end
  local len = h:byte(5) * 256 + h:byte(6)
  local body = c:receive(len - 1)
  c:close()
  if not body then return nil, "ERR:timeout body" end
  if body:byte(1) == fc + 0x80 then return nil, "EXC:" .. body:byte(2) end
  if body:byte(1) ~= fc then return nil, "ERR:bad fc " .. body:byte(1) end
  return true
end

-- FC6 mit 2 Versuchen; bei EXC:1 (illegal function) Fallback auf FC16.
-- Rueckgabe: true, benutzter_fc  ODER  nil, fehler
local function write_retry(w_addr, w_val)
  local wok, werr
  for t = 1, 2 do
    wok, werr = write_reg_fc(w_addr, w_val, 6)
    if wok then return true, 6 end
    if tostring(werr) == "EXC:1" then break end -- FC6 nicht unterstuetzt
    L.sleep(1)
  end
  logline("FC6 fehlgeschlagen (" .. tostring(werr) .. ") - versuche FC16")
  for t = 1, 2 do
    wok, werr = write_reg_fc(w_addr, w_val, 16)
    if wok then return true, 16 end
    L.sleep(1)
  end
  return nil, werr
end

-- Kontroll-Ruecklesen: liefert Ist-Wert oder nil
local function read_back(w_addr)
  L.sleep(0.5)
  local w = L.read_regs_retry(ip, port, unit, 3, w_addr, 1, 5, 2, 0.5)
  return w and w[1] or nil
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

-- Schreiben + verifizieren; Rueckgabe: Text "geschrieben (FCx), Ruecklesen=Y"
local function write_verify(w_addr, w_val, name)
  local wok, fc_or_err = write_retry(w_addr, w_val)
  if not wok then fail_write(fc_or_err) end
  local rb = read_back(w_addr)
  local txt = name .. ": Reg " .. w_addr .. "=" .. w_val .. " (FC" .. fc_or_err .. ")"
  if rb == nil then
    txt = txt .. ", Ruecklesen FEHLGESCHLAGEN"
  elseif rb == w_val then
    txt = txt .. ", Ruecklesen OK (" .. rb .. ")"
  else
    txt = txt .. ", ABER Ruecklesen=" .. rb .. " - WR hat Wert NICHT uebernommen!"
  end
  logline(txt)
  return txt, (rb == w_val)
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
          " unit=" .. unit .. " cmd=" .. cmd)
  local txt, verified = write_verify(addr, value, "Conn")
  request_poll()
  if verified then
    out("OK - " .. txt)
  else
    out("WARNUNG - " .. txt)
  end
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
          " unit=" .. unit .. " cmd=nolimit")
  local txt, verified = write_verify(ena_addr, 0, "WMaxLim_Ena")
  request_poll()
  if verified then
    out("OK - Limit aufgehoben. " .. txt)
  else
    out("WARNUNG - " .. txt)
  end
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
        " unit=" .. unit .. " cmd=limit pct=" .. pct)

local txt1, ver1 = write_verify(pct_addr, raw, "WMaxLimPct")
L.sleep(0.5)
local txt2, ver2 = write_verify(ena_addr, 1, "WMaxLim_Ena")
request_poll()

if ver1 and ver2 then
  out("OK - Limit " .. pct .. "% aktiv. " .. txt1 .. " | " .. txt2 ..
      " | ACHTUNG: Rueckfallzeit 300 s moeglich.")
else
  out("WARNUNG - " .. txt1 .. " | " .. txt2)
end
