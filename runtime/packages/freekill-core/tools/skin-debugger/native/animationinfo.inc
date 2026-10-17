    QVariantList animationInfo() const override {
        QVariantList result;
        if (!mSkeleton || !mSkeleton->data) return result;
        const auto *data = mSkeleton->data;
        for (int i = 0; i < data->animationsCount; ++i) {
            const auto *animation = data->animations[i];
            result.append(QVariantMap{{QStringLiteral("name"), QString::fromUtf8(animation->name)},
                                      {QStringLiteral("duration"), double(animation->duration)}});
        }
        return result;
    }
