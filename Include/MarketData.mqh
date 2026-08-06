//+------------------------------------------------------------------+
//|                                                   MarketData.mqh |
//|   Einzige Stelle, an der Kursdaten gelesen werden. Handles       |
//|   werden in Init() (also aus OnInit) erzeugt, nie in OnTick.     |
//|   Alle Reads nutzen shift>=1 (ausschliesslich geschlossene       |
//|   Bars, ea.md 7.7) und pruefen die Rueckgabewerte von CopyBuffer.|
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_MARKETDATA_MQH__
#define __SWINGGOLD_MARKETDATA_MQH__

class CMarketData
  {
private:
   string            m_symbol;
   int               m_emaSlowHandle; // D1 EMA(InpEmaSlow)
   int               m_emaMidHandle;  // D1 EMA(InpEmaMid)
   int               m_atrHandle;     // D1 ATR(InpAtrPeriod)
   int               m_swingLookback;

   double            m_emaSlowD1;
   double            m_emaMidD1;
   double            m_atrD1;
   bool              m_valid;         // true, wenn der letzte Update()-Aufruf erfolgreich war

   datetime          m_lastD1BarTime;
   datetime          m_lastH4BarTime;

   //+------------------------------------------------------------------+
   //| Gemeinsame Implementierung fuer Swing-Tief-/-Hoch-Suche. Holt     |
   //| Low/High in einem einzigen CopyLow/CopyHigh-Aufruf und sucht      |
   //| danach rueckwaerts nach dem ersten bestaetigten Extremum.        |
   //+------------------------------------------------------------------+
   bool              FindConfirmedSwing(const int startShift, const int maxShift, const bool findLow,
                                        int &outShift, double &outPrice)
     {
      int lb = m_swingLookback;
      if(lb <= 0)
         return false;

      int firstTestable = lb + 1; // braucht lb Bars davor (juenger) UND danach (aelter)
      int from = MathMax(startShift, firstTestable);
      if(from > maxShift)
         return false;

      int neededCount = maxShift + lb; // deckt den Nachbarn i+lb bei i=maxShift ab

      double buf[];
      ArraySetAsSeries(buf, true);
      int copied = findLow ? CopyLow(m_symbol, PERIOD_D1, 1, neededCount, buf)
                           : CopyHigh(m_symbol, PERIOD_D1, 1, neededCount, buf);
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
                        m_symbol(""), m_emaSlowHandle(INVALID_HANDLE), m_emaMidHandle(INVALID_HANDLE),
                        m_atrHandle(INVALID_HANDLE), m_swingLookback(5), m_emaSlowD1(0.0),
                        m_emaMidD1(0.0), m_atrD1(0.0), m_valid(false),
                        m_lastD1BarTime(0), m_lastH4BarTime(0) {}

   //+------------------------------------------------------------------+
   //| Erzeugt alle Indikator-Handles. Muss aus OnInit aufgerufen        |
   //| werden. Gibt false zurueck, wenn ein Handle fehlschlaegt.        |
   //+------------------------------------------------------------------+
   bool              Init(const string symbol, const int emaSlowPeriod, const int emaMidPeriod,
                          const int atrPeriod, const int swingLookback)
     {
      m_symbol        = symbol;
      m_swingLookback = swingLookback;

      m_emaSlowHandle = iMA(m_symbol, PERIOD_D1, emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_emaMidHandle  = iMA(m_symbol, PERIOD_D1, emaMidPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_atrHandle     = iATR(m_symbol, PERIOD_D1, atrPeriod);

      if(m_emaSlowHandle == INVALID_HANDLE || m_emaMidHandle == INVALID_HANDLE || m_atrHandle == INVALID_HANDLE)
        {
         PrintFormat("MarketData: Indikator-Handle-Fehler fuer %s (EmaSlow=%d EmaMid=%d Atr=%d)",
                     m_symbol, m_emaSlowHandle, m_emaMidHandle, m_atrHandle);
         return false;
        }

      return true;
     }

   //--- Muss aus OnDeinit aufgerufen werden.
   void              Deinit(void)
     {
      if(m_emaSlowHandle != INVALID_HANDLE) IndicatorRelease(m_emaSlowHandle);
      if(m_emaMidHandle  != INVALID_HANDLE) IndicatorRelease(m_emaMidHandle);
      if(m_atrHandle     != INVALID_HANDLE) IndicatorRelease(m_atrHandle);
      m_emaSlowHandle = INVALID_HANDLE;
      m_emaMidHandle  = INVALID_HANDLE;
      m_atrHandle     = INVALID_HANDLE;
     }

   //+------------------------------------------------------------------+
   //| Liest die aktuellen D1-Indikatorwerte (Shift=1, letzte           |
   //| geschlossene Bar). Vor jeder Bias/Setup-Pruefung aufrufen.       |
   //+------------------------------------------------------------------+
   bool              Update(void)
     {
      m_valid = false;

      double buf[];
      if(CopyBuffer(m_emaSlowHandle, 0, 1, 1, buf) != 1)
         return false;
      m_emaSlowD1 = buf[0];

      if(CopyBuffer(m_emaMidHandle, 0, 1, 1, buf) != 1)
         return false;
      m_emaMidD1 = buf[0];

      if(CopyBuffer(m_atrHandle, 0, 1, 1, buf) != 1)
         return false;
      m_atrD1 = buf[0];

      if(m_atrD1 <= 0.0)
         return false;

      m_valid = true;
      return true;
     }

   bool              IsValid(void)     const { return m_valid; }
   double            GetEmaSlowD1(void) const { return m_emaSlowD1; }
   double            GetEmaMidD1(void)  const { return m_emaMidD1; }
   double            GetAtrD1(void)     const { return m_atrD1; }

   //--- Geschlossener D1-Close/-High/-Low bei gegebenem Shift (>=1).
   bool              GetCloseD1(const int shift, double &outClose)
     {
      if(shift < 1)
         return false;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyClose(m_symbol, PERIOD_D1, shift, 1, buf) != 1)
         return false;
      outClose = buf[0];
      return true;
     }

   bool              GetHighD1(const int shift, double &outHigh)
     {
      if(shift < 1)
         return false;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyHigh(m_symbol, PERIOD_D1, shift, 1, buf) != 1)
         return false;
      outHigh = buf[0];
      return true;
     }

   bool              GetLowD1(const int shift, double &outLow)
     {
      if(shift < 1)
         return false;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyLow(m_symbol, PERIOD_D1, shift, 1, buf) != 1)
         return false;
      outLow = buf[0];
      return true;
     }

   //+------------------------------------------------------------------+
   //| Sucht rueckwaerts (aufsteigender Shift = aeltere Bars) ab         |
   //| startShift nach dem ersten bestaetigten Swing-Tief/-Hoch.        |
   //| Ein Kandidat bei Shift i gilt erst als bestaetigt, wenn           |
   //| m_swingLookback Bars davor UND danach existieren und i das        |
   //| Extremum in diesem Fenster ist (Anti-Repainting, ea.md 7.7).     |
   //+------------------------------------------------------------------+
   bool              FindConfirmedSwingLow(const int startShift, const int maxShift,
                                           int &outShift, double &outPrice)
     {
      return FindConfirmedSwing(startShift, maxShift, true, outShift, outPrice);
     }

   bool              FindConfirmedSwingHigh(const int startShift, const int maxShift,
                                            int &outShift, double &outPrice)
     {
      return FindConfirmedSwing(startShift, maxShift, false, outShift, outPrice);
     }

   //--- Open/Close der H4-Bar bei gegebenem Shift (>=1, geschlossen).
   bool              GetH4Bar(const int shift, double &outOpen, double &outClose)
     {
      if(shift < 1)
         return false;

      double bufO[], bufC[];
      ArraySetAsSeries(bufO, true);
      ArraySetAsSeries(bufC, true);
      if(CopyOpen(m_symbol, PERIOD_H4, shift, 1, bufO) != 1)
         return false;
      if(CopyClose(m_symbol, PERIOD_H4, shift, 1, bufC) != 1)
         return false;

      outOpen  = bufO[0];
      outClose = bufC[0];
      return true;
     }

   //--- true, wenn seit dem letzten Aufruf eine neue geschlossene H4-Bar entstanden ist.
   bool              IsNewH4Bar(void)
     {
      datetime t = iTime(m_symbol, PERIOD_H4, 0);
      if(t == 0)
         return false;
      if(t != m_lastH4BarTime)
        {
         m_lastH4BarTime = t;
         return true;
        }
      return false;
     }

   //--- true, wenn seit dem letzten Aufruf eine neue geschlossene D1-Bar entstanden ist.
   bool              IsNewD1Bar(void)
     {
      datetime t = iTime(m_symbol, PERIOD_D1, 0);
      if(t == 0)
         return false;
      if(t != m_lastD1BarTime)
        {
         m_lastD1BarTime = t;
         return true;
        }
      return false;
     }
  };

#endif // __SWINGGOLD_MARKETDATA_MQH__
