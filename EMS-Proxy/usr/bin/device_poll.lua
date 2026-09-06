#!/usr/bin/lua
-- =====================================================================
-- device_poll.lua - Read-only-Poller fuer Geraeteprofile (Slots 1..4)
--
-- Aufruf:
--   lua /usr/local/bin/device_poll.lua        alle belegten Slots pollen
--   lua /usr/local/bin/device_poll.lua 2      nur Slot 2
--
-- Slot-Konfiguration (durch Setup-UI / manuell):
--   /etc/tesvolt_devN_profile   Profilname ohne .lua (z.B. solis_s6_hybrid)
--   /etc/tesvolt_devN_ip        Geraete-IP (PFLICHT)
--   /etc/tesvolt_devN_port      optional (Default: Profil bzw. 502)
--   /etc/tesvolt_devN_unit      optional (Default: Profil-unit_id bzw. 1)
--   /etc/tesvolt_devN_en        optional 0/1 (Default 1; 0 = Slot aus)
--
-- Ausgabe: /tmp/emsproxy_devN_status (key=value, atomar via rename)
--   fuer CGIs/status.html; Fehler je Punkt als err_<name>=EXC:/ERR:/NA:
-- SunSpec-Scan-Cache: /tmp/emsproxy_devN_scan (RAM; nach Reboot neu)
--   Cache loeschen erzwingt Neu-Scan (z.B. nach Firmware-Update).
--
-- STRIKT READ-ONLY: schreibt niemals in Geraete. Profile mit
-- write-Block werden abgewiesen (Phase-1-Sicherheitsregel).
-- =====================================================================

local L = dofile("/usr/local/bin/profile_loader.lua")

local function cfg(n, key)
  return L.read_file("/etc/tesvolt_dev" .. n .. "_" .. key)
end

local function fmt(v)
  if type(v) ~= "number" then return tostring(v) end
  if v == math.floor(v) and math.abs(v) < 1e14 then
    return string.format("%d", v)
  end
  return string.format("%.3f", v)
end

local function write_status(n, lines)
  local tmp = "/tmp/emsproxy_dev" .. n .. "_status.tmp"
  local dst = "/tmp/emsproxy_dev" .. n .. "_status"
  local f = io.open(tmp, "w")
  if not f then return end
  f:write(table.concat(lines, "\n"), "\n")
  f:close()
  os.rename(tmp, dst)
end

local function load_scan_cache(n)
  local f = io.open("/tmp/emsproxy_dev" .. n .. "_scan", "r")
  if not f then return nil end
  local scan = { models = {} }
  for line in f:lines() do
    local mid, ds, len = line:match("^(%d+)=(%d+),(%d+)$")
    if mid then
      scan.models[tonumber(mid)] = {
        data_start = tonumber(ds), len = tonumber(len),
      }
    end
  end
  f:close()
  if next(scan.models) then return scan end
  return nil
end

local function save_scan_cache(n, scan)
  local f = io.open("/tmp/emsproxy_dev" .. n .. "_scan", "w")
  if not f then return end
  for mid, m in pairs(scan.models) do
    f:write(mid, "=", m.data_start, ",", m.len, "\n")
  end
  f:close()
end

-- Rueckgabe: true = Slot belegt (Status geschrieben), nil = Slot leer
local function poll_slot(n)
  local name = cfg(n, "profile")
  if not name then return nil end

  local lines = { "ts=" .. os.time(), "slot=" .. n, "profile=" .. name }

  if cfg(n, "en") == "0" then
    lines[#lines + 1] = "enabled=0"
    write_status(n, lines)
    return true
  end
  lines[#lines + 1] = "enabled=1"

  local prof, perr = L.load_profile(name)
  if not prof then
    lines[#lines + 1] = "error=" .. perr
    write_status(n, lines)
    return true
  end
  if prof.write then
    -- Phase-1-Regel: Profile mit write-Block werden NICHT gepollt
    lines[#lines + 1] = "error=ERR:Profil hat write-Block - Phase 1 verbietet Schreibprofile"
    write_status(n, lines)
    return true
  end
  local ip = cfg(n, "ip")
  if not ip then
    lines[#lines + 1] = "error=ERR:keine IP (/etc/tesvolt_dev" .. n .. "_ip)"
    write_status(n, lines)
    return true
  end

  local dev = {
    ip   = ip,
    port = tonumber(cfg(n, "port") or "") or prof.port or 502,
    unit = tonumber(cfg(n, "unit") or "") or prof.unit_id or 1,
  }
  if prof.unverified then lines[#lines + 1] = "unverified=1" end

  -- SunSpec Model Scan (falls das Profil ihn verlangt, z.B. Kaco NX3)
  local scan
  if prof.sunspec and prof.sunspec.scan_required then
    scan = load_scan_cache(n)
    if not scan then
      local s, serr = L.sunspec_scan(dev.ip, dev.port, dev.unit, prof.sunspec)
      if not s then
        lines[#lines + 1] = "error=" .. (serr or "ERR:Scan fehlgeschlagen")
        write_status(n, lines)
        return true
      end
      scan = s
      save_scan_cache(n, scan)
      lines[#lines + 1] = "scan_base=" .. s.base
    end
  end

  local gap = (prof.min_gap_ms or 100) / 1000
  local sf_cache = {}
  local okc, errc = 0, 0
  for pname, p in pairs(prof.read or {}) do
    local v, err = L.read_point(dev, prof, p, scan, sf_cache)
    if v ~= nil then
      lines[#lines + 1] = pname .. "=" .. fmt(v)
      okc = okc + 1
    else
      lines[#lines + 1] = "err_" .. pname .. "=" .. (err or "?")
      errc = errc + 1
    end
    L.sleep(gap) -- Herstellervorgabe min_gap_ms einhalten
  end
  lines[#lines + 1] = "points_ok=" .. okc
  lines[#lines + 1] = "points_err=" .. errc
  write_status(n, lines)
  return true
end

-- ---------- main -----------------------------------------------------------

local slot = tonumber(arg and arg[1] or nil)
if slot then
  if not poll_slot(slot) then
    print("Slot " .. slot .. " nicht belegt (/etc/tesvolt_dev" .. slot .. "_profile fehlt)")
  else
    print("OK: Slot " .. slot .. " -> /tmp/emsproxy_dev" .. slot .. "_status")
  end
else
  local count = 0
  for n = 1, 4 do
    if poll_slot(n) then count = count + 1 end
  end
  if count == 0 then
    print("Keine Geraeteslots konfiguriert (/etc/tesvolt_devN_profile fehlt)")
  else
    print("OK: " .. count .. " Slot(s) gepollt -> /tmp/emsproxy_devN_status")
  end
end
