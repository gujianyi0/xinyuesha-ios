// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls

import Fk
import Fk.Widgets as W

W.PreferencePage {
  groupWidth: width * 0.8

  W.PreferenceGroup {

    W.SwitchRow {
      title: Lua.tr("Hide unselectable cards")
      subTitle: Lua.tr("help: Hide unselectable cards")
      checked: Config.hideUseless
      onCheckedChanged: Config.hideUseless = checked;
    }

    W.SwitchRow {
      title: Lua.tr("Rotate table card")
      subTitle: Lua.tr("help: Rotate table card")
      checked: Config.rotateTableCard
      onCheckedChanged: Config.rotateTableCard = checked;
    }

  }

  W.PreferenceGroup {
    W.SwitchRow {
      title: Lua.tr("Auto select the only target")
      subTitle: Lua.tr("help: Auto select the only target")
      checked: Config.autoTarget
      onCheckedChanged: Config.autoTarget = checked;
    }

    /*
     W.SwitchRow {
       title: Lua.tr("Double click to use card or skill")
       subTitle: Lua.tr("help: Double click to use card or skill")
       checked: Config.doubleClickUse
       onCheckedChanged: Config.doubleClickUse = checked;
     }
     */

    W.SwitchRow {
      title: Lua.tr("Do not use nullification to own one-target trick")
      subTitle: Lua.tr("help: Do not use nullification to own one-target trick")
      checked: Config.noSelfNullification
      onCheckedChanged: Config.noSelfNullification = checked;
    }

    W.SwitchRow {
      title: Lua.tr("Enable Super Drag")
      subTitle: Lua.tr("help: Enable Super Drag")
      checked: Config.enableSuperDrag
      onCheckedChanged: Config.enableSuperDrag = checked;
    }
  }

  W.PreferenceGroup {
    W.SwitchRow {
      title: Lua.tr("Hide Screen Name")
      subTitle: Lua.tr("help: Hide Screen Name")
      checked: Config.hideScreenName
      onCheckedChanged: Config.hideScreenName = checked;
    }

    W.SwitchRow {
      title: Lua.tr("Ban Change Skins")
      subTitle: Lua.tr("help: Ban Change Skins")
      checked: Config.banChangeSkin
      onCheckedChanged: Config.banChangeSkin = checked;
    }

    W.ActionRow {
      id: invitationSetting
      objectName: "blockRoomInvitationsSetting"
      title: Lua.tr("Block all room invitations")
      subTitle: RoomInvites.networkEnabled
        ? Lua.tr("help: Block all room invitations") : Lua.tr("Room invitations are unavailable on this server")
      enabled: RoomInvites.networkEnabled && !RoomInvites.settingPending
      onClicked: RoomInvites.setBlocked(!RoomInvites.blocked)
      suffixComponent: Controls.Switch {
        checked: RoomInvites.blocked
        enabled: invitationSetting.enabled
        onToggled: {
          RoomInvites.setBlocked(checked);
          checked = Qt.binding(() => RoomInvites.blocked);
        }
      }
    }
  }

}
