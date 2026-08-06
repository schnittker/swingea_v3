//+------------------------------------------------------------------+
//|                                               SymbolResolver.mqh |
//|   Liest die Handelssymbol-Eigenschaften von _Symbol einmalig aus |
//|   und cached sie. Kein Fallback auf andere Symbolnamen - der EA  |
//|   laeuft ausschliesslich auf dem Chart-Symbol (ea.md 4.2).       |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_SYMBOLRESOLVER_MQH__
#define __SWINGGOLD_SYMBOLRESOLVER_MQH__

class CSymbolResolver
  {
private:
   string            m_symbol;
   bool              m_valid;

   int               m_digits;
   double            m_point;
   double            m_contractSize;
   double            m_volumeMin;
   double            m_volumeMax;
   double            m_volumeStep;
   int               m_stopsLevel;   // Points
   int               m_freezeLevel;  // Points

public:
                     CSymbolResolver(void):
                        m_symbol(""), m_valid(false), m_digits(0), m_point(0.0),
                        m_contractSize(0.0), m_volumeMin(0.0), m_volumeMax(0.0),
                        m_volumeStep(0.0), m_stopsLevel(0), m_freezeLevel(0) {}

   //+------------------------------------------------------------------+
   //| Prueft und cached alle relevanten Symbol-Eigenschaften.          |
   //| Gibt false zurueck, wenn das Symbol nicht handelbar ist.         |
   //+------------------------------------------------------------------+
   bool              Init(const string symbol)
     {
      m_symbol = symbol;
      m_valid  = false;

      if(!SymbolSelect(m_symbol, true))
        {
         PrintFormat("SymbolResolver: '%s' konnte nicht selektiert werden.", m_symbol);
         return false;
        }

      m_digits       = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      m_point        = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_contractSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      m_volumeMin    = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      m_volumeMax    = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      m_volumeStep   = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      m_stopsLevel   = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      m_freezeLevel  = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);

      if(m_point <= 0.0 || m_contractSize <= 0.0 || m_volumeStep <= 0.0)
        {
         PrintFormat("SymbolResolver: '%s' liefert unplausible Eigenschaften (Point=%.5f, ContractSize=%.2f, VolumeStep=%.2f).",
                     m_symbol, m_point, m_contractSize, m_volumeStep);
         return false;
        }

      m_valid = true;
      PrintFormat("SymbolResolver: %s init OK - Digits=%d Point=%.5f ContractSize=%.2f StopsLevel=%d FreezeLevel=%d",
                  m_symbol, m_digits, m_point, m_contractSize, m_stopsLevel, m_freezeLevel);
      return true;
     }

   bool              IsValid(void)          const { return m_valid; }
   string            Symbol(void)           const { return m_symbol; }
   int               Digits(void)           const { return m_digits; }
   double            Point(void)            const { return m_point; }
   double            ContractSize(void)     const { return m_contractSize; }
   double            VolumeMin(void)        const { return m_volumeMin; }
   double            VolumeMax(void)        const { return m_volumeMax; }
   double            VolumeStep(void)       const { return m_volumeStep; }
   int               StopsLevelPoints(void) const { return m_stopsLevel; }
   int               FreezeLevelPoints(void) const { return m_freezeLevel; }
  };

#endif // __SWINGGOLD_SYMBOLRESOLVER_MQH__
