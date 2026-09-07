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
--    -> NICHT implementiert lt. Doku in M103: DCA/DCV/DCW (DC-Werte),
--       TmpSnk, TmpTrns, TmpOt (nur TmpCab vorhanden).
--    -> DC-WERTE KOMMEN AUS MODELL 160 (Multiple MPPT Extension):
--       M160-ID an 40208, Laenge 48, Daten ab 40210, N=2 Module.
--       SF datenrelativ: DCA_SF=+0(=-2), DCV_SF=+1(=-1), DCW_SF=+2(=+1).
--       Modul-Block je 20 Register ab +8:
--         String 1: DCA=+17 DCV=+18 DCW=+19
--         String 2: DCA=+37 DCV=+38 DCW=+39
--       DCWH/Tms/Tmp/DCSt/DCEvt in M160 = unimpl -> weggelassen.
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
-- Modell 103 datenrelativ: A=0 AphA=1 A_SF=4 PPVphAB=5 PPVphBC=6
--   PPVphCA=7 PhVphA=8 V_SF=11 W=12 W_SF=13 Hz=14 Hz_SF=15 VA=16
--   VAr=18 PF=20 PF_SF=21 WH=22(u32) WH_SF=24 TmpCab=31 Tmp_SF=35 St=36
-- Modell 160 datenrelativ: DCA_SF=0 DCV_SF=1 DCW_SF=2 N=6
--   Modul1: DCA=17 DCV=18 DCW=19 / Modul2: DCA=37 DCV=38 DCW=39
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
  -- device_poll liest je benoetigtem Modell (103 + 160) EINEN Block.
  read = {
    -- Kernpunkte: W(12) W_SF(13) Hz(14) Hz_SF(15) St(36)
    ac_power   = { model = 103, offset = 12, fc = 3, type = "s16", unit = "W",
                   sf_offset = 13, not_impl = 0x8000 },
    ac_freq    = { model = 103, offset = 14, fc = 3, type = "u16", unit = "Hz",
                   sf_offset = 15, not_impl = 0xFFFF },
    status     = { model = 103, offset = 36, fc = 3, type = "u16", unit = "",
                   not_impl = 0xFFFF },  -- St enum16 (4=MPPT, 7=Fault, 8=Standby)
    -- Zusatzpunkte (alle aus demselben Modell-103-Block, keine Extra-Reads):
    ac_current = { model = 103, offset = 0,  fc = 3, type = "u16", unit = "A",
                   sf_offset = 4, not_impl = 0xFFFF },   -- A gesamt
    u_l1n      = { model = 103, offset = 8,  fc = 3, type = "u16", unit = "V",
                   sf_offset = 11, not_impl = 0xFFFF },  -- PhVphA
    u_l12      = { model = 103, offset = 5,  fc = 3, type = "u16", unit = "V",
                   sf_offset = 11, not_impl = 0xFFFF },  -- PPVphAB (L1-L2)
    u_l23      = { model = 103, offset = 6,  fc = 3, type = "u16", unit = "V",
                   sf_offset = 11, not_impl = 0xFFFF },  -- PPVphBC (L2-L3)
    u_l31      = { model = 103, offset = 7,  fc = 3, type = "u16", unit = "V",
                   sf_offset = 11, not_impl = 0xFFFF },  -- PPVphCA (L3-L1)
    cos_phi    = { model = 103, offset = 20, fc = 3, type = "s16", unit = "",
                   sf_offset = 21, not_impl = 0x8000 },  -- PF (0..1)
    energy_kwh = { model = 103, offset = 22, fc = 3, type = "u32be", unit = "kWh",
                   sf_offset = 24, scale = 0.001 },      -- WH acc32 -> kWh
    temp_c     = { model = 103, offset = 31, fc = 3, type = "s16", unit = "C",
                   sf_offset = 35, not_impl = 0x8000 },  -- TmpCab
    -- DC-Werte aus Modell 160 (MPPT, 2 Strings) - eigener Block-Read:
    dc1_current = { model = 160, offset = 17, fc = 3, type = "u16", unit = "A",
                    sf_offset = 0, not_impl = 0xFFFF },  -- Modul1 DCA (SF=-2)
    dc1_voltage = { model = 160, offset = 18, fc = 3, type = "u16", unit = "V",
                    sf_offset = 1, not_impl = 0xFFFF },  -- Modul1 DCV (SF=-1)
    dc1_power   = { model = 160, offset = 19, fc = 3, type = "s16", unit = "W",
                    sf_offset = 2, not_impl = 0x8000 },  -- Modul1 DCW (SF=+1)
    dc2_current = { model = 160, offset = 37, fc = 3, type = "u16", unit = "A",
                    sf_offset = 0, not_impl = 0xFFFF },  -- Modul2 DCA
    dc2_voltage = { model = 160, offset = 38, fc = 3, type = "u16", unit = "V",
                    sf_offset = 1, not_impl = 0xFFFF },  -- Modul2 DCV
    dc2_power   = { model = 160, offset = 39, fc = 3, type = "s16", unit = "W",
                    sf_offset = 2, not_impl = 0x8000 },  -- Modul2 DCW
  },

  ui = {
    plaus = {
      ac_power    = { -1000, 12000 },
      ac_freq     = { 45, 55 },
      status      = { 1, 8 },
      ac_current  = { 0, 30 },
      u_l1n       = { 150, 280 },
      u_l12       = { 300, 480 },
      u_l23       = { 300, 480 },
      u_l31       = { 300, 480 },
      cos_phi     = { -1, 1 },
      energy_kwh  = { 0, 100000000 },
      temp_c      = { -25, 100 },
      dc1_current = { 0, 30 },
      dc1_voltage = { 0, 1100 },
      dc1_power   = { -100, 8000 },
      dc2_current = { 0, 30 },
      dc2_voltage = { 0, 1100 },
      dc2_power   = { -100, 8000 },
    },
  },

  -- KEIN write-Block: read-only. Schreibzugriff wuerde bei KACO
  -- ohnehin separate Freischaltung am Geraet erfordern (Phase 2).
}
