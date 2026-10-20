// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Fk

Item {
  id: root
  objectName: "fkCardCounter"
  anchors.fill: parent
  z: 800
  visible: expanded
  property bool expanded: false
  property var snapshot: ({ready:false,rows:[]})
  property var roomModel: null
  property string scope: "unseen"
  property int category: 0
  property string filterText: ""
  property bool hideZero: false
  property string selectedKey: "slash"
  property string lastPayload: ""
  property var rowLookup: ({})
  property var catalogueRows: []
  property var rows: []
  property string catalogueSignature: ""
  property string visibleSignature: ""
  property int viewRevision: 0
  property string lastError: ""
  property string titleFont: "Microsoft YaHei"
  property var readSnapshot: function() {
    if (typeof ClientInstance === "undefined" || !ClientInstance)
      return {ready:false,rows:[],message:"等待客户端连接"};
    return Lua.ev('(function() if not FkCardCounterV2 then FkCardCounterV2 = dofile("card-counter/counter.lua") end return FkCardCounterV2.current('+JSON.stringify(root.selectedKey)+') end)()');
  }
  property var cardPicture: function(name) { return SkinBank.getCardPicture(name); }
  readonly property string scopeTitle: ({unseen:"未见牌",discard:"弃牌堆",hand:"我的手牌"})[scope]
  readonly property var selectedRow: rowLookup[selectedKey] || null
  // Keep GridView's catalogue model stable when only live counts change.
  // Replacing a JS array model tears down visible delegates and interrupts flicks.
  function updateRows(preservePosition) {
    const next = (catalogueRows || []).filter(function(r) {
      return (!category || r.kind===category) && (!hideZero || (rowLookup[r.key] || {})[scope]>0)
        && (!filterText || r.name.indexOf(filterText)>=0 || r.key.indexOf(filterText.toLowerCase())>=0);
    });
    const signature=JSON.stringify(next);
    if (signature!==visibleSignature) {
      const columns=Math.max(1,Math.floor(cards.width/cards.cellWidth));
      const oldY=Math.max(0,cards.contentY-cards.originY);
      const first=Math.floor(oldY/cards.cellHeight)*columns;
      const offset=oldY%cards.cellHeight;
      const oldRows=rows;
      const revision=++viewRevision;
      visibleSignature=signature; rows=next;
      if (preservePosition && oldY>0 && next.length && oldRows.length) {
        // Derived cards and hide-zero membership can change the catalogue too.
        // Keep the first surviving visible card, with its fractional row offset.
        let anchor=-1;
        for (let i=first;i<oldRows.length && anchor<0;i++)
          anchor=next.findIndex(r => r.key===oldRows[i].key);
        if (anchor<0) anchor=Math.min(first,next.length-1);
        Qt.callLater(function() {
          if (root.viewRevision!==revision || cards.moving) return;
          cards.forceLayout();
          const y=cards.originY+Math.floor(anchor/columns)*cards.cellHeight+offset;
          cards.contentY=Math.max(cards.originY,Math.min(y,cards.originY+Math.max(0,cards.contentHeight-cards.height)));
        });
      }
    }
  }
  onCategoryChanged: updateRows()
  onHideZeroChanged: updateRows()
  onScopeChanged: updateRows()
  onFilterTextChanged: updateRows()
  onSelectedKeyChanged: if (expanded) refresh()
  readonly property color gold: "#CCAD76"
  readonly property color pale: "#F0E2C6"
  function open() { expanded=true; forceActiveFocus(); }
  function close() { expanded=false; }
  function toggle() { if (expanded) close(); else open(); }
  function refresh() {
    try {
      const value=readSnapshot();
      if (!value) return;
      const payload=JSON.stringify(value);
      if (payload!==lastPayload) {
        const lookup=({});
        const catalogue=(value.rows || []).map(function(row) {
          lookup[row.key]=row;
          return {key:row.key,name:row.name,kind:row.kind};
        });
        const signature=JSON.stringify(catalogue);
        rowLookup=lookup; snapshot=value; lastPayload=payload;
        if (signature!==catalogueSignature) { catalogueSignature=signature; catalogueRows=catalogue; }
        updateRows(true);
      }
      if (value.error && lastError!==value.error) { lastError=value.error; console.warn("[CardCounter] "+value.error); }
    } catch(e) {
      if (String(e)!==lastError) console.warn("[CardCounter] "+e);
      lastError=String(e); snapshot={ready:false,rows:[],message:"记牌数据暂不可用"};
      rowLookup=({}); catalogueRows=[]; rows=[];
      catalogueSignature=""; visibleSignature=""; lastPayload="";
    }
  }
  function suitCount(suit) {
    const d=selectedRow && selectedRow.details && selectedRow.details[scope];
    return d ? (d.suits[suit-1] || 0) : 0;
  }
  function pointCount(suit, rank) {
    const d=selectedRow && selectedRow.details && selectedRow.details[scope];
    return d ? (d.points[(suit-1)*14+rank] || 0) : 0;
  }
  function specialCount() {
    const d=selectedRow && selectedRow.details && selectedRow.details[scope];
    if (!d) return 0;
    let n=0;
    for (let s=0;s<5;s++) for (let rank=0;rank<14;rank++)
      if (s===4 || rank===0) n+=d.points[s*14+rank] || 0;
    return n;
  }
  onExpandedChanged: if (expanded) refresh()
  Keys.onEscapePressed: close()
  // Do not marshal a large Lua snapshot onto the UI thread during a gesture.
  // Counts catch up immediately after dragging/flicking stops.
  Timer { interval:500; running:root.expanded && !cards.moving; repeat:true; onTriggered:root.refresh() }
  Rectangle { anchors.fill:parent; color:"#9900090D" }
  MouseArea { anchors.fill:parent; onClicked:root.close() }

  Rectangle {
    id: panel
    objectName:"counterPanel"
    width:Math.min(1060,parent.width-56)
    height:Math.min(468,parent.height-40)
    anchors.centerIn:parent
    radius:10; color:"#151E22"; border.color:root.gold
    MouseArea { anchors.fill:parent }
    Rectangle { anchors.fill:parent; anchors.margins:4; color:"transparent"; border.color:"#3C443E"; radius:7 }
    Rectangle {
      x:1; y:1; width:parent.width-2; height:55; radius:9
      gradient:Gradient { GradientStop {position:0;color:"#3C3B30"} GradientStop {position:1;color:"#222A28"} }
    }
    Rectangle { x:20; y:54; width:parent.width-40; height:1; color:"#665D46" }
    Text { x:24; y:13; text:"记 牌 器"; font.family:root.titleFont; font.pixelSize:23; font.bold:true; color:root.pale }
    Text { x:154; y:23; text:"观已知 · 断未见"; font.pixelSize:11; color:"#AFAB96"; font.letterSpacing:2 }
    Row {
      anchors.right:closeButton.left; anchors.rightMargin:22; y:16; spacing:20
      Text { text:"本局牌池  "+(root.snapshot.total || 0); color:"#C5C4AF"; font.pixelSize:13 }
      Text { text:"牌堆  "+(root.roomModel ? root.roomModel.drawPileNum : "—"); color:root.pale; font.pixelSize:13 }
    }
    Rectangle {
      id:closeButton
      objectName:"counterClose"
      anchors.right:parent.right; anchors.rightMargin:14; y:10; width:36; height:36; radius:18
      color:closeMouse.containsMouse ? "#60513A" : "#252D2B"; border.color:"#7A6B4F"
      Text { anchors.centerIn:parent; text:"×"; color:root.pale; font.pixelSize:26 }
      MouseArea { id:closeMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked:root.close() }
    }
    Row {
      x:24; y:66; spacing:8
      Repeater {
        model:[{key:"unseen",name:"未见牌"},{key:"discard",name:"弃牌堆"},{key:"hand",name:"我的手牌"}]
        Rectangle {
          required property var modelData
          objectName:"scope-"+modelData.key
          width:133; height:36; radius:5
          color:root.scope===modelData.key ? "#544A34" : "#202A2C"
          border.color:root.scope===modelData.key ? "#C8A96D" : "#384440"
          Text { anchors.centerIn:parent; text:modelData.name+"   "+(root.snapshot[modelData.key] || 0); color:root.scope===modelData.key ? "#F4DFAE" : "#AAB6AF"; font.pixelSize:14; font.bold:root.scope===modelData.key }
          MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:root.scope=modelData.key }
        }
      }
    }
    Text {
      anchors.right:parent.right; anchors.rightMargin:24; y:78
      text:root.snapshot.ready ? "●  随本局自选牌池同步" : (root.snapshot.message || "等待牌局数据")
      color:root.snapshot.ready ? "#93B99C" : "#C0A876"; font.pixelSize:11
    }
    Item {
      id:body
      x:24; y:115; width:parent.width-48; height:parent.height-147
      Item {
        id:catalogue
        width:parent.width-298; height:parent.height
        Row {
          id:categories; spacing:4
          Repeater {
            model:["全部","基本","锦囊","装备"]
            Rectangle {
              required property int index
              required property string modelData
              width:54; height:28; radius:3; color:root.category===index ? "#3B4439" : "transparent"
              Text { anchors.centerIn:parent; text:modelData; color:root.category===index ? "#EEDBA8" : "#99A99F"; font.pixelSize:12 }
              MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:root.category=index }
            }
          }
        }
        TextField {
          id:search
          objectName:"counterSearch"
          anchors.right:parent.right; width:Math.min(176,parent.width-categories.width-12); height:28
          // This compact field uses its own placeholder instead of Material's
          // floating label, which sits above a 28 px field when the IME opens.
          placeholderText:""; color:root.pale; font.pixelSize:12
          leftPadding:10; rightPadding:8; topPadding:0; bottomPadding:0
          verticalAlignment:TextInput.AlignVCenter
          selectionColor:"#5C6245"; onTextChanged:root.filterText=text
          Text {
            anchors.fill:parent; anchors.leftMargin:10; anchors.rightMargin:8
            verticalAlignment:Text.AlignVCenter; text:"搜索牌名…"; color:"#7D8C83"
            font:search.font; visible:!search.text && !search.activeFocus; elide:Text.ElideRight
          }
          background:Rectangle { radius:4; color:"#10191B"; border.color:search.activeFocus ? "#B89C65" : "#3F4D46" }
        }
        GridView {
          id:cards
          objectName:"counterGrid"
          y:39; width:parent.width; height:parent.height-66
          clip:true; cellWidth:width/5; cellHeight:82; model:root.rows
          boundsBehavior:Flickable.StopAtBounds
          reuseItems:true; cacheBuffer:cellHeight*2
          onMovingChanged: if (!moving && root.expanded) Qt.callLater(root.refresh)
          ScrollBar.vertical:ScrollBar { policy:ScrollBar.AsNeeded }
          delegate:Item {
            id:tile
            required property var modelData
            width:cards.cellWidth; height:cards.cellHeight
            readonly property bool selected:root.selectedKey===modelData.key
            readonly property int total:(root.rowLookup[modelData.key] || {}).total || 0
            readonly property int amount:(root.rowLookup[modelData.key] || {})[root.scope] || 0
            Rectangle {
              anchors.fill:parent; anchors.rightMargin:7; anchors.bottomMargin:7; radius:5
              color:tile.selected ? "#394039" : (tileMouse.containsMouse ? "#2F3832" : "#252E2B")
              border.color:tile.selected ? "#D1AF70" : "#485044"; border.width:tile.selected ? 2 : 1
              Image { x:5; y:5; width:44; height:63; fillMode:Image.PreserveAspectCrop; smooth:true; asynchronous:true; sourceSize:Qt.size(132,189); source:root.cardPicture(tile.modelData.key); opacity:tile.amount ? 0.95 : 0.30 }
              Text {
                x:55; y:8; width:parent.width-59; height:24; text:tile.modelData.name
                color:tile.amount ? "#E6DFC8" : "#8F978B"; font.pixelSize:12
                font.bold:true; elide:Text.ElideRight; verticalAlignment:Text.AlignVCenter
              }
              Text { x:55; y:31; text:tile.amount; color:tile.amount ? "#EFDA9E" : "#778477"; font.pixelSize:27; font.bold:true }
              Text { anchors.right:parent.right; anchors.rightMargin:8; y:49; text:"/ "+tile.total; color:"#89968A"; font.pixelSize:10 }
              Rectangle {
                x:55; y:65; width:Math.max(0,parent.width-63); height:2; color:"#111C18"
                Rectangle { width:parent.width*Math.min(1,tile.amount/Math.max(1,tile.total)); height:2; color:tile.selected ? "#C8AC72" : "#72856B" }
              }
              MouseArea { id:tileMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked:root.selectedKey=tile.modelData.key }
            }
          }
          Text { anchors.centerIn:parent; visible:cards.count===0; text:root.snapshot.ready ? "没有符合条件的牌" : "等待牌局数据"; color:"#A6AF9E"; font.pixelSize:15 }
        }
        Row {
          y:parent.height-21; spacing:8
          Rectangle {
            objectName:"counterHideZero"
            width:15; height:15; radius:3; color:root.hideZero ? "#C2A66D" : "#141F1D"; border.color:"#897E5E"
            Text { anchors.centerIn:parent; text:root.hideZero ? "✓" : ""; color:"#18251E"; font.pixelSize:13; font.bold:true }
            MouseArea { anchors.fill:parent; anchors.margins:-5; onClicked:root.hideZero=!root.hideZero }
          }
          Text { text:"隐藏数量为 0 的牌"; color:"#A5AF9D"; font.pixelSize:11 }
          Text { text:"·  点选卡牌查看详情"; color:"#748777"; font.pixelSize:11 }
        }
      }
      Rectangle { x:catalogue.width+12; width:1; height:parent.height; color:"#4E5546" }
      Item {
        id:details
        anchors.right:parent.right; width:270; height:parent.height
        Row {
          x:2; spacing:14
          Rectangle {
            width:68; height:94; radius:4; color:"#BCAE8E"; border.color:"#DDC58D"
            Image { anchors.fill:parent; anchors.margins:2; fillMode:Image.PreserveAspectFit; asynchronous:true; sourceSize:Qt.size(204,282); source:root.selectedRow ? root.cardPicture(root.selectedRow.key) : "" }
          }
          Column {
            spacing:6; y:3
            Text { text:root.selectedRow ? root.selectedRow.name : "请选择卡牌"; color:root.pale; font.family:root.titleFont; font.pixelSize:21; font.bold:true }
            Text { text:root.selectedRow ? ["其他","基本牌","锦囊牌","装备牌"][root.selectedRow.kind] : ""; color:"#9BAA95"; font.pixelSize:11 }
            Row {
              spacing:5
              Text { text:root.selectedRow ? root.selectedRow[root.scope] : "—"; color:"#E9CC83"; font.pixelSize:30; font.bold:true }
              Text { y:16; text:root.scopeTitle; color:"#A7B19D"; font.pixelSize:11 }
            }
          }
        }
        Row {
          y:108; spacing:6
          Repeater {
            model:[{suit:1,glyph:"♠"},{suit:2,glyph:"♣"},{suit:3,glyph:"♥"},{suit:4,glyph:"♦"}]
            Rectangle {
              required property var modelData
              width:62; height:33; radius:4; color:"#242F2B"; border.color:"#455044"
              SuitIcon { x:8; y:8; suit:parent.modelData.suit }
              Text { anchors.right:parent.right; anchors.rightMargin:9; y:8; text:root.suitCount(modelData.suit); color:root.pale; font.pixelSize:14; font.bold:true }
            }
          }
        }
        Text { y:153; text:"花色 · 点数分布"; color:"#C2B58D"; font.pixelSize:12; font.bold:true }
        Text { y:155; anchors.right:parent.right; text:root.scopeTitle; color:"#7F917E"; font.pixelSize:10 }
        Item {
          y:179; width:parent.width; height:108
          Row {
            x:22
            Repeater {
              model:["A","2","3","4","5","6","7","8","9","10","J","Q","K"]
              Text { required property string modelData; width:19; height:20; text:modelData; color:"#8C9C86"; font.pixelSize:10; horizontalAlignment:Text.AlignHCenter }
            }
          }
          Column {
            y:21; spacing:2
            Repeater {
              model:["♠","♣","♥","♦"]
              Row {
                id:suitLine
                required property int index
                required property string modelData
                property int suit:index+1
                Item { width:22; height:21; SuitIcon {width:12;height:14;y:3;suit:suitLine.suit} }
                Repeater {
                  model:13
                  Rectangle {
                    required property int index
                    readonly property int amount:root.pointCount(suitLine.suit,index+1)
                    width:19; height:21; radius:2; color:amount ? "#4A4C35" : "#202D27"
                    Text { anchors.centerIn:parent; text:parent.amount || "·"; color:parent.amount ? "#F1DCA3" : "#4D6350"; font.pixelSize:11; font.bold:parent.amount>0 }
                  }
                }
              }
            }
          }
        }
        Text { y:parent.height-14; text:root.specialCount() ? "另有无花色／无点数牌："+root.specialCount() : "按实体原始牌面计数"; color:"#718970"; font.pixelSize:10 }
      }
    }
    Rectangle { x:24; y:parent.height-26; width:parent.width-48; height:1; color:"#3E493E" }
    Text { x:24; y:parent.height-19; text:"未见牌包含未知手牌，不等于牌堆内的精确分布。"; font.pixelSize:10; color:"#85977F" }
    Text { anchors.right:parent.right; anchors.rightMargin:24; y:parent.height-19; text:"点击外侧或 × 关闭"; font.pixelSize:10; color:"#85977F" }
  }
}
