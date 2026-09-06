-- =====================================================================
-- Profil: Janitza UMG 604 (Netzanschlusszaehler, OHNE 'Pro')
-- Standort: Hebauer (Brand nutzt UMG 604 Pro - Registerlage lt. Doku
-- weitgehend identisch). Phase 1: NUR LESEN - kein write-Block!
--
-- Quelle: janitza-mal/bhb-umg604 (Knowledge): Modbus TCP Port 502,
-- Float32-Block ab 19000: 19000/19002/19004 = UL1/UL2/UL3-N,
-- 19020/19022/19024 = P L1/L2/L3, 19026 = Psum. Alles BIG-ENDIAN.
-- STATUS Verifikation am Geraet (2026-09-06): P-Werte intern
-- konsistent (L1+L2+L3 ~ Psum) -> f32be/Word-Order OK;
-- Display-Vergleich (Absolutwerte) noch offen.
-- =====================================================================

return {
  id           = "janitza_umg604",
  name         = "Janitza UMG 604 (Netzzaehler)",
  role         = "meter",
  unit_id      = 1,        -- Default; am Geraet verifizieren
  min_gap_ms   = 100,
  has_watchdog = true,     -- irrelevant, read-only
  unverified   = true,     -- Display-Vergleich der Absolutwerte offen

  read = {
    u_l1n = { addr = 19000, fc = 3, type = "f32be", scale = 1, unit = "V" },  -- Spannung L1-N
    u_l2n = { addr = 19002, fc = 3, type = "f32be", scale = 1, unit = "V" },  -- Spannung L2-N
    u_l3n = { addr = 19004, fc = 3, type = "f32be", scale = 1, unit = "V" },  -- Spannung L3-N
    p_sum = { addr = 19026, fc = 3, type = "f32be", scale = 1, unit = "W" },  -- Wirkleistung Summe
    p_l1  = { addr = 19020, fc = 3, type = "f32be", scale = 1, unit = "W" },
    p_l2  = { addr = 19022, fc = 3, type = "f32be", scale = 1, unit = "W" },
    p_l3  = { addr = 19024, fc = 3, type = "f32be", scale = 1, unit = "W" },
  },

  ui = {
    plaus = { p_sum = { -150000, 150000 }, u_l1n = { 180, 260 } },
  },

  -- KEIN write-Block: read-only.
}
