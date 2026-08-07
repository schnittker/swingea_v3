//+------------------------------------------------------------------+
//|                                             ClusterRiskGuard.mqh |
//|   Uebergreifendes Risiko-Management (ea.md 4.10, strategies.md  |
//|   Teil F). Summiert das offene Risiko ueber alle Positionen auf  |
//|   dem Chart-Symbol und den konfigurierten Korrelations-Cluster-  |
//|   Symbolen (Default: XAUUSD, XAGUSD, AUDUSD).                   |
//|                                                                   |
//|   Risiko je Position = |OpenPrice - SL| * (tickValue/tickSize)  |
//|   * Volume — exakt dieselbe Formel wie RiskManager.ComputeLots().|
//|                                                                   |
//|   Richtungen werden ADDIERT, nicht genettet (konservativ).       |
//|   Positionen ohne SL sind nicht quantifizierbar und blockieren   |
//|   per Default neue Trades (konfigurierbar).                      |
//|                                                                   |
//|   Graceful Degradation: fehlendes Cluster-Symbol -> eine         |
//|   Warnmeldung beim Init, Handel laeuft weiter (ea.md 2.6).      |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_CLUSTERRISKGUARD_MQH__
#define __SWINGGOLD_CLUSTERRISKGUARD_MQH__

class CClusterRiskGuard
  {
private:
   string            m_clusterSymbols[];  // aufgeloeste Symbol-Namen
   bool              m_clusterAvailable[]; // Verfuegbarkeit je Symbol
   int               m_clusterCount;
   double            m_maxClusterRiskPct;
   bool              m_countForeign;       // auch Fremd-Magic-Positionen?
   bool              m_noSLBlocks;         // Position ohne SL = Veto?
   bool              m_degraded;           // mind. ein Symbol fehlt

   //--- Risiko einer einzelnen Position in Kontowährung
   double            PositionRiskMoney(const string symbol, const ulong ticket)
     {
      if(!PositionSelectByTicket(ticket))
         return 0.0;

      double sl = PositionGetDouble(POSITION_SL);
      if(sl == 0.0)
         return -1.0; // Sonderfall: nicht quantifizierbar

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double volume    = PositionGetDouble(POSITION_VOLUME);
      double stopDist  = MathAbs(openPrice - sl);
      if(stopDist <= 0.0 || volume <= 0.0)
         return 0.0;

      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0.0 || tickValue <= 0.0)
         return 0.0;

      return (tickValue / tickSize) * stopDist * volume;
     }

public:
                     CClusterRiskGuard(void):
                        m_clusterCount(0), m_maxClusterRiskPct(3.0),
                        m_countForeign(true), m_noSLBlocks(true), m_degraded(false) {}

   //+------------------------------------------------------------------+
   //| Parst die Komma-getrennte Symbol-Liste und aktiviert jedes      |
   //| Symbol per SymbolSelect. Fehlende Symbole werden geloggt und    |
   //| als nicht verfuegbar markiert (kein INIT_FAILED).              |
   //+------------------------------------------------------------------+
   void              Configure(const string clusterList, const double maxClusterRiskPct,
                               const bool countForeign, const bool noSLBlocks)
     {
      m_maxClusterRiskPct = maxClusterRiskPct;
      m_countForeign      = countForeign;
      m_noSLBlocks        = noSLBlocks;
      m_degraded          = false;

      //--- Symbol-Liste parsen
      string parts[];
      int    n = StringSplit(clusterList, ',', parts);
      ArrayResize(m_clusterSymbols,   n);
      ArrayResize(m_clusterAvailable, n);
      m_clusterCount = 0;

      for(int i = 0; i < n; i++)
        {
         string sym = parts[i];
         StringTrimLeft(sym);
         StringTrimRight(sym);
         m_clusterSymbols[m_clusterCount] = sym;

         bool avail = SymbolSelect(sym, true);
         //--- Nochmals pruefen: bei manchen Brokern braucht SymbolSelect
         //--- einen Moment; wir validieren ueber einen echten Datenpunkt.
         if(avail)
           {
            double point = SymbolInfoDouble(sym, SYMBOL_POINT);
            avail = (point > 0.0);
           }

         m_clusterAvailable[m_clusterCount] = avail;
         if(!avail)
           {
            PrintFormat("ClusterRiskGuard: Symbol '%s' nicht verfuegbar - wird im Cluster ignoriert. "
                        "Handel laeuft weiter (ea.md 2.6).", sym);
            m_degraded = true;
           }
         else
           {
            PrintFormat("ClusterRiskGuard: Symbol '%s' im Cluster registriert.", sym);
           }
         m_clusterCount++;
        }
     }

   bool              IsDegraded(void) const { return m_degraded; }

   //+------------------------------------------------------------------+
   //| Summiert das gesamte offene Risiko ueber alle Cluster-Symbole.  |
   //| outUnquantifiable = true: mind. eine Position ohne SL gefunden. |
   //| outOffender: Name des ersten Verursachers (fuer Logmeldung).    |
   //+------------------------------------------------------------------+
   double            SumOpenRisk(bool &outUnquantifiable, string &outOffender)
     {
      outUnquantifiable = false;
      outOffender       = "";
      double total      = 0.0;

      int posTotal = PositionsTotal();
      for(int i = 0; i < posTotal; i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;

         string posSym  = PositionGetString(POSITION_SYMBOL);
         long   posMagic = PositionGetInteger(POSITION_MAGIC);

         //--- Gehoert diese Position zu einem Cluster-Symbol?
         bool inCluster = false;
         for(int j = 0; j < m_clusterCount; j++)
           {
            if(m_clusterAvailable[j] && m_clusterSymbols[j] == posSym)
              {
               inCluster = true;
               break;
              }
           }
         if(!inCluster)
            continue;

         //--- Fremd-Magics: nur wenn m_countForeign
         //--- (EA-eigene Magics sind stets enthalten)
         // Wir zaehlen alle Positionen auf Cluster-Symbolen —
         // das inkludiert eigene und ggf. fremde. 'countForeign'
         // deaktiviert nur Positionen, die NICHT mit eigenen Magics
         // uebereinstimmen. Da wir die eigenen Magics hier nicht kennen,
         // implementieren wir es als: countForeign=false = NUR Positionen
         // auf dem EA-Chart-Symbol (m_clusterSymbols[0] ist _Symbol).
         // Fuer eine striktere Trennung wuerde man die Magic-Liste uebergeben.
         // Pragmatischer Ansatz: countForeign=false ignoriert Nicht-Chart-Symbole.
         if(!m_countForeign && posSym != m_clusterSymbols[0])
            continue;

         double risk = PositionRiskMoney(posSym, ticket);
         if(risk < 0.0)
           {
            // Position ohne SL
            if(!outUnquantifiable)
               outOffender = StringFormat("%s Magic=%I64d (kein SL)", posSym, posMagic);
            outUnquantifiable = true;
            // addiere 0 — aber merke das Flag
           }
         else
           {
            total += risk; // Richtungen addieren, nicht netten
           }
        }

      return total;
     }

   //+------------------------------------------------------------------+
   //| Veto-Pruefung fuer einen neuen Trade: darf das neue Risiko      |
   //| (newRiskMoney, bereits berechnet vom RiskManager) hinzugefuegt  |
   //| werden, ohne den Cluster-Deckel zu uebersteigen?               |
   //| outCurrentPct: aktuell gebundenes Risiko als % der Equity.      |
   //+------------------------------------------------------------------+
   bool              AllowNewRisk(const double newRiskMoney, double &outCurrentPct,
                                  string &outReason)
     {
      outReason      = "";
      outCurrentPct  = 0.0;

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0)
        {
         outReason = "ClusterRiskGuard: Equity <= 0";
         return false;
        }

      bool   hasNoSL   = false;
      string offender;
      double currentRisk = SumOpenRisk(hasNoSL, offender);

      outCurrentPct = (currentRisk / equity) * 100.0;

      //--- Position ohne SL blockiert (wenn konfiguriert)
      if(hasNoSL && m_noSLBlocks)
        {
         outReason = StringFormat("ClusterRiskGuard: nicht-quantifizierbares Risiko (%s)", offender);
         return false;
        }

      //--- Deckel-Pruefung
      double totalRisk    = currentRisk + newRiskMoney;
      double totalRiskPct = (totalRisk / equity) * 100.0;

      if(totalRiskPct > m_maxClusterRiskPct)
        {
         outReason = StringFormat("ClusterRiskGuard: Cluster-Risiko %.2f%% + neu %.2f%% = %.2f%% > Deckel %.2f%%",
                                  outCurrentPct,
                                  (newRiskMoney / equity) * 100.0,
                                  totalRiskPct,
                                  m_maxClusterRiskPct);
         return false;
        }

      return true;
     }
  };

#endif // __SWINGGOLD_CLUSTERRISKGUARD_MQH__
