pragma Singleton
import QtQuick
import Fk

QtObject {
  property var styles: ({})
  readonly property real badgeWidth: 110
  readonly property real badgeHeight: 30
  readonly property var fallback: ({
    border: "#cecccd", background: "#838383", color: "snow",
    fontSize: 10, height: 14
  })

  function refresh() {
    styles = Lua.ev("Fk.title_styles or {}") || {};
    Config.titleTestEdition = Lua.ev("Fk.title_test_enabled == true") === true;
  }

  function resolve(code) {
    const legacy = {
      yellow: ["#e7dc7b", "#d3c93b"], red: ["#e79a7b", "#d3403b"],
      green: ["#afc96a", "#78b12f"], indigo: ["#7be7d5", "#32beb3"],
      blue: ["#7baae7", "#3b78d3"], purple: ["#ad7be7", "#643bd3"],
      pink: ["#e0a1c6", "#d4579c"], orange: ["#d3a36c", "#ce7f35"],
      grey: ["#cecccd", "#838383"]
    };
    if (styles[code]) return styles[code];
    if (legacy[code]) return { border: legacy[code][0], background: legacy[code][1], color: "snow" };
    return fallback;
  }

  function heightForWidth(maxWidth) {
    return Math.max(0, maxWidth) * badgeHeight / badgeWidth;
  }

  function localProfile(playerId, equippedId, requestedId) {
    // Build session-only test ownership from the installed registry, including future styles.
    const titles = Object.keys(styles).sort().filter(code => {
      const style = styles[code];
      return style && typeof style === "object" && !Array.isArray(style);
    }).map(code => ({
      id: "test_style_" + code,
      title: typeof styles[code].title === "string" && styles[code].title.trim()
        ? styles[code].title : code,
      style: code
    }));
    let selected = titles.find(title => title.id === equippedId) || {};
    let accepted = true;
    if (requestedId !== undefined) {
      const requested = titles.find(title => title.id === requestedId);
      if (typeof requestedId !== "string" || (requestedId !== "" && !requested)) {
        accepted = false;
      } else {
        selected = requested || {};
      }
    }
    return {
      playerId: playerId, supported: true, titles: titles, equipped: selected,
      ok: accepted, error: accepted ? "" : "称号不存在"
    };
  }

  function componentSource(code) {
    const path = resolve(code).component;
    // Component paths come from installed extensions, never network payloads.
    if (typeof path !== "string" || !path.startsWith("packages/")
        || path.includes("..") || path.includes(":")) return "";
    return Cpp.path + "/" + path;
  }
}
