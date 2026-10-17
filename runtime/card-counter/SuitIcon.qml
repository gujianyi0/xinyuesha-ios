// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
Canvas {
  property int suit: 1
  property color tint: suit > 2 ? "#D9917F" : "#C9D0BD"
  width:16; height:16
  onSuitChanged:requestPaint()
  onTintChanged:requestPaint()
  onPaint: {
    const c=getContext("2d");c.reset();c.scale(width/16,height/16);c.fillStyle=tint;
    c.beginPath();
    if (suit===1) {
      c.moveTo(8,0);c.bezierCurveTo(6,4,1,5,1,9);c.bezierCurveTo(1,13,6,14,8,10);
      c.bezierCurveTo(10,14,15,13,15,9);c.bezierCurveTo(15,5,10,4,8,0);c.closePath();c.fill();
      c.beginPath();c.moveTo(8,8);c.lineTo(5,16);c.lineTo(11,16);c.closePath();
    } else if (suit===2) {
      c.arc(8,4,3.6,0,Math.PI*2);c.moveTo(8,9);c.arc(4,9,3.6,0,Math.PI*2);c.moveTo(15.6,9);c.arc(12,9,3.6,0,Math.PI*2);c.fill();
      c.beginPath();c.moveTo(8,8);c.lineTo(5,16);c.lineTo(11,16);c.closePath();
    } else if (suit===3) {
      c.moveTo(8,15);c.bezierCurveTo(5,12,0,9,0,5);c.bezierCurveTo(0,0,6,-1,8,4);
      c.bezierCurveTo(10,-1,16,0,16,5);c.bezierCurveTo(16,9,11,12,8,15);c.closePath();
    } else {
      c.moveTo(8,0);c.lineTo(15,8);c.lineTo(8,16);c.lineTo(1,8);c.closePath();
    }
    c.fill();
  }
}
