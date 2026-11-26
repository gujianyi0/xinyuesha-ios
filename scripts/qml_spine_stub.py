"""ABI-only Spine fixture for UI tests which never play an animation."""
def install_spine_stub(folder):
    module=folder/'Spine';module.mkdir(parents=True,exist_ok=True)
    (module/'qmldir').write_text('module Spine\nSkeletonAnimation 1.0 SkeletonAnimation.qml\nsingleton SpineVersion 1.0 SpineVersion.qml\n',encoding='utf8')
    (module/'SpineVersion.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject{enum Version{Auto}}',encoding='utf8')
    (module/'SkeletonAnimation.qml').write_text('''import QtQuick
Item{property url atlasFile;property url skeletonDataFile;property real skeletonScale:1;property real timeScale:1
 property int spineVersion:0;property bool premultipliedAlapha:false;property bool loaded:false
 signal skeletonLoadFinished(bool ok);signal complete(int trackIndex,int loopCount)
 function clearTracks(){} function setToSetupPose(){} function setAnimation(track,name,loop){} function isPlaying(track){return false;}}
''',encoding='utf8')
