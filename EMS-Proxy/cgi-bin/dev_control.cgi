#!/usr/bin/lua
-- =====================================================================
-- dev_control.cgi - MANUELLER EIN/AUS-Befehl fuer Geraeteslots
--   ?slot=N&cmd=on|off
--
-- SICHERHEIT (Phase 1.5):
--   * Funktioniert NUR, wenn das Profil einen control-Block mit
--     manual_only=true und einem conn-Punkt hat (z.B. kaco_nx3_sunspec).
--   * Schreibt GENAU EIN Register (SunSpec Conn) per FC6 - sonst nichts.
--   * Wird ausschliesslich per Button (devices.html) mit
--     Bestaetigungsdialog aufgerufen - niemals automatisch.
--   * Jeder Versuch wird nach /tmp/ems_control.log protokolliert.
--
-- ABLAUF:
--   1. Slot-Konfig lesen (/etc/tesvolt_devN_*)
--   2. Profil laden, control-Block pruefen
--   3. M123-Adresse aus Scan-Cache (/tmp/emsproxy_devN_scan) holen;
--      wenn kein Cache: eigener SunSpec-Scan
--   4. FC6-Write Conn=1 (on) bzw. Conn=0 (off), 2 Versuche
--   5. Ergebnis als Klartext (OK ... / FEHLER:...)
--
-- HINWEIS KACO NX3: Der WR muss Modbus-SCHREIBZUGRIFF freigeschaltet
-- haben, sonst antwortet er mit EXC:1 (illegal function) oder EXC:2/3.
-- Conn_RvtTms=300s: der WR kann den Befehl nach der Rueckfallzeit
-- selbststaendig aufheben.
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

if not slot or slot < 1 or slot > 4 then out("FEHLER:slot=1..4 fehlt") end
if cmd ~= "on" and cmd ~= "off" then out("FEHLER:cmd=on|off fehlt") end

-- ---------- Slot-Konfig + Profil -------------------------------------------

local function cfg(key)
  return L.read_file("/etc/tesvolt_dev" .. slot .. "_" .. key)
end

local pname = cfg("profile")
if not pname then out("FEHLER:Slot " .. slot .. " hat kein Profil") end

local prof, perr = L.load_profile(pname)
if not prof then out("FEHLER:" .. tostring(perr)) end

local ctl = prof.control
if not (ctl and ctl.manual_only and ctl.conn) then
  out("FEHLER:Profil '" .. pname .. "' erlaubt keine manuelle Steuerung (kein control-Block)")
end

local ip = cfg("ip")
if not ip then out("FEHLER:Slot " .. slot .. " hat keine IP") end
local port = tonumber(cfg("port") or "") or prof.port or 502
local unit = tonumber(cfg("unit") or "") or prof.unit_id or 1

-- ---------- Zieladresse: Scan-Cache oder eigener Scan -----------------------

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

local cp = ctl.conn
local addr = cp.addr
if not addr and cp.model then
  if not (scan and scan.models and scan.models[cp.model]) then
    out("FEHLER:Modell " .. tostring(cp.model) .. " nicht im Scan (erst Poll ausfuehren)")
  end
  addr = scan.models[cp.model].data_start + (cp.offset or 0)
end
if not addr then out("FEHLER:keine Adresse im control-Block") end

local value = (cmd == "on") and (cp.on or 1) or (cp.off or 0)

-- ---------- FC6 Write Single Register ---------------------------------------

local function write_reg(w_ip, w_port, w_unit, w_addr, w_val, timeout)
  if not ok_socket then return nil, "ERR:luasocket fehlt" end
  local c = socket.tcp()
  c:settimeout(timeout or 5)
  local ok, err = c:connect(w_ip, w_port)
  if not ok then c:close() return nil, "ERR:connect " .. tostring(err) end
  local function hi(v) return math.floor(v / 256) % 256 end
  local function lo(v) return v % 256 end
  local pdu = string.char(6, hi(w_addr), lo(w_addr), hi(w_val), lo(w_val))
  c:send(string.char(0, 1, 0, 0, 0, #pdu + 1, w_unit) .. pdu)
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

logline("BEFEHL slot=" .. slot .. " profil=" .. pname .. " ip=" .. ip ..
        " unit=" .. unit .. " cmd=" .. cmd .. " addr=" .. addr .. " val=" .. value)

-- 2 Versuche (NX3 mag keine schnellen Verbindungsfolgen)
local wok, werr
for t = 1, 2 do
  wok, werr = write_reg(ip, port, unit, addr, value, 5)
  if wok then break end
  L.sleep(1)
end

if not wok then
  if tostring(werr):find("^EXC:") then
    out("FEHLER:" .. werr .. " - Schreibzugriff am WR freigeschaltet? (MODBUS/SunSpec-Menue)")
  end
  out("FEHLER:" .. tostring(werr))
end

-- Poll anfordern, damit die Anzeige den neuen Zustand zeigt
local pf = io.open("/tmp/emsproxy_poll_req", "w")
if pf then pf:close() end

out("OK - Befehl '" .. cmd .. "' gesendet (Register " .. addr .. "=" .. value ..
    "). Status aktualisiert sich nach dem naechsten Poll.")
