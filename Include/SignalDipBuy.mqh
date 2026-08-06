//+------------------------------------------------------------------+
//|                                                 SignalDipBuy.mqh |
//|   Phase-1-Strategie: struktureller Dip-Buy (D1-Bias/Setup,       |
//|   H4-Trigger). Long-Bias = Close>EMA(Slow) + hoehere Tiefs,      |
//|   gespiegelt fuer Short (nur wenn m_allowShort). Setup-Zone ist  |
//|   die Vereinigung aus EMA(Mid)-Beruehrung und Fib 0.382-0.618    |
//|   des letzten Impulses (ea.md 4.6). Kein RSI-/Zeit-Exit.         |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_SIGNALDIPBUY_MQH__
#define __SWINGGOLD_SIGNALDIPBUY_MQH__

#include "Types.mqh"
#include "MarketData.mqh"

class CSignalDipBuy
  {
private:
   ENUM_SETUP_STATE  m_state;
   ENUM_SIGNAL_DIR   m_dir;              // nur waehrend ARMED..PENDING gueltig

   bool              m_allowShort;
   int               m_swingLookback;
   int               m_swingSearchDepth; // wie weit (Shifts) rueckwaerts nach Swings gesucht wird
   double            m_atrStopMult;
   int               m_armedExpiryBars;  // konfigurierter Default
   int               m_expiryCounter;    // laufender Countdown
   int               m_magic;

   double            m_zoneLow;
   double            m_zoneHigh;
   double            m_stopSwingPrice;   // Swing-Extremum, das das Setup definiert (fuer Stop + Invalidierung)
   double            m_targetPrice;      // altes Swing-Hoch/-Tief, Teilgewinn-Ziel

   //+------------------------------------------------------------------+
   //| D1-Bias: Trend (Close vs. EMA-Slow) + Struktur (hoehere Tiefs   |
   //| fuer Long, tiefere Hochs fuer Short, fraktalbasiert).            |
   //+------------------------------------------------------------------+
   bool              CheckBias(CMarketData &md, const ENUM_SIGNAL_DIR dir)
     {
      double close1;
      if(!md.GetCloseD1(1, close1))
         return false;

      double emaSlow = md.GetEmaSlowD1();

      if(dir == SIGNAL_LONG)
        {
         if(close1 <= emaSlow)
            return false;

         int    shift1, shift0;
         double price1, price0;
         if(!md.FindConfirmedSwingLow(m_swingLookback + 1, m_swingSearchDepth, shift1, price1))
            return false;
         if(!md.FindConfirmedSwingLow(shift1 + 1, m_swingSearchDepth, shift0, price0))
            return false;

         return (price1 > price0); // hoehere Tiefs
        }
      else // SIGNAL_SHORT
        {
         if(close1 >= emaSlow)
            return false;

         int    shift1, shift0;
         double price1, price0;
         if(!md.FindConfirmedSwingHigh(m_swingLookback + 1, m_swingSearchDepth, shift1, price1))
            return false;
         if(!md.FindConfirmedSwingHigh(shift1 + 1, m_swingSearchDepth, shift0, price0))
            return false;

         return (price1 < price0); // tiefere Hochs
        }
     }

   //+------------------------------------------------------------------+
   //| D1-Setup: Impuls (letztes bestaetigtes Swing-Extremum -> das     |
   //| dazwischenliegende, juengere Gegen-Extremum) + Zone (Fib         |
   //| 0.382-0.618, erweitert um EMA-Mid, falls dieser innerhalb des    |
   //| Impulses liegt).                                                 |
   //+------------------------------------------------------------------+
   bool              CheckBiasAndSetup(CMarketData &md, const ENUM_SIGNAL_DIR dir)
     {
      if(!CheckBias(md, dir))
         return false;

      double emaMid = md.GetEmaMidD1();

      if(dir == SIGNAL_LONG)
        {
         int    lowShift;
         double lowPrice;
         if(!md.FindConfirmedSwingLow(m_swingLookback + 1, m_swingSearchDepth, lowShift, lowPrice))
            return false;

         if(lowShift - 1 < m_swingLookback + 1)
            return false; // keine Bars fuer ein Gegen-Extremum zwischen Tief und jetzt

         int    highShift;
         double highPrice;
         if(!md.FindConfirmedSwingHigh(m_swingLookback + 1, lowShift - 1, highShift, highPrice))
            return false;

         double impulseRange = highPrice - lowPrice;
         if(impulseRange <= 0.0)
            return false;

         double fibLow  = highPrice - 0.618 * impulseRange;
         double fibHigh = highPrice - 0.382 * impulseRange;

         double zoneLow  = fibLow;
         double zoneHigh = fibHigh;
         if(emaMid > lowPrice && emaMid < highPrice) // EMA-Mid sinnvoll innerhalb des Impulses
           {
            zoneLow  = MathMin(zoneLow, emaMid);
            zoneHigh = MathMax(zoneHigh, emaMid);
           }

         m_zoneLow        = zoneLow;
         m_zoneHigh       = zoneHigh;
         m_stopSwingPrice = lowPrice;
         m_targetPrice    = highPrice;
         return true;
        }
      else // SIGNAL_SHORT
        {
         int    highShift;
         double highPrice;
         if(!md.FindConfirmedSwingHigh(m_swingLookback + 1, m_swingSearchDepth, highShift, highPrice))
            return false;

         if(highShift - 1 < m_swingLookback + 1)
            return false;

         int    lowShift;
         double lowPrice;
         if(!md.FindConfirmedSwingLow(m_swingLookback + 1, highShift - 1, lowShift, lowPrice))
            return false;

         double impulseRange = highPrice - lowPrice;
         if(impulseRange <= 0.0)
            return false;

         double fibLow  = lowPrice + 0.382 * impulseRange;
         double fibHigh = lowPrice + 0.618 * impulseRange;

         double zoneLow  = fibLow;
         double zoneHigh = fibHigh;
         if(emaMid > lowPrice && emaMid < highPrice)
           {
            zoneLow  = MathMin(zoneLow, emaMid);
            zoneHigh = MathMax(zoneHigh, emaMid);
           }

         m_zoneLow        = zoneLow;
         m_zoneHigh       = zoneHigh;
         m_stopSwingPrice = highPrice;
         m_targetPrice    = lowPrice;
         return true;
        }
     }

   bool              PriceInZone(const double price) const
     {
      return (price >= m_zoneLow && price <= m_zoneHigh);
     }

   //+------------------------------------------------------------------+
   //| H4-Trigger: Umkehrkerze in der Zone. Long = bullisch (Close>Open |
   //| und Close > Mitte der Vorkerze), Short gespiegelt.               |
   //+------------------------------------------------------------------+
   bool              CheckTriggerCandle(CMarketData &md, const ENUM_SIGNAL_DIR dir, double &outRefPrice)
     {
      double open1, close1, open2, close2;
      if(!md.GetH4Bar(1, open1, close1))
         return false;
      if(!md.GetH4Bar(2, open2, close2))
         return false;

      double mid2 = (open2 + close2) / 2.0;
      outRefPrice = close1;

      if(dir == SIGNAL_LONG)
         return (close1 > open1 && close1 > mid2);
      else
         return (close1 < open1 && close1 < mid2);
     }

   void              Arm(const ENUM_SIGNAL_DIR dir)
     {
      m_dir           = dir;
      m_state         = ST_ARMED;
      m_expiryCounter = m_armedExpiryBars;
      PrintFormat("SignalDipBuy: ST_ARMED dir=%d zone=[%.5f,%.5f] stopSwing=%.5f target=%.5f expiry=%d",
                  dir, m_zoneLow, m_zoneHigh, m_stopSwingPrice, m_targetPrice, m_expiryCounter);
     }

   void              ResetToIdle(const string logReason)
     {
      PrintFormat("SignalDipBuy: ST_IDLE (%s)", logReason);
      m_state = ST_IDLE;
      m_dir   = SIGNAL_FLAT;
     }

   void              BuildProposal(CMarketData &md, const double refPrice, SignalProposal &outProposal)
     {
      double atr = md.GetAtrD1();

      outProposal.Reset();
      outProposal.valid       = true;
      outProposal.dir         = m_dir;
      outProposal.entryPrice  = 0.0; // Market
      outProposal.atrAtSignal = atr;
      outProposal.magic       = m_magic;
      outProposal.targetPrice = m_targetPrice;

      if(m_dir == SIGNAL_LONG)
        {
         outProposal.stopPrice = MathMin(m_stopSwingPrice, refPrice - m_atrStopMult * atr);
         outProposal.reason    = "DipBuy Long: Umkehrkerze in Zone";
        }
      else
        {
         outProposal.stopPrice = MathMax(m_stopSwingPrice, refPrice + m_atrStopMult * atr);
         outProposal.reason    = "DipBuy Short: Umkehrkerze in Zone";
        }
     }

public:
                     CSignalDipBuy(void):
                        m_state(ST_IDLE), m_dir(SIGNAL_FLAT), m_allowShort(false),
                        m_swingLookback(5), m_swingSearchDepth(250), m_atrStopMult(2.0),
                        m_armedExpiryBars(10), m_expiryCounter(0), m_magic(0),
                        m_zoneLow(0.0), m_zoneHigh(0.0), m_stopSwingPrice(0.0), m_targetPrice(0.0) {}

   void              Configure(const bool allowShort, const int swingLookback, const double atrStopMult,
                               const int armedExpiryBars, const int magic)
     {
      m_allowShort      = allowShort;
      m_swingLookback   = swingLookback;
      m_atrStopMult     = atrStopMult;
      m_armedExpiryBars = armedExpiryBars;
      m_magic           = magic;
     }

   ENUM_SETUP_STATE  GetState(void) const { return m_state; }
   ENUM_SIGNAL_DIR   GetDir(void) const { return m_dir; }

   //--- Fuer den TradeManager: altes Swing-Hoch/-Tief als Teilgewinn-Ziel
   //--- der aktuell laufenden (bzw. gerade eroeffneten) Position.
   double            GetTargetPrice(void) const { return m_targetPrice; }

   //+------------------------------------------------------------------+
   //| Vom Haupt-EA einmal pro neuer H4-Bar aufgerufen, solange KEINE   |
   //| eigene Position offen ist. Liefert true + gefuellte outProposal, |
   //| wenn ein Trigger gefeuert hat (Zustand wechselt dann auf         |
   //| ST_PENDING - der Aufrufer meldet das Ergebnis ueber Notify*()    |
   //| zurueck).                                                        |
   //+------------------------------------------------------------------+
   bool              OnBar(CMarketData &md, SignalProposal &outProposal)
     {
      outProposal.Reset();

      if(m_state == ST_ARMED || m_state == ST_WAIT_TRIGGER)
        {
         if(!CheckBias(md, m_dir))
           {
            ResetToIdle("Bias verloren");
            return false;
           }

         double close1;
         if(md.GetCloseD1(1, close1))
           {
            bool zoneInvalid = (m_dir == SIGNAL_LONG) ? (close1 < m_stopSwingPrice)
                                                       : (close1 > m_stopSwingPrice);
            if(zoneInvalid)
              {
               ResetToIdle("Zone ungueltig - Swing-Extremum verletzt");
               return false;
              }
           }

         //--- InpArmedExpiryBars ist in D1-Bars definiert (ea.md), OnBar() wird aber
         //--- pro geschlossener H4-Bar aufgerufen - daher nur bei tatsaechlichem
         //--- D1-Bar-Wechsel dekrementieren, sonst verfaellt das Setup 4x zu schnell.
         if(md.IsNewD1Bar())
           {
            m_expiryCounter--;
            if(m_expiryCounter <= 0)
              {
               ResetToIdle("Setup abgelaufen (InpArmedExpiryBars)");
               return false;
              }
           }

         double refPrice;
         bool   triggerMatch = CheckTriggerCandle(md, m_dir, refPrice);

         if(PriceInZone(refPrice))
           {
            if(m_state == ST_ARMED)
               m_state = ST_WAIT_TRIGGER;

            if(triggerMatch)
              {
               BuildProposal(md, refPrice, outProposal);
               m_state = ST_PENDING;
               return true;
              }
           }

         return false;
        }

      if(m_state == ST_IDLE)
        {
         if(CheckBiasAndSetup(md, SIGNAL_LONG))
            Arm(SIGNAL_LONG);
         else if(m_allowShort && CheckBiasAndSetup(md, SIGNAL_SHORT))
            Arm(SIGNAL_SHORT);

         return false; // fruehestens im naechsten Bar kann getriggert werden
        }

      return false; // ST_PENDING/ST_IN_POSITION/ST_BLOCKED: vom Aufrufer verwaltet
     }

   //--- Callbacks des Haupt-EA nach Order-Ausfuehrung / Filter-Veto / Positions-Ende.
   void              NotifyFilled(void)      { m_state = ST_IN_POSITION; }
   void              NotifyOrderFailed(void) { ResetToIdle("Order fehlgeschlagen"); }
   void              NotifyFilterVeto(void)
     {
      m_state = ST_BLOCKED;
      ResetToIdle("FilterStack-Veto");
     }
   void              NotifyPositionClosed(void) { ResetToIdle("Position geschlossen"); }

   //--- Nach Neustart/Reattach: Zustand aus vorhandener Position rekonstruieren.
   //--- dir muss vom Aufrufer aus der tatsaechlichen Positionsrichtung (Broker)
   //--- ermittelt werden, da m_dir sonst auf SIGNAL_FLAT verbleibt und
   //--- TradeManager dann faelschlich den Short-Zweig fuer eine Long-Position
   //--- (oder umgekehrt) durchlaeuft.
   void              SyncInPosition(const ENUM_SIGNAL_DIR dir)
     {
      m_dir   = dir;
      m_state = ST_IN_POSITION;
     }
  };

#endif // __SWINGGOLD_SIGNALDIPBUY_MQH__
