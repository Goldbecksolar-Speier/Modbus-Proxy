-- =====================================================================
-- sunspec_diag.lua - SunSpec-Diagnose (READ-ONLY)
--
-- Aufruf: lua /usr/local/bin/sunspec_diag.lua <ip> [port] [unit] [modell]
-- Beispiele:
--   lua /usr/local/bin/sunspec_diag.lua 192.168.20.171 502 3
--   lua /usr/local/bin/sunspec_diag.lua 192.168.20.171 502 3 103
--
-- Ohne 4. Argument: Marker-Test + Modell-Ketten-Walk.
-- Mit 4. Argument:  zusaetzlich ROH-DUMP des Modells - jedes Register
--                   als offset / u16 / s16 (fuer Offset-Verifikation).
-- =====================================================================

local L = dofile("/usr/local/bin/profile_loader.lua")

local ip    = arg and arg[1]
local port  = tonumber(arg and arg[2]) or 502
local unit  = tonumber(arg and arg[3]) or 1
local dumpm = tonumber(arg and arg[4])
local TMO   = 5

if not ip then
  print("Aufruf: lua sunspec_diag.lua <ip> [port] [unit] [modell]")
  os.exit(1)
end

print("Ziel: " .. ip .. ":" .. port .. " unit " .. unit)

local function read_retry(addr, count)
  local last
  for t = 1, 3 do
    local w, e = L.read_regs(ip, port, unit, 3, addr, count, TMO)
    if w then return w end
    last = e
    L.sleep(1)
  end
  return nil, last
end

print("-- Schritt 1: Marker-Read auf 40000 --")
local w, e = read_retry(40000, 2)
if not (w and w[1] == 0x5375 and w[2] == 0x6E53) then
  print("ABBRUCH: kein SunS-Marker auf 40000: " .. tostring(e))
  os.exit(1)
end
print("SunS-Marker OK")
local base = 40000

print("-- Schritt 2: Modell-Ketten-Walk ab " .. (base + 2) .. " --")
local models = {}
local addr = base + 2
for n = 1, 60 do
  L.sleep(0.5)
  local h, he = read_retry(addr, 2)
  if not h then
    print("ABBRUCH bei addr=" .. addr .. ": " .. tostring(he))
    os.exit(1)
  end
  local id, len = h[1], h[2]
  if id == 0xFFFF then
    print("ENDE der Kette (0xFFFF) bei addr=" .. addr)
    break
  end
  models[id] = { data_start = addr + 2, len = len }
  print("MODEL=" .. id .. " header=" .. addr .. " data_start=" .. (addr + 2)
        .. " len=" .. len)
  addr = addr + 2 + len
end

if not dumpm then
  print("Scan fertig. (Modell-Dump: 4. Argument = Modell-ID)")
  os.exit(0)
end

local m = models[dumpm]
if not m then
  print("Modell " .. dumpm .. " nicht in der Kette!")
  os.exit(1)
end

print("-- Schritt 3: ROH-DUMP Modell " .. dumpm .. " (data_start=" ..
      m.data_start .. " len=" .. m.len .. ") --")
print("offset | addr  | u16    | s16")
local pos = 0
while pos < m.len do
  local n = math.min(20, m.len - pos)
  L.sleep(0.5)
  local ww, we = read_retry(m.data_start + pos, n)
  if not ww then
    print("Dump-Abbruch bei offset=" .. pos .. ": " .. tostring(we))
    os.exit(1)
  end
  for i = 1, n do
    local u = ww[i]
    local s = u
    if s > 32767 then s = s - 65536 end
    print(string.format("%6d | %5d | %6d | %6d",
          pos + i - 1, m.data_start + pos + i - 1, u, s))
  end
  pos = pos + n
end
print("Dump fertig.")
