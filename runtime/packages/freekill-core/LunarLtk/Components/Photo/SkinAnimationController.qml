import QtQuick

QtObject {
  id: root
  property var target: null
  property bool ready: false
  property string normalAnim: ""
  property string shownAnim: ""
  property string attackAnim: ""
  property string skillAnim: ""
  property string hurtAnim: ""
  property string activeAction: ""
  property int generation: 0
  readonly property bool eventOnly: !normalAnim && !shownAnim && !!(attackAnim || skillAnim || hurtAnim)
  readonly property bool artworkEnabled: !eventOnly || !!activeAction

  function restoreIdle() {
    ++generation;
    activeAction = "";
    if (!target || !ready) return;
    target.clearTracks();
    target.setToSetupPose();
    target.visible = !eventOnly;
    if (normalAnim) target.setAnimation(0, normalAnim, true);
  }
  function playOnce(name, action) {
    if (!target || !ready || !name) return false;
    ++generation;
    target.clearTracks();
    target.setToSetupPose();
    target.visible = true;
    target.setAnimation(0, name, false);
    if (!target.isPlaying(0)) { restoreIdle(); return false; }
    activeAction = action;
    if (normalAnim) target.addAnimation(0, normalAnim, true, 0);
    return true;
  }
  function start(includeShown) {
    restoreIdle();
    if (includeShown && shownAnim) playOnce(shownAnim, "shown");
  }
  function playAction(action) {
    const names = {attack: attackAnim, skill: skillAnim, hurt: hurtAnim};
    const priority = {shown: 0, attack: 1, skill: 2, hurt: 3};
    if (!names[action] || !ready) return false;
    // New actions replace the old one; lower-priority events cannot cover hurt/skill.
    if (activeAction && priority[action] < priority[activeAction]) return false;
    return playOnce(names[action], action);
  }
  onTargetChanged: { ++generation; activeAction = ""; }
  onReadyChanged: if (!ready) { ++generation; activeAction = ""; }
  property Connections completion: Connections {
    target: root.target
    ignoreUnknownSignals: true
    function onComplete(trackIndex, loopCount) {
      if (trackIndex !== 0 || !root.activeAction) return;
      const expected = root.generation;
      // Do not mutate Spine tracks inside its animation-completion callback.
      Qt.callLater(function() {
        if (expected !== root.generation || !root.target || !root.ready) return;
        if (root.normalAnim) root.activeAction = "";
        else root.restoreIdle();
      });
    }
  }
}
