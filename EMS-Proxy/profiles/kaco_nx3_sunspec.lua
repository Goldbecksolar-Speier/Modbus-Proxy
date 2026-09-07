-- =====================================================================
-- Profil: Kaco blueplanet NX3 10 kW (PV-Wechselrichter)
-- Standort: Hebauer. Phase 1: NUR LESEN - kein write-Block!
--
-- QUELLEN:
--  * KACO blueplanet NX1/NX3 SunSpec-Implementierungsliste
--    (Firmware V07 bis V.xy, Modbus TCP + RTU)
--  * SunSpec Device Information Model Specification v1.2.1
--
-- SCAN-ERGEBNIS AM GERAET (2026-09-07, 192.168.20.171:502 unit 3):
--    Basis 40000, Kette: 1(len 66) 103(len 50) 120 121 123 160(len 48)
--    701(len 153) 702 704 714 715, Ende 0xFFFF bei 40611
--    -> Modell 103 data_start=40072 (nur zur Info, NICHT hart kodieren!)
--    WICHTIG: Der NX3 quittiert schnelle TCP-Verbindungsfolgen mit
--    Timeout -> Scan/Reads brauchen Retry + Pausen (profile_loader).
--
-- WICHTIG (KACO-Vorgabe): KEINE festen absoluten Registeradressen
-- verwenden - die Adressen gelten nur fuer eine konkrete Firmware!
-- Modelle und Startadressen MUESSEN per SunSpec Model Scan zur
-- Laufzeit ermittelt werden. Deshalb enthaelt dieses Profil nur
-- Modell-relative Offsets (model + offset), keine Absolutadressen.
-- Schreibzugriff erfordert bei KACO eine separate Aktivierung am
-- Geraet - fuer Phase 1 (read-only) irrelevant.
--
-- OFFSET-KONVENTION: offset zaehlt ab DATENBEGINN des Modells
-- (data_start = Header-Adresse + 2, also NACH ID+Laenge).
-- Modell 103 datenrelativ: A=0 A_SF=4 PhVphA=8 V_SF=11
--   W=12 W_SF=13 Hz=14 Hz_SF=15 VA=16 WH=22 DCW=29 TmpCab=31 St=36
--
-- SunSpec-Regeln (Spec v1.2.1):
--  * "SunS"-Marker (0x53756E53) an Adresse 0, 40000 ODER 50000.
--  * Modellkette: je Modell [ID u16][Laenge u16][Daten...];
--    Ende = Modell-ID 0xFFFF.
--  * sunssf: s16, -10..+10, NOT IMPLEMENTED = 0x8000.
--    Echtwert = Rohwert * 10^SF. SF ist statisch -> beim Start
--    lesen und cachen.
--  * NOT-IMPLEMENTED-Sentinels: u16=0xFFFF, s16=0x8000,
--    u32=0xFFFFFFFF, s32=0x80000000 -> als "kein Wert" verwerfen.
-- =====================================================================

return {
  id           = "kaco_nx3_sunspec",
  name         = "Kaco blueplanet NX3 10kW (SunSpec Model Scan)",
  role         = "inverter",
  conn         = "tcp",
  port         = 502,
  unit_id      = 3,        -- AM GERAET VERIFIZIERT 2026-09-07 (nicht 1/126!)
  min_gap_ms   = 300,      -- NX3 mag keine schnellen Verbindungsfolgen
  has_watchdog = true,     -- irrelevant, read-only
  unverified   = true,     -- bis Messwerte am Geraet plausibel bestaetigt

  -- SunSpec-Discovery: der Profil-Loader MUSS scannen (KACO-Vorgabe).
  sunspec = {
    scan_required   = true,                  -- keine Absolutadressen!
    base_candidates = { 40000, 0, 50000 },   -- "SunS"-Marker suchen
    end_model_id    = 0xFFFF,                -- Kettenende
    scan_timeout    = 5,                     -- NX3 braucht lange Timeouts
    sf_not_impl     = 0x8000,                -- sunssf NOT IMPLEMENTED
    sf_static       = true,                  -- SF einmalig lesen + cachen
    -- Am Geraet bestaetigte Modelle (Scan 2026-09-07):
    models_expected = { 1, 103, 120, 121, 123, 160, 701, 702, 704, 714, 715 },
  },

  -- Messpunkte MODELL-RELATIV: model = SunSpec-Modell-ID,
  -- offset = Register-Offset ab Modell-DATENBEGINN (nach ID+Laenge).
  -- Absolutadresse = ScanErgebnis(model).data_start + offset.
  read = {
    -- Modell 103 datenrelativ: W(12) W_SF(13) Hz(14) Hz_SF(15) St(36)
    ac_power = { model = 103, offset = 12, fc = 3, type = "s16", unit = "W",
                 sf_offset = 13, not_impl = 0x8000 },
    ac_freq  = { model = 103, offset = 14, fc = 3, type = "u16", unit = "Hz",
                 sf_offset = 15, not_impl = 0xFFFF },
    status   = { model = 103, offset = 36, fc = 3, type = "u16", unit = "",
                 not_impl = 0xFFFF },  -- St (enum16): 4=MPPT/normal
  },

  ui = {
    plaus = { ac_power = { -1000, 12000 }, ac_freq = { 45, 55 } },
  },

  -- KEIN write-Block: read-only. Schreibzugriff wuerde bei KACO
  -- ohnehin separate Aktivierung am Geraet erfordern (Phase 2).
}
