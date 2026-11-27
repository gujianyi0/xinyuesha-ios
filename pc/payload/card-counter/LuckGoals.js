// SPDX-License-Identifier: GPL-3.0-or-later
.pragma library
function canonical(value) {
    const s=String(value || "").trim().toLowerCase();
    return ({"ak":"crossbow","连弩":"crossbow","诸葛连弩":"crossbow","丈八":"spear","丈八蛇矛":"spear","杀":"slash"})[s] || s;
}
function parse(text) {
    const parts=String(text).split(/[,，]/);
    if(!parts.length || parts.length>6 || String(text).length>160)return null;
    const out=[];
    for(const part of parts) {
        const match=part.trim().match(/^([^:：×*]+?)(?:[:：×*]\s*(\d+))?$/);
        if(!match)return null;
        const names=match[1].split("/").map(canonical);
        const count=match[2]===undefined?1:Number(match[2]);
        if(names.some(n=>!n) || !Number.isInteger(count) || count<1 || count>99)return null;
        out.push({names:names,count:count});
    }
    return out;
}
