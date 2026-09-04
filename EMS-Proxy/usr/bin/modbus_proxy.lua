#!/usr/bin/lua
-- =====================================================================
-- EMS Modbus-Proxy fuer Teltonika RUTX11 (RUTOS)
-- Tesvolt EMS (Master, Modbus TCP) -> Proxy -> Tesvolt-Batterie + BLUESUN PCS
--
-- Installationspfad: /usr/local/bin (RUTOS: / ist squashfs read-only!)
--
-- Modi:
--   passthrough : alle Anfragen 1:1 an die Tesvolt-Batterie
--   split       : SetPower wird via powersplit.lua auf beide Batterien
--                 verteilt; BLUESUN erhaelt den Sollwert ueber den
--                 UDAN-EMS Steuerblock 0x1500 (Herstellerfreigabe
--                 2026-09-04, Variante A):
--                   0x1500 ControlMode  = 2 (manuell)
--                   0x1501 SystemState  = 1 Laden / 2 Entladen / 3 Standby
--                   0x1502 ExpectedPower = Betrag in 0.1 kW (u16)
--                   0x1503 ControlPriority = 1 (lokal)
--                   0x1505 PCS Start/Stop  = 1 Start / 2 Stop
--                 Herstellervorgabe: min. 200 ms zwischen Requests.
--
-- Netzanschluss-Limit (nur Split-Modus!):
--   * /etc/tesvolt_grid_max_chg / _dis (kW, Setup-UI) = harte Obergrenze
--   * /etc/tesvolt_grid_use_ems = 1: zusaetzlich EMS-Register 40003/40004
--     lesen; wirksam ist das MINIMUM beider Quellen pro Richtung
--     (ACHTUNG: Einheit/Skalierung der EMS-Register noch NICHT am
--     Geraet verifiziert - Annahme W; Checkbox default AUS)
--   * Im Passthrough-Modus greift der Proxy NICHT in die
--     Tesvolt-Steuerung ein (User-Vorgabe 2026-08-29)
--
-- Simulation (/etc/tesvolt_sim = 1):
--   * Proxy beantwortet ALLE Anfragen selbst mit plausiblen
--     Fantasiewerten - KEINE Verbindung zu echten Geraeten.
--   * FC06/FC16-Schreibwerte werden gemerkt und beim Lesen
--     zurueckgegeben (Roundtrip-Test fuer die UI).
--   * Simulierte Register (Proxy-Adressen, addr = reg-30001):
--       30001 (0)  SOC_T   pendelt ~35..75 %
--       30005 (4)  Power_T pendelt +-18 kW (signed, W)
--       30011 (10) SOC_B   pendelt ~30..66 % (andere Phase)
--       30015 (14) Power_B pendelt +-12 kW (signed, W)
--   * Zum Testen der Status-/Setup-UI ohne angeschlossene Batterien.
--
-- Konfiguration:
--   * KEINE fest kodierten IPs. IPs kommen ausschliesslich aus
--     /etc/tesvolt_ip_t und /etc/tesvolt_ip_b (Setup-UI: setup.html).
--   * BLUESUN Unit-ID: /etc/tesvolt_unit_b (Default 10 lt. Hersteller).
--   * Solange keine IPs konfiguriert sind, antwortet der Proxy mit
--     Modbus-Exception 0x0A (Gateway Path Unavailable) und loggt dies.
--
-- Failsafe (WICHTIG: das UDAN-EMS hat KEINEN eigenen Watchdog!
-- Herstellerantwort 2026-09-04: 'No timeout setting' - ein einmal
-- geschriebener Sollwert bleibt dauerhaft aktiv):
--   * BLUESUN 3x nicht erreichbar -> automatisch passthrough +
--     BLUESUN Standby (0x1501=3, 0x1502=0)
--   * Kein EMS-Sollwert seit > ems_timeout_s -> BLUESUN Standby
--   * Fehler werden nach /var/log/ems_proxy.log geschrieben
-- =====================================================================

local socket = require("socket")
local split  = dofile("/usr/local/bin/powersplit.lua")

-- ------------------------- Konfiguration ----------------------------
local CFG = {
  listen_port = 1502,   -- Port fuer das Tesvolt EMS (Master)
  tesvolt_ip  = nil,    -- NUR aus /etc/tesvolt_ip_t (kein Fallback!)
  bluesun_ip  = nil,    -- NUR aus /etc/tesvolt_ip_b (kein Fallback!)
  modbus_port = 502,
  unit_id     = 1,      -- Unit-ID Tesvolt-Seite
  bluesun_unit = 10,    -- Unit-ID UDAN-EMS (Default lt. Hersteller;
                        -- Override: /etc/tesvolt_unit_b)
  timeout_s   = 2,
  bs_gap_s    = 0.2,    -- Herstellervorgabe: min. 200 ms zwischen
                        -- Requests an das UDAN-EMS
  keepalive_s = 5,      -- unveraenderten Sollwert spaetestens alle 5 s
                        -- erneut schreiben
  ems_timeout_s = 10,   -- kein EMS-Sollwert > 10 s -> BLUESUN Standby
  logfile     = "/var/log/ems_proxy.log",
}

-- BLUESUN/UDAN-EMS Registerkonstanten (EMS/HMI Modbus485 v1.18;
-- Schreibpfad per Herstellerfreigabe 2026-09-04 = Steuerblock 0x1500)
local BS = {
  SOC        = 0x1140,  -- System-SOC (FC04, read-only)
  CTRL_MODE  = 0x1500,  -- ControlMode: 1=Automatik, 2=manuell
  CTRL_STATE = 0x1501,  -- SystemState: 1=Laden, 2=Entladen, 3=Standby
  CTRL_POWER = 0x1502,  -- ExpectedPower: Betrag in 0.1 kW (u16)
  CTRL_PRIO  = 0x1503,  -- ControlPriority: 1=lokal, 2=remote
  PCS_ONOFF  = 0x1505,  -- PCS Start/Stop: 1=Start, 2=Stop
  CHG_LIM    = 0x361D,  -- ChargeLimit_B, x100
  DIS_LIM    = 0x361F,  -- DischargeLimit_B, x100
}

-- EMS-Registeradressen (Proxy-Sicht, siehe docs/Register-Mapping)
local EMS = {
  SOC      = 30001,
  SETPOWER = 30005,  -- Schreibzugriff (FC06)
  CHG_LIM_ADDR = 2,  -- 40003 ChargeLimit_T    (FC03, addr = reg-40001)
  DIS_LIM_ADDR = 3,  -- 40004 DischargeLimit_T (FC03, addr = reg-40001)
}

-- ------------------------- Hilfsfunktionen --------------------------
local function log(msg)
  local f = io.open(CFG.logfile, "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S ") .. msg .. "\n")
    f:close()
  end
end

local function read_file(path, default)
  local f = io.open(path, "r")
  if not f then return default end
  local v = f:read("*l")
  f:close()
  if v == nil or v == "" then return default end
  return v
end

local function get_mode()       return read_file("/etc/tesvolt_proxy_mode", "passthrough") end
local function get_split_mode() return read_file("/etc/tesvolt_split_mode", "capacity") end
local function get_sim()        return read_file("/etc/tesvolt_sim", "0") == "1" end

local function get_caps()
  local ct = tonumber(read_file("/etc/tesvolt_cap_t", "0")) or 0
  local cb = tonumber(read_file("/etc/tesvolt_cap_b", "0")) or 0
  return ct, cb
end

local function load_ips()
  CFG.tesvolt_ip = read_file("/etc/tesvolt_ip_t", nil)
  CFG.bluesun_ip = read_file("/etc/tesvolt_ip_b", nil)
  CFG.bluesun_unit = tonumber(read_file("/etc/tesvolt_unit_b", "10")) or 10
end

local function is_configured()
  return CFG.tesvolt_ip ~= nil
end

-- ------------------------- Modbus TCP Client ------------------------
local function u16(hi, lo) return hi * 256 + lo end
local function b_hi(v) return math.floor(v / 256) % 256 end
local function b_lo(v) return v % 256 end

local tid_counter = 0
local function next_tid()
  tid_counter = (tid_counter + 1) % 65536
  return tid_counter
end

-- Sendet einen Modbus-TCP-Request und liefert die Antwort-PDU
local function mb_request(ip, pdu, unit)
  if ip == nil then return nil, "IP nicht konfiguriert" end
  unit = unit or CFG.unit_id
  local c = socket.tcp()
  c:settimeout(CFG.timeout_s)
  local ok, err = c:connect(ip, CFG.modbus_port)
  if not ok then c:close(); return nil, "connect: " .. tostring(err) end

  local tid = next_tid()
  local mbap = string.char(
    b_hi(tid), b_lo(tid),           -- Transaction ID
    0, 0,                           -- Protocol ID
    b_hi(#pdu + 1), b_lo(#pdu + 1), -- Length
    unit)                           -- Unit ID
  c:send(mbap .. pdu)

  local hdr = c:receive(7)
  if not hdr then c:close(); return nil, "timeout header" end
  local len = u16(hdr:byte(5), hdr:byte(6))
  local body = c:receive(len - 1)
  c:close()
  if not body then return nil, "timeout body" end
  return body
end

-- FC03/FC04: Register lesen -> Zahlenwert (erstes Register)
local function mb_read(ip, fc, addr, count, unit)
  count = count or 1
  local pdu = string.char(fc, b_hi(addr), b_lo(addr), b_hi(count), b_lo(count))
  local resp, err = mb_request(ip, pdu, unit)
  if not resp then return nil, err end
  if resp:byte(1) ~= fc then return nil, "exception " .. tostring(resp:byte(2)) end
  return u16(resp:byte(3), resp:byte(4))
end

-- FC06: Einzelregister schreiben
local function mb_write(ip, addr, value, unit)
  if ip == nil then return nil, "IP nicht konfiguriert" end
  if value < 0 then value = value + 65536 end -- 16-Bit-Zweierkomplement
  local pdu = string.char(6, b_hi(addr), b_lo(addr), b_hi(value), b_lo(value))
  local resp, err = mb_request(ip, pdu, unit)
  if not resp then return nil, err end
  if resp:byte(1) ~= 6 then return nil, "exception " .. tostring(resp:byte(2)) end
  return true
end

-- ------------------- BLUESUN/UDAN-EMS Zugriff -----------------------
-- Alle Zugriffe laufen ueber bs_read/bs_write: erzwingt die
-- Herstellervorgabe von min. 200 ms Abstand zwischen Requests und
-- nutzt die richtige Unit-ID (Default 10).
local last_bs_t = 0
local function bs_throttle()
  local now = socket.gettime()
  local wait = CFG.bs_gap_s - (now - last_bs_t)
  if wait > 0 then socket.sleep(wait) end
  last_bs_t = socket.gettime()
end

local function bs_read(fc, addr)
  bs_throttle()
  return mb_read(CFG.bluesun_ip, fc, addr, 1, CFG.bluesun_unit)
end

local function bs_write(addr, value)
  bs_throttle()
  return mb_write(CFG.bluesun_ip, addr, value, CFG.bluesun_unit)
end

-- Init-Sequenz (einmalig beim Aktivieren der Regelung):
-- 0x1503=1 (lokal: EMS ignoriert Cloud-Plattform) ->
-- 0x1500=2 (manueller Modus) -> 0x1505=1 (PCS starten)
local bs_initialized = false
local function bluesun_init()
  if bs_initialized then return true end
  local ok1, e1 = bs_write(BS.CTRL_PRIO, 1)
  local ok2, e2 = bs_write(BS.CTRL_MODE, 2)
  local ok3, e3 = bs_write(BS.PCS_ONOFF, 1)
  if ok1 and ok2 and ok3 then
    bs_initialized = true
    log("BLUESUN init OK: Prio=lokal, Mode=manuell, PCS=Start")
    return true
  end
  log("BLUESUN init FEHLER: prio=" .. tostring(e1) ..
      " mode=" .. tostring(e2) .. " pcs=" .. tostring(e3))
  return false
end

-- Sollwert schreiben. p_w in W, Vorzeichen wie P_req
-- (>0 = Entladen, <0 = Laden). Kodierung UDAN-EMS:
-- Richtung ueber 0x1501, Betrag in 0.1 kW ueber 0x1502.
-- Unveraenderte Werte werden nur alle keepalive_s erneut geschrieben
-- (Registerschonung), Aenderungen sofort.
local last_bs_state, last_bs_deci = nil, nil
local last_bs_write_t = 0
local function write_bluesun_setpoint(p_w)
  local deci = math.floor(math.abs(p_w) / 100 + 0.5)  -- W -> 0.1 kW
  local state
  if deci == 0 then
    state = 3            -- Standby
  elseif p_w > 0 then
    state = 2            -- Entladen
  else
    state = 1            -- Laden
  end

  local now = socket.gettime()
  if state == last_bs_state and deci == last_bs_deci
     and (now - last_bs_write_t) < CFG.keepalive_s then
    return true -- unveraendert, Keepalive noch nicht faellig
  end

  if not bluesun_init() then return nil, "init fehlgeschlagen" end

  local ok1, e1 = bs_write(BS.CTRL_STATE, state)
  local ok2, e2 = bs_write(BS.CTRL_POWER, deci)
  if ok1 and ok2 then
    last_bs_state, last_bs_deci = state, deci
    last_bs_write_t = socket.gettime()
    return true
  end
  bs_initialized = false -- Init beim naechsten Versuch wiederholen
  return nil, "state=" .. tostring(e1) .. " power=" .. tostring(e2)
end

-- Sicherer Zustand: Standby + 0 kW (das UDAN-EMS hat KEINEN eigenen
-- Watchdog - ohne diesen Aufruf bleibt der letzte Sollwert dauerhaft aktiv!)
local function bluesun_safe_state(reason)
  log("BLUESUN SAFE-STATE (" .. reason .. "): Standby + 0 kW")
  bs_write(BS.CTRL_STATE, 3)
  bs_write(BS.CTRL_POWER, 0)
  last_bs_state, last_bs_deci = 3, 0
  last_bs_write_t = socket.gettime()
end

-- ------------------------- Netzanschluss-Limit ----------------------
-- Liefert { chg = W, dis = W } oder nil (kein Limit gesetzt).
-- Setup-Werte sind kW (Setup-UI); EMS-Register-Werte werden als W
-- angenommen (Skalierung UNVERIFIZIERT - deshalb Checkbox default aus).
-- Wirksam ist pro Richtung das MINIMUM beider Quellen. Faellt die
-- EMS-Abfrage aus, gilt der Setup-Wert (fail-safe).
local function get_grid_limits()
  local chg = tonumber(read_file("/etc/tesvolt_grid_max_chg", ""))
  local dis = tonumber(read_file("/etc/tesvolt_grid_max_dis", ""))
  local use_ems = read_file("/etc/tesvolt_grid_use_ems", "0") == "1"
  local g = {}
  if chg and chg > 0 then g.chg = chg * 1000 end  -- kW -> W
  if dis and dis > 0 then g.dis = dis * 1000 end
  if use_ems then
    local ems_chg = mb_read(CFG.tesvolt_ip, 3, EMS.CHG_LIM_ADDR)
    local ems_dis = mb_read(CFG.tesvolt_ip, 3, EMS.DIS_LIM_ADDR)
    if ems_chg and ems_chg > 0 and (not g.chg or ems_chg < g.chg) then g.chg = ems_chg end
    if ems_dis and ems_dis > 0 and (not g.dis or ems_dis < g.dis) then g.dis = ems_dis end
  end
  if g.chg or g.dis then return g end
  return nil
end

-- ------------------------- Simulation --------------------------------
-- Fantasiewerte fuer UI-Tests ohne echte Geraete.
-- FC06/FC16-Schreibwerte landen in sim_written und werden beim
-- naechsten Lesen zurueckgegeben.
local sim_written = {}

local function sim_value(addr)
  if sim_written[addr] ~= nil then return sim_written[addr] end
  local t = os.time()
  if addr == 0 then
    -- 30001 SOC_T: pendelt langsam zwischen ~35 und ~75 %
    return 55 + math.floor(20 * math.sin(t / 120))
  elseif addr == 4 then
    -- 30005 Power_T: +-18 kW (signed, W); durch FC06 ueberschreibbar
    return math.floor(18000 * math.sin(t / 60))
  elseif addr == 10 then
    -- 30011 SOC_B: pendelt zwischen ~30 und ~66 % (andere Phase als SOC_T)
    return 48 + math.floor(18 * math.sin(t / 90 + 2))
  elseif addr == 14 then
    -- 30015 Power_B: +-12 kW (signed, W)
    return math.floor(12000 * math.sin(t / 75 + 1))
  end
  -- generisch: deterministisch pro Adresse, aendert sich alle 15 s
  return (addr * 13 + math.floor(t / 15) * 7) % 1000
end

local function sim_response(body)
  local fc   = body:byte(1)
  local addr = u16(body:byte(2), body:byte(3))
  if fc == 3 or fc == 4 then
    local count = u16(body:byte(4), body:byte(5))
    if count < 1 or count > 125 then return string.char(fc + 0x80, 3) end
    local data = ""
    for i = 0, count - 1 do
      local v = sim_value(addr + i) % 65536
      data = data .. string.char(b_hi(v), b_lo(v))
    end
    return string.char(fc, count * 2) .. data
  elseif fc == 6 then
    sim_written[addr] = u16(body:byte(4), body:byte(5))
    return body -- Echo gemaess Modbus-Norm FC06
  elseif fc == 16 then
    local count = u16(body:byte(4), body:byte(5))
    for i = 0, count - 1 do
      sim_written[addr + i] = u16(body:byte(7 + i * 2), body:byte(8 + i * 2))
    end
    return string.char(16, body:byte(2), body:byte(3), body:byte(4), body:byte(5))
  end
  return string.char(fc + 0x80, 1) -- Illegal Function
end

-- ------------------------- Split-Logik ------------------------------
local bluesun_fail_count = 0
local BLUESUN_FAIL_LIMIT = 3

-- Zeitstempel des letzten gueltigen EMS-Sollwerts (Failsafe-Basis)
local last_ems_setpoint_t = socket.gettime()
local ems_stale = false

local function read_limits()
  local chg_b = bs_read(3, BS.CHG_LIM)
  local dis_b = bs_read(3, BS.DIS_LIM)
  return {
    chg_b = chg_b and chg_b * 100 or nil,
    dis_b = dis_b and dis_b * 100 or nil,
    chg_t = nil, -- Tesvolt-Limits liefert das EMS selbst
    dis_t = nil,
  }
end

local function failsafe_passthrough(reason)
  log("FAILSAFE: " .. reason .. " -> passthrough + BLUESUN Standby")
  local f = io.open("/etc/tesvolt_proxy_mode", "w")
  if f then f:write("passthrough\n"); f:close() end
  bluesun_safe_state(reason)
end

-- Verarbeitet einen Schreibbefehl des EMS auf das SetPower-Register
local function handle_setpower(p_req)
  last_ems_setpoint_t = socket.gettime()
  ems_stale = false

  local mode = get_mode()
  if mode ~= "split" or CFG.bluesun_ip == nil then
    if mode == "split" and CFG.bluesun_ip == nil then
      log("SPLIT angefordert, aber BLUESUN-IP nicht konfiguriert -> passthrough")
    end
    -- Passthrough: KEIN Eingriff in die Tesvolt-Steuerung (User-Vorgabe)
    return mb_write(CFG.tesvolt_ip, EMS.SETPOWER, p_req)
  end

  local soc_t = mb_read(CFG.tesvolt_ip, 4, EMS.SOC) or 0
  local soc_b = bs_read(4, BS.SOC)

  if soc_b == nil then
    bluesun_fail_count = bluesun_fail_count + 1
    log("BLUESUN SOC nicht lesbar (" .. bluesun_fail_count .. "/" .. BLUESUN_FAIL_LIMIT .. ")")
    if bluesun_fail_count >= BLUESUN_FAIL_LIMIT then
      failsafe_passthrough("BLUESUN " .. BLUESUN_FAIL_LIMIT .. "x nicht erreichbar")
    end
    return mb_write(CFG.tesvolt_ip, EMS.SETPOWER, p_req)
  end
  bluesun_fail_count = 0

  local cap_t, cap_b = get_caps()
  local limits = read_limits()
  local grid   = get_grid_limits()
  local p_t, p_b = split.split_power(p_req, soc_t, soc_b, cap_t, cap_b,
                                     "split", get_split_mode(), limits, grid)

  -- Geclampte Anfragen loggen (Netzanschluss-Schutz)
  local sum = math.abs(p_t + p_b)
  if grid and sum + 1 < math.abs(p_req) then
    log(string.format("GRIDLIMIT: Anfrage %dW auf %dW begrenzt (chg=%s dis=%s)",
        p_req, math.floor(p_t + p_b),
        tostring(grid.chg), tostring(grid.dis)))
  end

  local ok1, e1 = mb_write(CFG.tesvolt_ip, EMS.SETPOWER, math.floor(p_t))
  local ok2, e2 = write_bluesun_setpoint(math.floor(p_b))

  log(string.format("SPLIT req=%dW -> T=%dW B=%dW (soc_t=%d soc_b=%d)",
      p_req, p_t, p_b, soc_t, soc_b))

  if not ok1 then log("Tesvolt write error: " .. tostring(e1)) end
  if not ok2 then log("BLUESUN write error: " .. tostring(e2)) end
  return ok1
end

-- ------------------------- Modbus TCP Server ------------------------
local unconfigured_logged = false
local sim_logged = false

local function serve()
  load_ips()
  local server = assert(socket.bind("0.0.0.0", CFG.listen_port))
  server:settimeout(1)
  log("EMS-Proxy gestartet auf Port " .. CFG.listen_port ..
      " (Tesvolt=" .. tostring(CFG.tesvolt_ip) ..
      ", BLUESUN=" .. tostring(CFG.bluesun_ip) ..
      ", BS-Unit=" .. tostring(CFG.bluesun_unit) ..
      (get_sim() and ", SIMULATION AKTIV" or "") .. ")")
  if not get_sim() and not is_configured() then
    log("WARNUNG: IPs nicht konfiguriert - bitte Setup aufrufen (setup.html). " ..
        "Alle Anfragen werden mit Exception 0x0A beantwortet.")
  end

  while true do
    local client = server:accept()
    if client then
      client:settimeout(CFG.timeout_s)
      local hdr = client:receive(7)
      if hdr then
        local len  = u16(hdr:byte(5), hdr:byte(6))
        local body = client:receive(len - 1)
        if body then
          local fc   = body:byte(1)
          local addr = u16(body:byte(2), body:byte(3))
          local resp_pdu

          -- IPs bei jedem Request nachladen, falls noch unkonfiguriert
          -- (Setup-UI kann so ohne Proxy-Neustart aktivieren)
          if not is_configured() then load_ips() end

          if get_sim() then
            -- Simulationsmodus: Fantasiewerte, keine Geraete noetig
            if not sim_logged then
              log("SIMULATION: beantworte Anfragen mit Fantasiewerten")
              sim_logged = true
            end
            resp_pdu = sim_response(body)
          elseif not is_configured() then
            if not unconfigured_logged then
              log("Anfrage abgelehnt: IPs nicht konfiguriert (Exception 0x0A)")
              unconfigured_logged = true
            end
            resp_pdu = string.char(fc + 0x80, 0x0A) -- Gateway Path Unavailable
          elseif fc == 6 and addr == EMS.SETPOWER then
            local val = u16(body:byte(4), body:byte(5))
            if val > 32767 then val = val - 65536 end
            handle_setpower(val)
            resp_pdu = body -- Echo gemaess Modbus-Norm FC06
          else
            local resp, err = mb_request(CFG.tesvolt_ip, body)
            if resp then
              resp_pdu = resp
            else
              log("Passthrough-Fehler FC" .. fc .. " addr " .. addr .. ": " .. tostring(err))
              resp_pdu = string.char(fc + 0x80, 0x0B) -- Gateway Target Failed
            end
          end

          local out_len = #resp_pdu + 1
          client:send(hdr:sub(1, 4) ..
                      string.char(b_hi(out_len), b_lo(out_len)) ..
                      hdr:sub(7, 7) .. resp_pdu)
        end
      end
      client:close()
    else
      -- Keine EMS-Anfrage in diesem Zyklus: Failsafe pruefen.
      -- Das UDAN-EMS hat KEINEN eigenen Watchdog - ohne diese Sicherung
      -- wuerde der letzte Sollwert bei EMS-Ausfall dauerhaft weiterlaufen!
      if not get_sim() and get_mode() == "split"
         and CFG.bluesun_ip ~= nil and bs_initialized and not ems_stale
         and (socket.gettime() - last_ems_setpoint_t) > CFG.ems_timeout_s then
        bluesun_safe_state("kein EMS-Sollwert seit " ..
                           CFG.ems_timeout_s .. " s")
        ems_stale = true
      end
    end
  end
end

-- ------------------------- Start ------------------------------------
local ok, err = pcall(serve)
if not ok then
  log("FATAL: " .. tostring(err))
  os.exit(1)
end
