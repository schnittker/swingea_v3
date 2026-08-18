//+------------------------------------------------------------------+
//|                                                 MagicNumbers.mqh |
//|   Magic-Nummern-Schema: InpMagicBase + Modul-Offset.             |
//|   Aktuell nur ein Signalmodul (DipBuy); das Offset-Schema bleibt |
//|   bewusst bestehen, damit Phase 2/3 weitere Module anhaengen     |
//|   koennen, ohne bestehende Magic-Nummern zu verschieben.         |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_MAGICNUMBERS_MQH__
#define __SWINGGOLD_MAGICNUMBERS_MQH__

//--- Modul-Offsets, ab InpMagicBase addiert. Fix, nicht umsortieren,
//--- da bereits laufende Positionen ueber die Magic-Nummer identifiziert
//--- werden.
#define MAGIC_OFFSET_DIPBUY   1
#define MAGIC_OFFSET_OVERLAP  2   // Overlap-Trendfolge (Phase 3)
#define MAGIC_OFFSET_SWEEP    3   // LiquiditySweep-Reclaim (Tier 2.1)
#define MAGIC_OFFSET_LBMAFIX  4   // LBMA-Fix-Reversal (Tier 3, experimentell)
#define MAGIC_OFFSET_ASIA     5   // Asia-Range-Breakout (Tier 2, Hypothese 2)

//+------------------------------------------------------------------+
//| Liefert die Magic-Nummer des DipBuy-Moduls fuer die gegebene     |
//| Basis-Nummer (InpMagicBase).                                     |
//+------------------------------------------------------------------+
int MagicDipBuy(const int magicBase)
  {
   return magicBase + MAGIC_OFFSET_DIPBUY;
  }

//+------------------------------------------------------------------+
//| Liefert die Magic-Nummer des OverlapTrend-Moduls.                |
//+------------------------------------------------------------------+
int MagicOverlapTrend(const int magicBase)
  {
   return magicBase + MAGIC_OFFSET_OVERLAP;
  }

//+------------------------------------------------------------------+
//| Liefert die Magic-Nummer des LiquiditySweep-Moduls.             |
//+------------------------------------------------------------------+
int MagicLiquiditySweep(const int magicBase)
  {
   return magicBase + MAGIC_OFFSET_SWEEP;
  }

//+------------------------------------------------------------------+
//| Liefert die Magic-Nummer des LbmaFixReversal-Moduls.            |
//+------------------------------------------------------------------+
int MagicLbmaFixReversal(const int magicBase)
  {
   return magicBase + MAGIC_OFFSET_LBMAFIX;
  }

//+------------------------------------------------------------------+
//| Liefert die Magic-Nummer des AsiaRangeBreakout-Moduls.          |
//+------------------------------------------------------------------+
int MagicAsiaRangeBreakout(const int magicBase)
  {
   return magicBase + MAGIC_OFFSET_ASIA;
  }

#endif // __SWINGGOLD_MAGICNUMBERS_MQH__
