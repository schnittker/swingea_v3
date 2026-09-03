// Shared file-lock helpers for the Master/Slave copier EAs (MQL5).
// Provides a simple cooperative lock over the shared common-folder files,
// with stale-lock detection and a max-wait force-acquire fallback to avoid
// deadlocks if a terminal crashes while holding the lock.

input int  LockStaleSeconds   = 10;  // Force-remove lock file if older than this (deadlock protection)
input int  LockMaxWaitSeconds = 30;  // Give up waiting and force-acquire after this long

string LOCK_FILE = "copier.lock";  // Shared across Master and all Slaves

datetime GetLockTimestamp()
{
   int h = FileOpen(LOCK_FILE, FILE_READ|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE) return 0;
   datetime ts = (datetime)StringToInteger(FileReadString(h));
   FileClose(h);
   return ts;
}

bool Lock()
{
   datetime waitStart = TimeCurrent();

   while(FileIsExist(LOCK_FILE, FILE_COMMON))
   {
      datetime lockTs = GetLockTimestamp();
      bool stale = (lockTs > 0 && TimeCurrent() - lockTs > LockStaleSeconds);
      bool waitedTooLong = (TimeCurrent() - waitStart > LockMaxWaitSeconds);

      if(stale || waitedTooLong)
      {
         Print("WARNING: Force-removing lock file '", LOCK_FILE, "' | Stale=", stale,
               " | WaitedTooLong=", waitedTooLong, " | LockAge=", (lockTs>0 ? (long)(TimeCurrent()-lockTs) : -1));
         FileDelete(LOCK_FILE, FILE_COMMON);
         break;
      }

      Sleep(5);
   }

   int h = FileOpen(LOCK_FILE, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create lock file: ", LOCK_FILE, " | Error: ", GetLastError());
      return false;
   }
   FileWrite(h, (string)(long)TimeCurrent());
   FileClose(h);
   return true;
}

void Unlock()
{
   FileDelete(LOCK_FILE, FILE_COMMON);
}
