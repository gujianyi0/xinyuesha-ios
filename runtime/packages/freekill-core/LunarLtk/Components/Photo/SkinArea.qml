import QtQuick
import QtMultimedia
import Spine

import Fk

import LunarLtk

pragma ComponentBehavior: Bound

Item {
  id: root
  property string general: ""
  property string skinName: ""
  property bool enabledShown: false
  readonly property bool isSkeleton: Ltk.isSkeletonSkin(general, skinName)
  readonly property string source:  {
    if (general && !skinName) return SkinBank.getGeneralPicture(general);
    return Ltk.getFullSkinPath(general, skinName);
  }
  readonly property var skelData: {
    const data = Ltk.getSkeletonSkinData(general, skinName)
    if (!data) refreshSkelSkinTimer.restart();
    return data
  }
  property bool hasDeputy: false //是否使用dual这个功能还是相信后人智慧吧
  clip: true
  function playAction(action) {
    return isSkeleton && imgLoader.item && typeof imgLoader.item.playAction === "function"
      ? imgLoader.item.playAction(action) : false;
  }

  Timer {
    id: refreshSkelSkinTimer
    interval: 1000
    repeat: false
    running: false

    onTriggered: {
      root.skinNameChanged() // 手动刷新一下
    }
  }

  Loader {
    id: imgLoader
    anchors.fill: parent
    sourceComponent: {
      if (root.isSkeleton) {
        if (root.skelData) return skeletonAnim;
      } else if (root.source.endsWith(".gif")) {
        return animated;
      } else if (root.source.endsWith(".mp4")) {
        return videoImg;
      } else {
        return staticImg;
      }
    }
  }

  Component {
    id: staticImg
    Image {
      anchors.fill: parent
      fillMode: Image.PreserveAspectCrop
      source: root.source
      smooth: true

    }
  }

  Component {
    id: animated
    AnimatedImage {
      anchors.fill: parent
      fillMode: Image.PreserveAspectCrop
      source: root.source
      playing: true
    }
  }

  Component {
    id: videoImg
    Video {
      id: videoPlayer
      anchors.fill: parent
      source: root.source
      loops: MediaPlayer.Infinite
      fillMode: Image.PreserveAspectCrop
      muted: true

      Component.onCompleted: play()
      Component.onDestruction: {
        videoPlayer.stop();
        videoPlayer.source = "";
      }
      onSourceChanged: {
        if (source !== "") {
          play();
        }
      }
    }
  }

  Component {
    id: skeletonAnim
    Item {
      id: skelHost
      anchors.fill: parent

      // —— 骨骼同步播放协调（等待真正加载完成 / 失败即跳过） ——
      // 先统计本皮肤应有的骨架层数量（bg / extraBg / body / front / extraFront；
      // bg、front 可能不存在，extra 数量可变），与下方实际创建逻辑保持一致。
      // 每层骨架在 Component.onCompleted 时注册到队列；但 QML 的 onCompleted 只
      // 代表组件树创建完成，骨架数据（PNG/JSON）是 C++ 异步加载的，二者并不同步。
      // 因此监听每层的 skeletonLoadFinished：只有“所有层都已给出加载结论（成功
      // loaded，或失败）”就统一播放——成功的层一起 setAnimation 起播，失败的层
      // 直接跳过。这样既保证各层真正同一时刻起播，又不会因个别坏层（文件缺失/
      // 版本不支持）而卡住整个皮肤等待。
      property var _skeletonQueue: []     // 元素：{ comp, shown, normal, done, ok }
      property var _layers: []
      property bool _skeletonsStarted: false
      property int _expectedCount: (function() {
        let n = 0
        if (!root.skelData.staticBg) ++n                                // 背景骨骼
        n += (root.skelData.extraBg ? root.skelData.extraBg.length : 0) // 额外背景
        ++n                                                             // 身体
        if (!root.skelData.atlasFrontFile.startsWith("undefined")) ++n  // 前景
        n += (root.skelData.extraFront ? root.skelData.extraFront.length : 0) // 额外前景
        return n
      })()

      function _registerSkeleton(comp, shown, normal) {
        skelHost._layers.push(comp)
        if (skelHost._skeletonsStarted) {
          // 统一播放后才完成注册（如模型动态增删）的层：立即单独起播
          skelHost._playOne(comp, shown, normal)
          return
        }
        const entry = { comp, shown, normal, done: comp.loadConcluded, ok: comp.loadOk }
        skelHost._skeletonQueue.push(entry)
        // 有新骨架注册 → 重置收集窗口（容纳 Loader/Repeater 内容稍晚注册）
        skeletonCollectTimer.restart()
        if (entry.done) {
          // 注册前已给出加载结论（极快完成或已失败）
          skelHost._maybeStartSkeletons()
          return
        }
        // 等待该层给出加载结论：成功(ok=true) 或失败(ok=false) 都算“结束”。
        // wrapper 缓存 loadConcluded/loadOk，这里用信号推进协调器。
        comp.skeletonLoadFinished.connect(function(ok) {
          entry.done = true
          entry.ok = !!ok
          skelHost._maybeStartSkeletons()
        })
      }

      // 收集窗口：任何骨架注册都会重启它，根 Item onCompleted 也会启动一次；
      // 窗口静默（没有新的层再加入）后判定收集完成——Loader 内容（front 等）
      // 即使比其它层晚一拍注册，也会在窗口内被纳入。
      Timer {
        id: skeletonCollectTimer
        interval: 32
        repeat: false
        onTriggered: skelHost._closeSkeletonCollection()
      }

      // 收集窗口关闭后调用：
      // 若统计数大于实际注册数（个别层因数据缺失/条件不满足未被创建），
      // 把期望修正为实际注册数，避免永远等一个不存在的层。
      function _closeSkeletonCollection() {
        if (skelHost._skeletonQueue.length < skelHost._expectedCount)
          skelHost._expectedCount = skelHost._skeletonQueue.length
        skelHost._maybeStartSkeletons()
      }

      // 所有层都已注册且全部给出结论（成功或失败）→ 统一播放成功层。
      // 关键：绝不“到点抢跑”——每个已注册层最终都会发加载结论（C++ 成功/失败
      // 都保证发出），等待不会卡死；抢跑会让先完成的层先播、后完成的层晚播，
      // 正是同一皮肤内各层不同步的根源。
      function _maybeStartSkeletons() {
        if (skelHost._skeletonsStarted)
          return
        if (skelHost._skeletonQueue.length < skelHost._expectedCount)
          return // 收集尚未完成
        for (const s of skelHost._skeletonQueue) {
          if (!s.done)
            return // 仍有层未给出加载结论：继续等待，不抢跑
        }
        skelHost._startSkeletons()
      }

      function _startSkeletons() {
        if (skelHost._skeletonsStarted)
          return
        // 仅当确有成功加载的层才锁定并统一播放；若全部失败（如远程文件暂不可用）
        // 保持未锁定，等待后续层重试成功后再次驱动播放。
        let anyOk = false
        for (const s of skelHost._skeletonQueue) {
          if (s.ok) { anyOk = true; break }
        }
        if (!anyOk)
          return
        skelHost._skeletonsStarted = true
        const queue = skelHost._skeletonQueue
        skelHost._skeletonQueue = []
        for (const s of queue) {
          if (s.ok)
            skelHost._playOne(s.comp, s.shown, s.normal)
        }
      }

      function _playOne(comp, shown, normal) {
        comp.startPlayback(root.enabledShown)
      }

      function playAction(action) {
        if (!skelHost._skeletonsStarted) return false
        let played = false
        for (const layer of skelHost._layers) {
          if (layer && layer.loadOk) played = layer.playAction(action) || played
        }
        return played
      }

      // QSGRenderNode 直接内联绘制时父级 clip / OpacityMask 对它不生效，
      // 需用 layer 离屏成纹理。但 layer 默认按“逻辑尺寸”采样（不乘 DPR、
      // 也不超采样），在高分屏/放大显示时骨骼会糊；因此手动把 textureSize
      // 设为逻辑尺寸的 2 倍做超采样，显示时缩小回逻辑尺寸，画面锐利。

      // 背景静态图（可选）
      Image {
        visible: !!root.skelData.staticBg
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        source: root.skelData.staticBg ? (root.skelData.path + root.skelData.staticBg) : ""
      }

      // 背景骨骼 —— 与人物骨骼放在同一父层级（用 Loader 条件创建：
      // 有 staticBg 时用静态图代替，不创建背景骨架，让计数与实际创建一致）。
      Loader {
        sourceComponent: !root.skelData.staticBg ? bgSkelCom : null
      }

      Component {
        id: bgSkelCom
        SkinSkeleton {
          animationData: root.skelData
          animationRole: "bg"
          atlasFile: root.skelData.path + root.skelData.atlasBgFile
          skeletonDataFile: root.skelData.path + root.skelData.skelBgFile
          skeletonScale: root.skelData.renderScale
          spineVersion: SpineVersion.Auto
          premultipliedAlapha: false
          x: root.width * root.skelData.bgXOffset
          y: root.height * root.skelData.bgYOffset
          scale: root.skelData.bgScale * root.height / root.skelData.renderScale / 175

          // 只注册不播放：等所有骨架层 onCompleted 后统一起播
          Component.onCompleted: skelHost._registerSkeleton(this,
            root.skelData.bgShownAnim, root.skelData.bgNormalAnim)
        }
      }

      Repeater {
        model: root.skelData.extraBg
        SkinSkeleton {
          animationData: root.skelData
          animationRole: "bg"
          required property var modelData
          atlasFile: root.skelData.path + modelData + ".atlas"
          skeletonDataFile: root.skelData.path + modelData + root.skelData.skelType
          skeletonScale: root.skelData.renderScale
          spineVersion: SpineVersion.Auto
          premultipliedAlapha: false
          x: root.width * root.skelData.bgXOffset
          y: root.height * root.skelData.bgYOffset
          scale: root.skelData.bgScale * root.height / root.skelData.renderScale / 175

          // 只注册不播放：等所有骨架层 onCompleted 后统一起播
          Component.onCompleted: skelHost._registerSkeleton(this,
            root.skelData.bgShownAnim, root.skelData.bgNormalAnim)
        }
      }

      SkinSkeleton {
        animationData: root.skelData
        animationRole: "body"
        id: skel
        atlasFile: root.skelData.path + root.skelData.atlasBodyFile
        skeletonDataFile: root.skelData.path + root.skelData.skelBodyFile
        skeletonScale: root.skelData.renderScale
        spineVersion: SpineVersion.Auto
        premultipliedAlapha: false
        x: root.width * root.skelData.bodyXOffset
        y: root.height * root.skelData.bodyYOffset
        scale: root.skelData.bodyScale * root.height / root.skelData.renderScale / 175

        // 只注册不播放：等所有骨架层 onCompleted 后统一起播
        Component.onCompleted: skelHost._registerSkeleton(this,
          root.skelData.bodyShownAnim, root.skelData.bodyNormalAnim)
      }

      Loader {
        sourceComponent: {
          if (!root.skelData.atlasFrontFile.startsWith("undefined")) {
            return frontSkelCom
          }
        }
      }

      Component {
        id: frontSkelCom
        SkinSkeleton {
          animationData: root.skelData
          animationRole: "front"
          id: skelFront
          atlasFile: root.skelData.path + root.skelData.atlasFrontFile
          skeletonDataFile: root.skelData.path + root.skelData.skelFrontFile
          skeletonScale: root.skelData.renderScale
          spineVersion: SpineVersion.Auto
          premultipliedAlapha: false
          x: root.width * root.skelData.frontXOffset
          y: root.height * root.skelData.frontYOffset
          scale: root.skelData.frontScale * root.height / root.skelData.renderScale / 175

          // 只注册不播放：等所有骨架层 onCompleted 后统一起播
          Component.onCompleted: skelHost._registerSkeleton(this,
            root.skelData.frontShownAnim, root.skelData.frontNormalAnim)
        }
      }

      Repeater {
        model: root.skelData.extraFront
        SkinSkeleton {
          animationData: root.skelData
          animationRole: "front"
          required property var modelData
          atlasFile: root.skelData.path + modelData + ".atlas"
          skeletonDataFile: root.skelData.path + modelData + root.skelData.skelType
          skeletonScale: root.skelData.renderScale
          spineVersion: SpineVersion.Auto
          premultipliedAlapha: false
          x: root.width * root.skelData.frontXOffset
          y: root.height * root.skelData.frontYOffset
          scale: root.skelData.frontScale * root.height / root.skelData.renderScale / 175

          // 只注册不播放：等所有骨架层 onCompleted 后统一起播
          Component.onCompleted: skelHost._registerSkeleton(this,
            root.skelData.frontShownAnim, root.skelData.frontNormalAnim)
        }
      }

      // 根 Item 的 onCompleted 在所有同步子骨架之后触发（QML 子先父后），
      // 此时大部分骨架已完成注册；启动收集窗口 Timer 收尾，给 Loader 内容
      // （front 等）最后一拍注册机会。之后窗口关闭 → 收窄期望 → 尝试统一播放。
      Component.onCompleted: skeletonCollectTimer.start()
    }
  }
}
