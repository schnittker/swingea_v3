//+------------------------------------------------------------------+
//|                                                   MarketData.mqh |
//|   Einzige Stelle, an der Kursdaten gelesen werden. Handles       |
//|   werden in Init() (also aus OnInit) erzeugt, nie in OnTick.    |
//|   Alle Reads nutzen shift>=1 (ausschliesslich geschlossene      |
//|   Bars, ea.md 7.7) und pruefen die Rueckgabewerte von CopyBuffer|
//|                                                                   |
//|   PollNewBars() wird EINMAL pro OnTick-Eintritt aufgerufen und   |
//|   latcht m_newM15/m_newH4/m_newD1. IsNew*Bar() sind danach reine|
//|   const-Reads ohne Seiteneffekt: mehrere Slots koennen dasselbe  |
//|   Flag sicher lesen (Bugfix gegenueber der 1-Konsumenten-Version)|
//|                                                                   |
//|   EnsureD1/EnsureH4/EnsureM15 lesen die Indikatorcaches neu,    |
//|   wenn die jeweilige Bar geschlossen ist; der EA ruft nur die    |
//|   fuer seinen Slot relevanten TFs. Fehlschlaege sind isoliert:   |
//|   ein M15-Lesefehler sperrt nicht das D1-Management.            |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_MARKETDATA_MQH__
#define __SWINGGOLD_MARKETDATA_MQH__

//+------------------------------------------------------------------+
//|   Konfigurationsstruktur fuer CMarketData::Init().               |
//|   Welche TF-Kontexte aktiv sind, entscheidet der EA aus den     |
//|   Modul-Schaltern — so werden nie M15-Handles angelegt, wenn    |
//|   nur DipBuy aktiv ist (ea.md 7.7: kein Handle-Wachstum).      |
//+------------------------------------------------------------------+
struct SMarketDataCfg
  {
   // D1 — immer aktiv
   int    emaSlowPeriod;      // z.B. 200 (InpEmaSlow)
   int    emaMidPeriod;       // z.B. 150 (InpEmaMid), wird als "emaFast" auf D1 intern gefuehrt
   int    atrPeriod;          // z.B. 14  (InpAtrPeriod)
   int    swingLookback;      // Fraktal-Breite fuer FindConfirmedSwing
   // H4 — optional, nur wenn Overlap-Modul aktiv
   bool   useH4Emas;
   int    emaFastH4Period;    // z.B. 50  (InpOvEmaFastH4)
   int    emaSlowH4Period;    // z.B. 200 (InpOvEmaSlowH4)
   // M15 — optional, nur wenn Overlap-Modul aktiv
   bool   useM15;
   int    emaPullbackFastM15; // z.B. 20  (InpOvPullbackEmaFast)
   int    emaPullbackSlowM15; // z.B. 50  (InpOvPullbackEmaSlow)
   int    atrPeriodM15;       // z.B. 14  (InpOvAtrPeriodM15)
  };

class CMarketData
  {
private:
   string            m_symbol;
   int               m_swingLookback;

   //--- D1 Handles + Cache
   int               m_emaSlowD1Handle;
   int               m_emaMidD1Handle;
   int               m_atrD1Handle;
   double            m_emaSlowD1;
   double            m_emaMidD1;
   double            m_atrD1;
   bool              m_d1Valid;

   //--- H4 Handles + Cache (optional)
   bool              m_useH4Emas;
   int               m_emaFastH4Handle;
   int               m_emaSlowH4Handle;
   double            m_emaFastH4;
   double            m_emaSlowH4;
   bool              m_h4Valid;

   //--- M15 Handles + Cache (optional)
   bool              m_useM15;
   int               m_emaFastM15Handle;
   int               m_emaSlowM15Handle;
   int               m_atrM15Handle;
   double            m_emaFastM15;
   double            m_emaSlowM15;
   double            m_atrM15;
   bool              m_m15Valid;

   //--- Bar-Zeit-Referenzen (fuer PollNewBars)
   datetime          m_lastD1BarTime;
   datetime          m_lastH4BarTime;
   datetime          m_lastM15BarTime;

   //--- Gelegte Flags (von PollNewBars gesetzt, von Is*Bar() nur gelesen)
   bool              m_newD1;
   bool              m_newH4;
   bool              m_newM15;

   //+------------------------------------------------------------------+
   //| Gemeinsame Implementierung fuer Swing-Tief-/-Hoch-Suche.        |
   //| Holt Low/High in einem einzigen CopyLow/CopyHigh-Aufruf und     |
   //| sucht danach rueckwaerts nach dem ersten bestaetigten Extremum. |
   //+------------------------------------------------------------------+
   bool              FindConfirmedSwingImpl(const int startShift, const int maxShift,
                                            const bool findLow, const ENUM_TIMEFRAMES tf,
                                            int &outShift, double &outPrice)
     {
      int lb = m_swingLookback;
      if(lb <= 0)
         return false;

      int firstTestable = lb + 1;
      int from = MathMax(startShift, firstTestable);
      if(from > maxShift)
         return false;

      int neededCount = maxShift + lb;

      double buf[];
      ArraySetAsSeries(buf, true);
      int copied = findLow ? CopyLow(m_symbol, tf, 1, neededCount, buf)
                           : CopyHigh(m_symbol, tf, 1, neededCount, buf);
      if(copied <= 0)
         return false;

      // buf-Index j entspricht Shift j+1 (Copy-Start war Shift 1).
      for(int i = from; i <= maxShift; i++)
        {
         int idx = i - 1;
         if(idx < 0 || idx >= copied)
            break;

         double candidate = buf[idx];
         bool   confirmed  = true;

         for(int k = 1; k <= lb; k++)
           {
            int idxBefore = (i - k) - 1;
            int idxAfter  = (i + k) - 1;
            if(idxBefore < 0 || idxBefore >= copied || idxAfter < 0 || idxAfter >= copied)
              {
               confirmed = false;
               break;
              }

            double neighborBefore = buf[idxBefore];
            double neighborAfter  = buf[idxAfter];

            if(findLow)
              {
               if(neighborBefore < candidate || neighborAfter < candidate)
                 {
                  confirmed = false;
                  break;
                 }
              }
            else
              {
               if(neighborBefore > candidate || neighborAfter > candidate)
                 {
                  confirmed = false;
                  break;
                 }
              }
           }

         if(confirmed)
           {
            outShift = i;
            outPrice = candidate;
            return true;
           }
        }

      return false;
     }

public:
                     CMarketData(void):
                        m_symbol(""),
                        m_swingLookback(5),
                        m_emaSlowD1Handle(INVALID_HANDLE),
                        m_emaMidD1Handle(INVALID_HANDLE),
                        m_atrD1Handle(INVALID_HANDLE),
                        m_emaSlowD1(0.0), m_emaMidD1(0.0), m_atrD1(0.0),
                        m_d1Valid(false),
                        m_useH4Emas(false),
                        m_emaFastH4Handle(INVALID_HANDLE),
                        m_emaSlowH4Handle(INVALID_HANDLE),
                        m_emaFastH4(0.0), m_emaSlowH4(0.0),
                        m_h4Valid(false),
                        m_useM15(false),
                        m_emaFastM15Handle(INVALID_HANDLE),
                        m_emaSlowM15Handle(INVALID_HANDLE),
                        m_atrM15Handle(INVALID_HANDLE),
                        m_emaFastM15(0.0), m_emaSlowM15(0.0), m_atrM15(0.0),
                        m_m15Valid(false),
                        m_lastD1BarTime(0), m_lastH4BarTime(0), m_lastM15BarTime(0),
                        m_newD1(false), m_newH4(false), m_newM15(false) {}

   //+------------------------------------------------------------------+
   //| Erzeugt alle Indikator-Handles gemaess Konfiguration.            |
   //| Muss aus OnInit aufgerufen werden. Nie in OnTick (ea.md 7.7).   |
   //| false = ein benoetigter Handle konnte nicht erstellt werden.     |
   //+------------------------------------------------------------------+
   bool              Init(const string symbol, const SMarketDataCfg &cfg)
     {
      m_symbol        = symbol;
      m_swingLookback = cfg.swingLookback;
      m_useH4Emas     = cfg.useH4Emas;
      m_useM15        = cfg.useM15;

      //--- D1 immer
      m_emaSlowD1Handle = iMA(m_symbol, PERIOD_D1, cfg.emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_emaMidD1Handle  = iMA(m_symbol, PERIOD_D1, cfg.emaMidPeriod,  0, MODE_EMA, PRICE_CLOSE);
      m_atrD1Handle     = iATR(m_symbol, PERIOD_D1, cfg.atrPeriod);

      if(m_emaSlowD1Handle == INVALID_HANDLE || m_emaMidD1Handle == INVALID_HANDLE || m_atrD1Handle == INVALID_HANDLE)
        {
         PrintFormat("MarketData: D1-Handle-Fehler fuer %s (EmaSlow=%d EmaMid=%d Atr=%d)",
                     m_symbol, m_emaSlowD1Handle, m_emaMidD1Handle, m_atrD1Handle);
         return false;
        }

      //--- H4 optional
      if(m_useH4Emas)
        {
         m_emaFastH4Handle = iMA(m_symbol, PERIOD_H4, cfg.emaFastH4Period, 0, MODE_EMA, PRICE_CLOSE);
         m_emaSlowH4Handle = iMA(m_symbol, PERIOD_H4, cfg.emaSlowH4Period, 0, MODE_EMA, PRICE_CLOSE);

         if(m_emaFastH4Handle == INVALID_HANDLE || m_emaSlowH4Handle == INVALID_HANDLE)
           {
            PrintFormat("MarketData: H4-Handle-Fehler fuer %s (EmaFastH4=%d EmaSlowH4=%d)",
                        m_symbol, m_emaFastH4Handle, m_emaSlowH4Handle);
            return false;
           }
        }

      //--- M15 optional
      if(m_useM15)
        {
         m_emaFastM15Handle = iMA(m_symbol, PERIOD_M15, cfg.emaPullbackFastM15, 0, MODE_EMA, PRICE_CLOSE);
         m_emaSlowM15Handle = iMA(m_symbol, PERIOD_M15, cfg.emaPullbackSlowM15, 0, MODE_EMA, PRICE_CLOSE);
         m_atrM15Handle     = iATR(m_symbol, PERIOD_M15, cfg.atrPeriodM15);

         if(m_emaFastM15Handle == INVALID_HANDLE || m_emaSlowM15Handle == INVALID_HANDLE || m_atrM15Handle == INVALID_HANDLE)
           {
            PrintFormat("MarketData: M15-Handle-Fehler fuer %s (EmaFastM15=%d EmaSlowM15=%d AtrM15=%d)",
                        m_symbol, m_emaFastM15Handle, m_emaSlowM15Handle, m_atrM15Handle);
            return false;
           }
        }

      return true;
     }

   //--- Muss aus OnDeinit aufgerufen werden.
   void              Deinit(void)
     {
      if(m_emaSlowD1Handle != INVALID_HANDLE) { IndicatorRelease(m_emaSlowD1Handle); m_emaSlowD1Handle = INVALID_HANDLE; }
      if(m_emaMidD1Handle  != INVALID_HANDLE) { IndicatorRelease(m_emaMidD1Handle);  m_emaMidD1Handle  = INVALID_HANDLE; }
      if(m_atrD1Handle     != INVALID_HANDLE) { IndicatorRelease(m_atrD1Handle);     m_atrD1Handle     = INVALID_HANDLE; }
      if(m_emaFastH4Handle != INVALID_HANDLE) { IndicatorRelease(m_emaFastH4Handle); m_emaFastH4Handle = INVALID_HANDLE; }
      if(m_emaSlowH4Handle != INVALID_HANDLE) { IndicatorRelease(m_emaSlowH4Handle); m_emaSlowH4Handle = INVALID_HANDLE; }
      if(m_emaFastM15Handle != INVALID_HANDLE) { IndicatorRelease(m_emaFastM15Handle); m_emaFastM15Handle = INVALID_HANDLE; }
      if(m_emaSlowM15Handle != INVALID_HANDLE) { IndicatorRelease(m_emaSlowM15Handle); m_emaSlowM15Handle = INVALID_HANDLE; }
      if(m_atrM15Handle     != INVALID_HANDLE) { IndicatorRelease(m_atrM15Handle);     m_atrM15Handle     = INVALID_HANDLE; }
     }

   //+------------------------------------------------------------------+
   //| Latcht die Bar-Neu-Flags fuer M15/H4/D1 in einem einzigen       |
   //| Aufruf. Muss EINMAL ganz am Anfang von OnTick aufgerufen werden. |
   //| Danach sind IsNew*Bar() nicht-mutierende const-Reads.            |
   //+------------------------------------------------------------------+
   void              PollNewBars(void)
     {
      //--- M15
      if(m_useM15)
        {
         datetime t = iTime(m_symbol, PERIOD_M15, 0);
         m_newM15 = (t != 0 && t != m_lastM15BarTime);
         if(m_newM15) m_lastM15BarTime = t;
        }
      else
        {
         m_newM15 = false;
        }

      //--- H4
      {
         datetime t = iTime(m_symbol, PERIOD_H4, 0);
         m_newH4 = (t != 0 && t != m_lastH4BarTime);
         if(m_newH4) m_lastH4BarTime = t;
        }

      //--- D1
      {
         datetime t = iTime(m_symbol, PERIOD_D1, 0);
         m_newD1 = (t != 0 && t != m_lastD1BarTime);
         if(m_newD1) m_lastD1BarTime = t;
        }
     }

   //--- Nicht-mutierende Bar-Abfragen (const, kein Einmalkonsum)
   bool              IsNewD1Bar(void)  const { return m_newD1;  }
   bool              IsNewH4Bar(void)  const { return m_newH4;  }
   bool              IsNewM15Bar(void) const { return m_newM15; }

   //+------------------------------------------------------------------+
   //| Liest D1-Indikatorcaches neu (Shift=1, letzte geschlossene Bar).|
   //| Setzt m_d1Valid. Muss aufgerufen werden, wenn neuer H4-Bar       |
   //| (oder neuer D1-Bar) erkannt wurde.                               |
   //+------------------------------------------------------------------+
   bool              EnsureD1(void)
     {
      m_d1Valid = false;

      double buf[];
      if(CopyBuffer(m_emaSlowD1Handle, 0, 1, 1, buf) != 1) return false;
      m_emaSlowD1 = buf[0];

      if(CopyBuffer(m_emaMidD1Handle, 0, 1, 1, buf) != 1) return false;
      m_emaMidD1 = buf[0];

      if(CopyBuffer(m_atrD1Handle, 0, 1, 1, buf) != 1) return false;
      m_atrD1 = buf[0];

      if(m_atrD1 <= 0.0) return false;

      m_d1Valid = true;
      return true;
     }

   //+------------------------------------------------------------------+
   //| Liest H4-Indikatorcaches neu. Nur wenn useH4Emas == true.       |
   //+------------------------------------------------------------------+
   bool              EnsureH4(void)
     {
      if(!m_useH4Emas) return true; // nicht benoetigt, kein Fehler

      m_h4Valid = false;

      double buf[];
      if(CopyBuffer(m_emaFastH4Handle, 0, 1, 1, buf) != 1) return false;
      m_emaFastH4 = buf[0];

      if(CopyBuffer(m_emaSlowH4Handle, 0, 1, 1, buf) != 1) return false;
      m_emaSlowH4 = buf[0];

      m_h4Valid = true;
      return true;
     }

   //+------------------------------------------------------------------+
   //| Liest M15-Indikatorcaches neu. Nur wenn useM15 == true.         |
   //+------------------------------------------------------------------+
   bool              EnsureM15(void)
     {
      if(!m_useM15) return true; // nicht benoetigt, kein Fehler

      m_m15Valid = false;

      double buf[];
      if(CopyBuffer(m_emaFastM15Handle, 0, 1, 1, buf) != 1) return false;
      m_emaFastM15 = buf[0];

      if(CopyBuffer(m_emaSlowM15Handle, 0, 1, 1, buf) != 1) return false;
      m_emaSlowM15 = buf[0];

      if(CopyBuffer(m_atrM15Handle, 0, 1, 1, buf) != 1) return false;
      m_atrM15 = buf[0];

      if(m_atrM15 <= 0.0) return false;

      m_m15Valid = true;
      return true;
     }

   bool              IsD1Valid(void)  const { return m_d1Valid;  }
   bool              IsH4Valid(void)  const { return m_h4Valid;  }
   bool              IsM15Valid(void) const { return m_m15Valid; }

   //--- D1 Getter (backward-kompatible Namen)
   double            GetEmaSlowD1(void) const { return m_emaSlowD1; }
   double            GetEmaMidD1(void)  const { return m_emaMidD1;  }
   double            GetAtrD1(void)     const { return m_atrD1;     }

   //--- H4 Getter
   double            GetEmaFastH4(void) const { return m_emaFastH4; }
   double            GetEmaSlowH4(void) const { return m_emaSlowH4; }

   //--- M15 Getter
   double            GetEmaFastM15(void) const { return m_emaFastM15; }
   double            GetEmaSlowM15(void) const { return m_emaSlowM15; }
   double            GetAtrM15(void)     const { return m_atrM15;     }

   //--- Generischer ATR-Getter (fuer TradeManager: strategies.md Teil D "Fehler 1")
   double            GetAtr(const ENUM_TIMEFRAMES tf) const
     {
      if(tf == PERIOD_D1)  return m_atrD1;
      if(tf == PERIOD_M15) return m_atrM15;
      return 0.0;
     }

   //--- Geschlossener D1-Close/-High/-Low bei gegebenem Shift (>=1).
   bool              GetCloseD1(const int shift, double &outClose)
     {
      if(shift < 1) return false;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyClose(m_symbol, PERIOD_D1, shift, 1, buf) != 1) return false;
      outClose = buf[0];
      return true;
     }

   bool              GetHighD1(const int shift, double &outHigh)
     {
      if(shift < 1) return false;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyHigh(m_symbol, PERIOD_D1, shift, 1, buf) != 1) return false;
      outHigh = buf[0];
      return true;
     }

   bool              GetLowD1(const int shift, double &outLow)
     {
      if(shift < 1) return false;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyLow(m_symbol, PERIOD_D1, shift, 1, buf) != 1) return false;
      outLow = buf[0];
      return true;
     }

   //--- H4-Bar Open/Close (Shift >= 1) — backward-kompatibel
   bool              GetH4Bar(const int shift, double &outOpen, double &outClose)
     {
      return GetBar(PERIOD_H4, shift, outOpen, outClose);
     }

   //--- Generischer Bar-Leser fuer beliebigen TF
   bool              GetBar(const ENUM_TIMEFRAMES tf, const int shift,
                            double &outOpen, double &outClose)
     {
      if(shift < 1) return false;
      double bufO[], bufC[];
      ArraySetAsSeries(bufO, true);
      ArraySetAsSeries(bufC, true);
      if(CopyOpen(m_symbol, tf, shift, 1, bufO) != 1) return false;
      if(CopyClose(m_symbol, tf, shift, 1, bufC) != 1) return false;
      outOpen  = bufO[0];
      outClose = bufC[0];
      return true;
     }

   //--- Generische Low/High-Leser
   bool              GetLow(const ENUM_TIMEFRAMES tf, const int shift, double &outLow)
     {
      if(shift < 1) return false;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyLow(m_symbol, tf, shift, 1, buf) != 1) return false;
      outLow = buf[0];
      return true;
     }

   bool              GetHigh(const ENUM_TIMEFRAMES tf, const int shift, double &outHigh)
     {
      if(shift < 1) return false;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyHigh(m_symbol, tf, shift, 1, buf) != 1) return false;
      outHigh = buf[0];
      return true;
     }

   //+------------------------------------------------------------------+
   //| TF-parameterisierte Swing-Suche. Rueckwaerts (aufsteigender    |
   //| Shift) ab startShift nach erstem bestaetigten Extremum.         |
   //| Bestaetigt: m_swingLookback Bars davor UND danach existieren   |
   //| und Kandidat ist das Extremum im Fenster (Anti-Repainting).    |
   //+------------------------------------------------------------------+
   bool              FindConfirmedSwingLow(const int startShift, const int maxShift,
                                           const ENUM_TIMEFRAMES tf,
                                           int &outShift, double &outPrice)
     {
      return FindConfirmedSwingImpl(startShift, maxShift, true, tf, outShift, outPrice);
     }

   bool              FindConfirmedSwingHigh(const int startShift, const int maxShift,
                                            const ENUM_TIMEFRAMES tf,
                                            int &outShift, double &outPrice)
     {
      return FindConfirmedSwingImpl(startShift, maxShift, false, tf, outShift, outPrice);
     }

   //--- Backward-kompatible 4-arg Wrapper (Standard PERIOD_D1)
   bool              FindConfirmedSwingLow(const int startShift, const int maxShift,
                                           int &outShift, double &outPrice)
     {
      return FindConfirmedSwingImpl(startShift, maxShift, true, PERIOD_D1, outShift, outPrice);
     }

   bool              FindConfirmedSwingHigh(const int startShift, const int maxShift,
                                            int &outShift, double &outPrice)
     {
      return FindConfirmedSwingImpl(startShift, maxShift, false, PERIOD_D1, outShift, outPrice);
     }

   //--- Rueckwaerts-kompatibler Alias fuer alten Update()-Aufruf.
   //--- Verhaltensaequivalent zu: lies D1-Indikatoren neu.
   //--- HINWEIS: Neuer Code soll EnsureD1() direkt aufrufen.
   bool              Update(void) { return EnsureD1(); }
  };

#endif // __SWINGGOLD_MARKETDATA_MQH__
