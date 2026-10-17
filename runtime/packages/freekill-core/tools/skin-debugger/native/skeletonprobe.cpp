// SPDX-License-Identifier: GPL-3.0-or-later
#include "skeletonprobe.h"
#include "spinebackend.h"
#include "spineversion.h"
#include "texture.h"
#include <QtConcurrent/QtConcurrent>
#include <QFutureWatcher>
#include <QFileInfo>
#include <QImage>
#include <QQmlExtensionPlugin>
#include <qqml.h>
#include <algorithm>
#include <cmath>
#include <memory>

namespace {
QVariantMap inspectFile(const QString &skeleton, const QString &atlas,
                        const QStringList &names, bool whole, const QString &token) {
    QVariantMap result{{"token", token}, {"skeleton", skeleton}, {"atlas", atlas}};
    auto fail = [&](const QString &error) { result["error"] = error; return result; };
    if (!QFileInfo::exists(skeleton)) return fail(QStringLiteral("骨骼文件不存在：") + skeleton);
    if (!QFileInfo::exists(atlas)) return fail(QStringLiteral("图集文件不存在：") + atlas);
    const auto version = detectSpineVersion(skeleton);
    result["version"] = spineVersionToString(version);
    if (version == SpineVersion::Unknown || version == SpineVersion::Auto)
        return fail(QStringLiteral("无法识别骨骼版本；支持 2.1、3.4–3.8、4.0–4.2。"));
    std::unique_ptr<SpineBackend> backend(createSpineBackend(version));
    if (!backend || !backend->load(skeleton, atlas, 1, QStringLiteral("default")))
        return fail(QStringLiteral("骨骼加载失败，请核对版本、图集与贴图是否配套。"));
    const QVariantList animations = backend->animationInfo();
    result["animations"] = animations;
    QVector<SpineDrawCommand> initialCommands;
    backend->collectDrawCommands(initialCommands);
    for (const auto &command : initialCommands) {
        const auto texture = static_cast<Texture *>(command.texture);
        if (texture && !texture->image())
            return fail(QStringLiteral("贴图加载失败：") + texture->name());
    }
    if (names.isEmpty()) return result;

    QRectF bounds;
    bool hasBounds = false;
    auto include = [&]() {
        // Match the actual drawing batches, excluding invisible attachments.
        QVector<SpineDrawCommand> commands;
        backend->collectDrawCommands(commands);
        for (const auto &command : commands) {
            if (command.a <= 0 || !command.texture || command.vertexCount <= 0) continue;
            for (int i = 0; i < command.vertexCount; ++i) {
                const double x = command.vertices[i * 2], y = -command.vertices[i * 2 + 1];
                if (!std::isfinite(x) || !std::isfinite(y)) continue;
                if (!hasBounds) { bounds = QRectF(x, y, 0, 0); hasBounds = true; }
                else bounds = QRectF(QPointF(std::min(bounds.left(), x), std::min(bounds.top(), y)),
                                     QPointF(std::max(bounds.right(), x), std::max(bounds.bottom(), y)));
            }
        }
    };
    int sampleCount = 0;
    for (const QString &name : names) {
        // A fresh instance per clip also resets 4.2 physics constraints.
        if (sampleCount > 0) {
            backend.reset(createSpineBackend(version));
            if (!backend || !backend->load(skeleton, atlas, 1, QStringLiteral("default")))
                return fail(QStringLiteral("重新加载骨骼失败，无法测量完整动画。"));
        }
        float duration = 0;
        if (!name.isEmpty()) {
            bool found = false;
            for (const QVariant &entry : animations) {
                const auto animation = entry.toMap();
                if (animation["name"].toString() == name) {
                    duration = animation["duration"].toFloat(); found = true; break;
                }
            }
            if (!found) return fail(QStringLiteral("动画不存在：") + name);
        }
        if (!std::isfinite(duration) || duration < 0 || duration > 300)
            return fail(QStringLiteral("动画时长无效或超过 300 秒，请使用首帧适配。"));
        backend->clearTracks();
        backend->setToSetupPose();
        if (!name.isEmpty() && !backend->setAnimation(0, name, false)) return fail(QStringLiteral("无法播放动画：") + name);
        backend->update(0);
        include(); ++sampleCount;
        if (whole && duration > 0) {
            const int steps = int(std::ceil(duration * 30));
            for (int i = 1; i <= steps; ++i) {
                backend->update(std::min(1.0f / 30, duration - float(i - 1) / 30));
                include(); ++sampleCount;
            }
        }
    }
    if (!hasBounds || bounds.width() <= 0 || bounds.height() <= 0)
        return fail(QStringLiteral("该姿势没有可测量的可见图像，请选择其他动画。"));
    result["bounds"] = QVariantMap{{"x", bounds.x()}, {"y", bounds.y()},
                                  {"width", bounds.width()}, {"height", bounds.height()}};
    result["samples"] = sampleCount;
    result["fps"] = 30;
    return result;
}
}

void SkeletonProbe::inspect(const QUrl &skeleton, const QUrl &atlas,
                            const QStringList &animations, bool wholeAnimation, const QString &token) {
    const quint64 generation = ++mGeneration;
    if (!mBusy) { mBusy = true; Q_EMIT busyChanged(); }
    auto *watcher = new QFutureWatcher<QVariantMap>(this);
    connect(watcher, &QFutureWatcher<QVariantMap>::finished, this, [this, watcher, generation]() {
        const auto result = watcher->result();
        watcher->deleteLater();
        if (generation != mGeneration) return;
        mBusy = false; Q_EMIT busyChanged(); Q_EMIT completed(result);
    });
    watcher->setFuture(QtConcurrent::run(inspectFile, skeleton.toLocalFile(), atlas.toLocalFile(),
                                        animations, wholeAnimation, token));
}

class SkinInspectorPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override { qmlRegisterType<SkeletonProbe>(uri, 1, 0, "SkeletonProbe"); }
};
#include "skeletonprobe.moc"
