// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Fk

Item {
  id: bridge
  required property var page
  property var request: null
  property int endpoint: 0
  property var urls: [
    "https://cdn.jsdelivr.net/gh/Qsgs-Fans/freekill-server-list@master/server-list.json",
    "https://raw.githubusercontent.com/Qsgs-Fans/freekill-server-list/master/server-list.json"
  ]
  function validRows(value) {
    if (!Array.isArray(value) || value.length>512) return [];
    return value.filter(s=>s && typeof s.addr==="string" && /^[a-zA-Z0-9.:_-]{1,253}$/.test(s.addr) &&
      Number.isInteger(s.port) && s.port>0 && s.port<=65535).map(s=>({addr:s.addr,port:s.port,name:String(s.name || "").slice(0,160)}));
  }
  function start() {
    // Let the stock page restore favorites and cached servers before appending.
    // Never replace its model: doing so also drops manually added public rows.
    page.loadConfig();
    const data=Backend.readJsonObjectFromFile("card-counter/public-servers.json");
    page.appendServers(validRows(data && data.servers));
    fetch();
  }
  function fetch() {
    if (endpoint>=urls.length || request) return;
    const xhr=new XMLHttpRequest(); request=xhr;
    xhr.open("GET",urls[endpoint]);
    xhr.onreadystatechange=function() {
      if (xhr.readyState!==XMLHttpRequest.DONE || bridge.request!==xhr) return;
      deadline.stop(); bridge.request=null;
      let rows=[];
      if(xhr.status===200)try{rows=validRows(JSON.parse(xhr.responseText));}catch(_){}
      if(rows.length) {
        page.appendServers(rows);
        // Stock hashing and refresh remain available; this path has no hash-API prerequisite.
        page.writeCache("json",JSON.stringify(rows));
        Config.saveConf();
      } else {endpoint++;Qt.callLater(fetch);}
    };
    deadline.restart(); xhr.send();
  }
  Timer {id:deadline;interval:8000;onTriggered:{const xhr=bridge.request;bridge.request=null;if(xhr)xhr.abort();bridge.endpoint++;bridge.fetch();}}
  Component.onCompleted:Qt.callLater(start)
  Component.onDestruction:{deadline.stop();const xhr=request;request=null;if(xhr)xhr.abort();}
}
