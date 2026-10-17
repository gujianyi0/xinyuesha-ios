local W = require "ui_emu.preferences"

local settings = {
  W.PreferenceGroup {
    title = "Properties",

    W.SpinRow {
      _settingsKey = "generalNum",
      title = "Select generals num",
      from = 3,
      to = 18,
      editable = true,
    },

    W.SpinRow {
      _settingsKey = "generalTimeout",
      title = "Choose General timeout",
      from = 10,
      to = 60,
      editable = true,
      enabled = function (settings)
        return not settings._game["timeoutAsGeneralTimeout"]
      end,
      value = function (settings)
        if settings._game["timeoutAsGeneralTimeout"] then
          return settings.timeout
        else
          return settings._game["generalTimeout"]
        end
      end,
    },

    W.SwitchRow {
      _settingsKey = "timeoutAsGeneralTimeout",
      title = "Timeout as general timeout",
    },

    W.SpinRow {
      _settingsKey = "luckTime",
      title = "Luck Card Times",
      from = 0,
      to = 8,
      editable = true,
    },
  },

  W.PreferenceGroup {
    title = "Game Rule",

    W.SwitchRow {
      _settingsKey = "enableFreeAssign",
      title = "Enable free assign",
    },

    W.SwitchRow {
      _settingsKey = "enableDeputy",
      title = "Enable deputy general",
    },

    W.SwitchRow {
      _settingsKey = "disableSameConvert",
      title = "Disable same convert",
    }
  },

  W.PreferenceGroup {
    title = "Observe",

    W.SwitchRow {
      _settingsKey = "enableObserverViewCard",
      title = "Observer can view card",
    },

    W.SwitchRow {
      _settingsKey = "enableObserverViewFakeSkills",
      title = "Observer can view fake skills",
    },
  }
}

Fk:addBoardGame {
  name = "lunarltk",
  room_klass = require "ltk.server.room",
  client_klass = require "ltk.client.client",
  engine = Fk,
  page = {
    uri = "LunarLtk.Pages",
    name = "Room",
  },
  ui_settings = settings,
}
