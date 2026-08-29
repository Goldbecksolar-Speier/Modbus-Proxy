-- PowerSplit Engine (Skeleton)
function split_power(P_req, SOC_T, SOC_B, Cap_T, Cap_B, mode, split_mode)
  if mode == "passthrough" then
    return P_req, 0
  end

  local sign = (P_req >= 0) and 1 or -1
  local P_abs = math.abs(P_req)

  local P_T, P_B

  if split_mode == "capacity" then
    P_T = P_abs * (Cap_T / (Cap_T + Cap_B))
  else
    local E_T = Cap_T * SOC_T
    local E_B = Cap_B * SOC_B
    P_T = P_abs * (E_T / (E_T + E_B))
  end

  P_B = P_abs - P_T

  return P_T * sign, P_B * sign
end
