pragma Singleton
import QtQuick

Item {
  id: root

  signal commandGot(variant sender, string command, variant data)

  Connections {
    target: Backend
    function onNotifyUI(command, data) {
      if (command === "Setup") {
        Config.resetTitleSession();
        TitleBank.refresh();
      } else if (command === "BackToStart") {
        Config.resetTitleSession();
        Config.consoleStartRequested = false;
      } else if (command === "SetServerSettings") {
        Config.resetTitleSession();
        TitleBank.refresh();
        const features = JSON.parse(JSON.stringify(data[2] || []));
        Config.titleServerSupported = Array.isArray(features) && features.includes("PlayerTitles");
        if (Config.consoleStartRequested || Config.titleServerSupported) Config.requestTitleProfile();
      } else if (command === "TitleProfile") {
        Config.applyTitleProfile(data);
      } else if (command === "PlayerTitle") {
        Config.applyPlayerTitle(data);
      } else if (command === "PlayerTitlesSnapshot") {
        const titles = JSON.parse(JSON.stringify(data));
        if (Array.isArray(titles)) for (const title of titles) Config.applyPlayerTitle(title);
      }
      root.notify(null, command, data);
    }
  }

  function notify(sender, command, data) {
    // Entering the lobby also clears old pages, while retaining the authenticated session.
    if (command === "BackToStart" && !(data && data.preserveSession === true)) RoomInvites.reset();
    else if (command === "Setup") {
      const accountId = Math.floor(data[0] || 0);
      // A seated/observing transition also sends Setup for the same account.
      if (accountId > 0 && RoomInvites.accountId > 0 && RoomInvites.accountId !== accountId)
        RoomInvites.reset();
      if (accountId > 0) RoomInvites.accountId = accountId;
    } else if (command === "EnterRoom") RoomInvites.setRoom(true);
    else if (command === "EnterLobby") RoomInvites.setRoom(false);
    else if (command === "SetServerSettings") {
      const accountId = RoomInvites.accountId;
      RoomInvites.reset();
      RoomInvites.accountId = accountId;
      const features = JSON.parse(JSON.stringify(data[2] || []));
      RoomInvites.supported = Array.isArray(features) && features.includes("RoomInvitations");
    } else if (command.startsWith("RoomInvite") || command === "RoomInvitation" || command === "RoomInvitationClosed") {
      RoomInvites.handle(command, data);
    }
    commandGot(sender, command, data);
  }
}
