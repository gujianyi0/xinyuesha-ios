import QtQuick
import Spine

SkeletonAnimation {
  id: root
  property var animationData: ({})
  property string animationRole: "body"
  readonly property string activeAction: controller.activeAction
  property bool _started: false
  property bool _includeShown: false
  function startPlayback(includeShown) { _started = true; _includeShown = includeShown; controller.start(includeShown); }
  function playAction(action) { return controller.playAction(action); }
  // A skin change can reuse the same QML layer and replace its skeleton files.
  onSkeletonLoadFinished: function(ok) { if (ok && _started) controller.start(_includeShown); }
  SkinAnimationController {
    id: controller
    target: root
    ready: root.loadOk
    normalAnim: root.animationData[root.animationRole + "NormalAnim"] ?? ""
    shownAnim: root.animationData[root.animationRole + "ShownAnim"] ?? ""
    attackAnim: root.animationData[root.animationRole + "AttackAnim"] ?? ""
    skillAnim: root.animationData[root.animationRole + "SkillAnim"] ?? ""
    hurtAnim: root.animationData[root.animationRole + "HurtAnim"] ?? ""
  }
}
