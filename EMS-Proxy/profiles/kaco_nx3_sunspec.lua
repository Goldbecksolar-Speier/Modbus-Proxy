-- =====================================================================
-- Profil: Kaco blueplanet NX3 10 kW (PV-Wechselrichter)
-- Standort: Hebauer. Phase 1: NUR LESEN - kein write-Block!
--
-- QUELLEN:
--  * KACO "SunSpec Information Model Reference NX3"
--    (3015836-01-221102, APL_SunSpec_Information_Model_Reference_NX3)
--    -> BESTAETIGT die Offsets absolut: M103-ID an 40070, Daten ab 40072,
--       W=40084, W_SF=40085(=1), Hz=40086, Hz_SF=40087(=-2), St=40108;
--       Device Address = 3; Schreibzugriff muss am WR separat
--       freigeschaltet werden (MODBUS/SunSpec-Menue), sonst read-only.
--  * SunSpec Device Information Model Specification v1.2.1
--
-- SCAN-ERGEBNIS AM GERAET (2026-09-07, 192.168.20.171:502 unit 3):
--    Basis 40000, Kette: 1(len 66) 103(len 50) 120 121 123 160(len 48)
--    701(len 153) 702 704 714 715, Ende 0xFFFF bei 40611
--    -> Modell 103 data_start=40072 (nur zur Info, NICHT hart kodieren!)
--    WICHTIG: Der NX3 quittiert schnelle TCP-Verbindungsfolgen mit
--    Timeout und liefert bei Einzelreads sporadisch verstuemmelte
--    Werte -> device_poll liest je Modell EINEN Block (konsistent).
--
-- WICHTIG (KACO-Vorgabe): KEINE festen absoluten Registeradressen
-- verwenden - die Adressen gelten nur fuer eine konkrete Firmware!
-- Modelle und Startadressen MUESSEN per SunSpec Model Scan zur
-- Laufzeit ermittelt werden. Deshalb enthaelt dieses Profil nur
-- Modell-relative Offsets (model + offset), keine Absolutadressen.
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
--    Echtwert = Rohwert * 10^SF. SF ist statisch.
--  * NOT-IMPLEMENTED-Sentinels: u16=0xFFFF, s16=0x8000,
--    u32=0xFFFFFFFF, s32=0x80000000 -> als "kein Wert" verwerfen.
--  * St (Operating State) enum16: 1=Off 2=Sleeping 3=Starting 4=MPPT
--    5=Throttled 6=ShuttingDown 7=Fault 8=Standby
-- =====================================================================

return {
  id           = "kaco_nx3_sunspec",
  name         = "Kaco blueplanet NX3 10kW (SunSpec Model Scan)",
  role         = "inverter",
  conn         = "tcp",
  port         = 502,
  unit_id      = 3,        -- AM GERAET VERIFIZIERT 2026-09-07 + KACO-Doku (Device Address)
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
    -- Am Geraet bestaetigte Modelle (Scan 2026-09-07 + KACO-Doku):
    models_expected = { 1, 103, 120, 121, 123, 160, 701, 702, 704, 714, 715 },
  },

  -- Messpunkte MODELL-RELATIV: model = SunSpec-Modell-ID,
  -- offset = Register-Offset ab Modell-DATENBEGINN (nach ID+Laenge).
  -- Absolutadresse = ScanErgebnis(model).data_start + offset.
  -- device_poll liest Modell 103 als EINEN Block und dekodiert daraus.
  read = {
    -- Modell 103 datenrelativ: W(12) W_SF(13) Hz(14) Hz_SF(15) St(36)
    ac_power = { model = 103, offset = 12, fc = 3, type = "s16", unit = "W",
                 sf_offset = 13, not_impl = 0x8000 },
    ac_freq  = { model = 103, offset = 14, fc = 3, type = "u16", unit = "Hz",
                 sf_offset = 15, not_impl = 0xFFFF },
    status   = { model = 103, offset = 36, fc = 3, type = "u16", unit = "",
                 not_impl = 0xFFFF },  -- St enum16 (4=MPPT, 7=Fault, 8=Standby)
  },

  ui = {
    plaus = {
      ac_power = { -1000, 12000 },
      ac_freq  = { 45, 55 },
      status   = { 1, 8 },
    },
  },

  -- KEIN write-Block: read-only. Schreibzugriff wuerde bei KACO
  -- ohnehin separate Freischaltung am Geraet erfordern (Phase 2).
}
