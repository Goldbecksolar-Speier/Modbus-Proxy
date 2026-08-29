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
--                 verteilt; BLUESUN erhaelt SetPower_B (0x1144, x100)
--                 und Mode (0x1143)
--
-- Konfiguration:
--   * KEINE fest kodierten IPs. IPs kommen ausschliesslich aus
--     /etc/tesvolt_ip_t und /etc/tesvolt_ip_b (Setup-UI: setup.html).
--   * Solange keine IPs konfiguriert sind, antwortet der Proxy mit
--     Modbus-Exception 0x0A (Gateway Path Unavailable) und loggt dies.
--
-- Failsafe:
--   * BLUESUN 3x nicht erreichbar -> automatisch passthrough + SetPower_B=0
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
  unit_id     = 1,
  timeout_s   = 2,
  logfile     = "/var/log/ems_proxy.log",
}

-- BLUESUN-Registerkonstanten (siehe 0-EMS/HMI Modbus485 v1.18)
local BS = {
  SOC      = 0x1140,  -- SOC_B
  SETPOWER = 0x1144,  -- SetPower_B, Skalierung x100
  MODE     = 0x1143,  -- Betriebsmodus
  CHG_LIM  = 0x361D,  -- ChargeLimit_B, x100
  DIS_LIM  = 0x361F,  -- DischargeLimit_B, x100
}

-- EMS-Registeradressen (Proxy-Sicht, siehe docs/Register-Mapping)
local EMS = {
  SOC      = 30001,
  SETPOWER = 30005,  -- Schreibzugriff (FC06)
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

local function get_caps()
  local ct = tonumber(read_file("/etc/tesvolt_cap_t", "0")) or 0
  local cb = tonumber(read_file("/etc/tesvolt_cap_b", "0")) or 0
  return ct, cb
end

local function load_ips()
  CFG.tesvolt_ip = read_file("/etc/tesvolt_ip_t", nil)
  CFG.bluesun_ip = read_file("/etc/tesvolt_ip_b", nil)
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
local function mb_request(ip, pdu)
  if ip == nil then return nil, "IP nicht konfiguriert" end
  local c = socket.tcp()
  c:settimeout(CFG.timeout_s)
  local ok, err = c:connect(ip, CFG.modbus_port)
  if not ok then c:close(); return nil, "connect: " .. tostring(err) end

  local tid = next_tid()
  local mbap = string.char(
    b_hi(tid), b_lo(tid),           -- Transaction ID
    0, 0,                           -- Protocol ID
    b_hi(#pdu + 1), b_lo(#pdu + 1), -- Length
    CFG.unit_id)                    -- Unit ID
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
local function mb_read(ip, fc, addr, count)
  count = count or 1
  local pdu = string.char(fc, b_hi(addr), b_lo(addr), b_hi(count), b_lo(count))
  local resp, err = mb_request(ip, pdu)
  if not resp then return nil, err end
  if resp:byte(1) ~= fc then return nil, "exception " .. tostring(resp:byte(2)) end
  return u16(resp:byte(3), resp:byte(4))
end

-- FC06: Einzelregister schreiben
local function mb_write(ip, addr, value)
  if ip == nil then return nil, "IP nicht konfiguriert" end
  if value < 0 then value = value + 65536 end -- 16-Bit-Zweierkomplement
  local pdu = string.char(6, b_hi(addr), b_lo(addr), b_hi(value), b_lo(value))
  local resp, err = mb_request(ip, pdu)
  if not resp then return nil, err end
  if resp:byte(1) ~= 6 then return nil, "exception " .. tostring(resp:byte(2)) end
  return true
end

-- ------------------------- Split-Logik ------------------------------
local bluesun_fail_count = 0
local BLUESUN_FAIL_LIMIT = 3

local function read_limits()
  local chg_b = mb_read(CFG.bluesun_ip, 3, BS.CHG_LIM)
  local dis_b = mb_read(CFG.bluesun_ip, 3, BS.DIS_LIM)
  return {
    chg_b = chg_b and chg_b * 100 or nil,
    dis_b = dis_b and dis_b * 100 or nil,
    chg_t = nil, -- Tesvolt-Limits liefert das EMS selbst
    dis_t = nil,
  }
end

local function failsafe_passthrough(reason)
  log("FAILSAFE: " .. reason .. " -> passthrough, SetPower_B=0")
  local f = io.open("/etc/tesvolt_proxy_mode", "w")
  if f then f:write("passthrough\n"); f:close() end
  mb_write(CFG.bluesun_ip, BS.SETPOWER, 0)
end

-- Verarbeitet einen Schreibbefehl des EMS auf das SetPower-Register
local function handle_setpower(p_req)
  local mode = get_mode()
  if mode ~= "split" or CFG.bluesun_ip == nil then
    if mode == "split" and CFG.bluesun_ip == nil then
      log("SPLIT angefordert, aber BLUESUN-IP nicht konfiguriert -> passthrough")
    end
    return mb_write(CFG.tesvolt_ip, EMS.SETPOWER, p_req)
  end

  local soc_t = mb_read(CFG.tesvolt_ip, 4, EMS.SOC) or 0
  local soc_b = mb_read(CFG.bluesun_ip, 3, BS.SOC)

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
  local p_t, p_b = split.split_power(p_req, soc_t, soc_b, cap_t, cap_b,
                                     "split", get_split_mode(), limits)

  local ok1, e1 = mb_write(CFG.tesvolt_ip, EMS.SETPOWER, math.floor(p_t))
  local ok2, e2 = mb_write(CFG.bluesun_ip, BS.SETPOWER, math.floor(p_b / 100))
  mb_write(CFG.bluesun_ip, BS.MODE, 1)

  log(string.format("SPLIT req=%dW -> T=%dW B=%dW (soc_t=%d soc_b=%d)",
      p_req, p_t, p_b, soc_t, soc_b))

  if not ok1 then log("Tesvolt write error: " .. tostring(e1)) end
  if not ok2 then log("BLUESUN write error: " .. tostring(e2)) end
  return ok1
end

-- ------------------------- Modbus TCP Server ------------------------
local unconfigured_logged = false

local function serve()
  load_ips()
  local server = assert(socket.bind("0.0.0.0", CFG.listen_port))
  server:settimeout(1)
  log("EMS-Proxy gestartet auf Port " .. CFG.listen_port ..
      " (Tesvolt=" .. tostring(CFG.tesvolt_ip) ..
      ", BLUESUN=" .. tostring(CFG.bluesun_ip) .. ")")
  if not is_configured() then
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

          if not is_configured() then
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
    end
  end
end

-- ------------------------- Start ------------------------------------
local ok, err = pcall(serve)
if not ok then
  log("FATAL: " .. tostring(err))
  os.exit(1)
end
