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

#endif // __SWINGGOLD_MAGICNUMBERS_MQH__
