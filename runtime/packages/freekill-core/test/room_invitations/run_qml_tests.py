"""Run real invitation QML components with an isolated, non-networked client bridge."""
from pathlib import Path
import argparse, os, shutil, subprocess, tempfile, sys
sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--qt-bin", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="freekill-room-invites-", dir=args.output) as scratch:
    temp = Path(scratch)
    imports = temp / "imports"
    fk = imports / "Fk"
    shutil.copytree(Path(__file__).parent / "stubs" / "Fk", fk)
    shutil.copytree(Path(__file__).parent / "stubs" / "Spine", imports / "Spine")
    shutil.copy2(ROOT / "Fk/Base/RoomInvites.qml", fk / "RoomInvites.qml")
    shutil.copy2(ROOT / "Fk/Base/Mediator.qml", fk / "Mediator.qml")
    shutil.copy2(ROOT / "Fk/Base/AppUtil.qml", fk / "SessionApp.qml")
    shutil.copy2(ROOT / "Fk/Base/command.mjs", fk / "Command.mjs")
    with (fk / "qmldir").open("a", encoding="utf-8") as exports:
        exports.write("\nsingleton SessionApp 1.0 SessionApp.qml\nCommand 1.0 Command.mjs\n")
    # Run the production lobby callback, not a handwritten approximation of it.
    init_source = (ROOT / "Fk/Pages/Common/Init.qml").read_text(encoding="utf-8")
    start = init_source.index("  function enterLobby(sender, data) {")
    end = init_source.index("\n  //", start)
    callback = init_source[start:end].replace("App.", "SessionApp.")
    (fk / "LobbyEntry.qml").write_text("import QtQuick\nimport Fk\nQtObject {\n" + callback + "\n}\n", encoding="utf-8")
    with (fk / "qmldir").open("a", encoding="utf-8") as exports:
        exports.write("LobbyEntry 1.0 LobbyEntry.qml\n")
    for name in ("ToastManager.qml", "Toast.qml"):
        shutil.copy2(ROOT / "Fk/Base" / name, fk / name)
    for folder in ("Widgets", "Components/WaitingRoom", "Components/GameCommon"):
        shutil.copytree(ROOT / "Fk" / folder, fk / folder)
    common = fk / "Pages/Common"
    common.mkdir(parents=True)
    (common / "qmldir").write_text("module Fk.Pages.Common\nRoomInviteDialog 1.0 RoomInviteDialog.qml\nRoomInvitationPrompt 1.0 RoomInvitationPrompt.qml\n", encoding="utf-8")
    for name in ("RoomInviteDialog.qml", "RoomInvitationPrompt.qml"):
        shutil.copy2(ROOT / "Fk/Pages/Common" / name, common / name)
    lobby = fk / "Pages/Lobby"
    lobby.mkdir(parents=True)
    (lobby / "qmldir").write_text("module Fk.Pages.Lobby\nControlSetting 1.0 ControlSetting.qml\nAudioSetting 1.0 AudioSetting.qml\n", encoding="utf-8")
    (lobby / "Lobby.qml").write_text("import QtQuick\nItem {}\n", encoding="utf-8")
    with (lobby / "qmldir").open("a", encoding="utf-8") as exports:
        exports.write("Lobby 1.0 Lobby.qml\n")
    shutil.copy2(ROOT / "Fk/Pages/Lobby/ControlSetting.qml", lobby / "ControlSetting.qml")
    shutil.copy2(ROOT / "Fk/Pages/Lobby/AudioSetting.qml", lobby / "AudioSetting.qml")
    (temp / "tst_room_invitations.qml").write_text((Path(__file__).parent / "tst_room_invitations.qml").read_text(encoding="utf-8").replace("@OUTPUT@", str(args.output.resolve()).replace(chr(92), "/")).replace("@CORE@", ROOT.as_posix()), encoding="utf-8")
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QT_QUICK_CONTROLS_STYLE="Basic", INVITATION_TEST_OUTPUT=str(args.output.resolve()).replace("\\", "/"))
    env["PATH"] = str(args.qt_bin) + os.pathsep + str(args.qt_bin.parent.parent / "Tools/mingw1310_64/bin") + os.pathsep + env["PATH"]
    result = subprocess.run([str(args.qt_bin / "qmltestrunner.exe"), "-input", str(temp), "-import", str(ROOT), "-import", str(imports), "-o", str(args.output / "qml-results.txt") + ",txt"], env=env)
    print((args.output / "qml-results.txt").read_text(encoding="utf-8", errors="replace"))
    raise SystemExit(result.returncode)
