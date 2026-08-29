-- =====================================================================
-- PowerSplit Engine (optimiert)
-- Teilt die vom Tesvolt EMS angeforderte Leistung auf Tesvolt- und
-- BLUESUN-Batterie auf. Split nach 'capacity' oder 'soc'.
--
-- Optimierungen gegenueber Skeleton:
--  * Division-durch-Null-Schutz (Cap/Energy = 0)
--  * SOC-Plausibilisierung (0..100)
--  * Limit-Clamping gegen Charge-/Discharge-Limits beider Batterien
--  * Rest-Umverteilung: wird eine Seite geclampt, uebernimmt die andere
--    Seite den Rest bis zu ihrem eigenen Limit
--  * Ladefall: Gewichtung nach freier Energie (100-SOC), nicht nach SOC
-- =====================================================================

local M = {}

local function clampval(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- P_req    : angeforderte Gesamtleistung in W (>0 = Entladen, <0 = Laden)
-- SOC_T/B  : State of Charge in % (0..100)
-- Cap_T/B  : Kapazitaet in kWh
-- mode     : "passthrough" | "split"
-- split_mode : "capacity" | "soc"
-- limits   : optionale Tabelle { chg_t, dis_t, chg_b, dis_b } (W, positiv)
-- Rueckgabe: P_T, P_B (mit Vorzeichen wie P_req)
function M.split_power(P_req, SOC_T, SOC_B, Cap_T, Cap_B, mode, split_mode, limits)
  if mode == "passthrough" then
    return P_req, 0
  end

  SOC_T = clampval(tonumber(SOC_T) or 0, 0, 100)
  SOC_B = clampval(tonumber(SOC_B) or 0, 0, 100)
  Cap_T = math.max(tonumber(Cap_T) or 0, 0)
  Cap_B = math.max(tonumber(Cap_B) or 0, 0)

  local sign  = (P_req >= 0) and 1 or -1
  local P_abs = math.abs(P_req)

  local w_t
  if split_mode == "capacity" then
    local total = Cap_T + Cap_B
    if total <= 0 then
      w_t = 1  -- keine Kapazitaetsdaten -> alles auf Tesvolt (sicherer Default)
    else
      w_t = Cap_T / total
    end
  else -- "soc": Gewichtung nach nutzbarer Energie
    local E_T, E_B
    if sign >= 0 then
      E_T = Cap_T * SOC_T          -- Entladen: verfuegbare Energie
      E_B = Cap_B * SOC_B
    else
      E_T = Cap_T * (100 - SOC_T)  -- Laden: freie Energie
      E_B = Cap_B * (100 - SOC_B)
    end
    local total = E_T + E_B
    if total <= 0 then
      w_t = 1
    else
      w_t = E_T / total
    end
  end

  local P_T = P_abs * w_t
  local P_B = P_abs - P_T

  if limits then
    local lim_t = (sign >= 0) and (limits.dis_t or math.huge) or (limits.chg_t or math.huge)
    local lim_b = (sign >= 0) and (limits.dis_b or math.huge) or (limits.chg_b or math.huge)

    if P_T > lim_t then
      local rest = P_T - lim_t
      P_T = lim_t
      P_B = math.min(P_B + rest, lim_b)
    end
    if P_B > lim_b then
      local rest = P_B - lim_b
      P_B = lim_b
      P_T = math.min(P_T + rest, lim_t)
    end
  end

  return P_T * sign, P_B * sign
end

return M
