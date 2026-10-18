#include "platform/requestclock.h"
#include <QDebug>
#include <cstdlib>
static void require(bool ok) { if (!ok) std::exit(1); }
int main() {
  // Ten seconds spent preparing a login must not subtract five seconds from
  // every subsequent turn timer. The network exchange itself takes 100 ms.
  const qint64 connected=100000, sent=110000, server=110050, received=110100;
  require(fkRequestClock::offset(server,connected,received)==-5000);
  require(fkRequestClock::offset(server,sent,received)==0);
  require(fkRequestClock::offset(server-12345,sent,received)==12345);
  require(fkRequestClock::offset(server+12345,sent,received)==-12345);
  require(fkRequestClock::offset(server,server,server)==0);
  qInfo()<<"Login preparation exclusion and positive/negative clock offsets passed";
}
