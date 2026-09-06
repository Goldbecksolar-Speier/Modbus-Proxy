-- =====================================================================
-- Profil: Janitza UMG 604 (Netzanschlusszaehler, OHNE 'Pro')
-- Standort: Hebauer (Brand nutzt UMG 604 Pro - Registerlage lt. Doku
-- weitgehend identisch). Phase 1: NUR LESEN - kein write-Block!
--
-- Quelle: janitza-mal/bhb-umg604 (Knowledge): Modbus TCP Port 502,
-- Wirkleistung Summe Psum = Register 19026, Float32 BIG-ENDIAN.
-- STATUS: am Geraet noch NICHT verifiziert (offener Punkt) -
-- insbesondere Word-Order des Float32 und Unit-ID pruefen.
-- =====================================================================

return {
  id           = "janitza_umg604",
  name         = "Janitza UMG 604 (Netzzaehler)",
  role         = "meter",
  unit_id      = 1,        -- Default; am Geraet verifizieren
  min_gap_ms   = 100,
  has_watchdog = true,     -- irrelevant, read-only
  unverified   = true,     -- Verifikation Psum/Word-Order offen

  read = {
    p_sum = { addr = 19026, fc = 3, type = "f32be", scale = 1, unit = "W" },  -- Wirkleistung Summe
    p_l1  = { addr = 19020, fc = 3, type = "f32be", scale = 1, unit = "W" },  -- (Doku-Lage; verifizieren)
    p_l2  = { addr = 19022, fc = 3, type = "f32be", scale = 1, unit = "W" },
    p_l3  = { addr = 19024, fc = 3, type = "f32be", scale = 1, unit = "W" },
  },

  ui = {
    plaus = { p_sum = { -150000, 150000 } },
  },

  -- KEIN write-Block: read-only.
}
