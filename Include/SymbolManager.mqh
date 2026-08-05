//+------------------------------------------------------------------+
//|                                                SymbolManager.mqh |
//|   Parst die CSV-Symbolliste, validiert Symbole und legt die       |
//|   Daily-Indikator-Handles (MA fast/slow + ATR) je Symbol an.      |
//+------------------------------------------------------------------+
#ifndef __TRENDMOMENTUM_SYMBOLMANAGER_MQH__
#define __TRENDMOMENTUM_SYMBOLMANAGER_MQH__

#include "Types.mqh"

class CSymbolManager
  {
private:
   SymbolState       m_symbols[];
   int               m_count;
   int               m_maFastPeriod;
   int               m_maSlowPeriod;
   int               m_atrPeriod;

   //--- Ein Feld aus der CSV trimmen (fuehrende/abschliessende Spaces)
   string            Trim(const string s)
     {
      string r=s;
      StringTrimLeft(r);
      StringTrimRight(r);
      return r;
     }

public:
                     CSymbolManager(void): m_count(0),m_maFastPeriod(100),
                        m_maSlowPeriod(200),m_atrPeriod(14) {}
                    ~CSymbolManager(void) { Release(); }

   //--- Konfiguration der Indikator-Perioden (vor Init aufrufen)
   void              Configure(const int maFast,const int maSlow,const int atr)
     {
      m_maFastPeriod=maFast;
      m_maSlowPeriod=maSlow;
      m_atrPeriod=atr;
     }

   int               Count(void) const { return m_count; }

   //--- Zugriff auf den State per Referenz (fuer Signal/Risk/Trade-Module)
   SymbolState*      At(const int i)
     {
      if(i<0 || i>=m_count) return NULL;
      return GetPointer(m_symbols[i]);
     }

   //+------------------------------------------------------------------+
   //| CSV parsen, Symbole validieren, Handles anlegen.                 |
   //| Gibt false zurueck, wenn kein einziges gueltiges Symbol bleibt.  |
   //+------------------------------------------------------------------+
   bool              Init(const string csvSymbols)
     {
      Release();

      string parts[];
      int n=StringSplit(csvSymbols,',',parts);
      if(n<=0)
        {
         Print("SymbolManager: leere Symbolliste");
         return false;
        }

      ArrayResize(m_symbols,n);
      m_count=0;

      for(int i=0;i<n;i++)
        {
         string sym=Trim(parts[i]);
         if(sym=="") continue;

         if(!SymbolSelect(sym,true))
           {
            PrintFormat("SymbolManager: '%s' nicht verfuegbar - uebersprungen",sym);
            continue;
           }

         SymbolState st;
         st.name         = sym;
         st.valid        = false;
         st.targetDir    = SIGNAL_FLAT;
         st.atr          = 0.0;
         st.stopDistance = 0.0;

         st.maFastHandle = iMA(sym,PERIOD_D1,m_maFastPeriod,0,MODE_SMA,PRICE_CLOSE);
         st.maSlowHandle = iMA(sym,PERIOD_D1,m_maSlowPeriod,0,MODE_SMA,PRICE_CLOSE);
         st.atrHandle    = iATR(sym,PERIOD_D1,m_atrPeriod);

         if(st.maFastHandle==INVALID_HANDLE ||
            st.maSlowHandle==INVALID_HANDLE ||
            st.atrHandle==INVALID_HANDLE)
           {
            PrintFormat("SymbolManager: Indikator-Handle fuer '%s' fehlgeschlagen",sym);
            continue;
           }

         st.valid=true;
         m_symbols[m_count]=st;
         m_count++;
        }

      if(m_count==0)
        {
         Print("SymbolManager: kein gueltiges Symbol nach Validierung");
         return false;
        }

      ArrayResize(m_symbols,m_count);
      PrintFormat("SymbolManager: %d Symbol(e) initialisiert",m_count);
      return true;
     }

   //--- Alle Indikator-Handles freigeben
   void              Release(void)
     {
      for(int i=0;i<m_count;i++)
        {
         if(m_symbols[i].maFastHandle!=INVALID_HANDLE) IndicatorRelease(m_symbols[i].maFastHandle);
         if(m_symbols[i].maSlowHandle!=INVALID_HANDLE) IndicatorRelease(m_symbols[i].maSlowHandle);
         if(m_symbols[i].atrHandle   !=INVALID_HANDLE) IndicatorRelease(m_symbols[i].atrHandle);
        }
      ArrayResize(m_symbols,0);
      m_count=0;
     }
  };

#endif // __TRENDMOMENTUM_SYMBOLMANAGER_MQH__
