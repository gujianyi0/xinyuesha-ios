// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef FK_IOS_CORE_REPAIR_H
#define FK_IOS_CORE_REPAIR_H

#include <QDir>
#include <QCryptographicHash>
#include <QFile>
#include <QFileInfo>
#include <QString>
#include <QUuid>
#include <git2.h>
#include <git2/errors.h>

namespace fkIosCoreRepair {

// Never discover a parent repository or accept an unborn/missing HEAD.
inline bool validRepository(const QString &path) {
  git_repository *repo = nullptr;
  git_reference *head = nullptr;
  git_object *commit = nullptr;
  bool valid = git_repository_open_ext(&repo, path.toUtf8().constData(),
                                       GIT_REPOSITORY_OPEN_NO_SEARCH, nullptr) == 0
      && git_repository_head(&head, repo) == 0
      && git_reference_peel(&commit, head, GIT_OBJECT_COMMIT) == 0;
  git_object_free(commit);
  git_reference_free(head);
  git_repository_free(repo);
  git_error_clear();
  return valid;
}

inline bool copyTree(const QString &source, const QString &target) {
  const QFileInfo info(source);
  if (info.isSymLink()) return false;
  if (info.isDir()) {
    if (!QDir().mkpath(target)) return false;
    const auto entries = QDir(source).entryList(
        QDir::Files | QDir::Dirs | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot);
    for (const auto &entry : entries)
      if (!copyTree(source + '/' + entry, target + '/' + entry)) return false;
    return true;
  }
  return info.isFile() && QFile::copy(source, target);
}

// Works on both a fresh installation and an already installed 0.5.25 runtime.
// Only the invalid core directory is replaced; user files and packages.db stay
// untouched. The old directory remains outside packages for recovery.
inline bool repair(const QString &bundleRuntime, const QString &dataRuntime,
                   QString *error = nullptr) {
  struct GitScope {
    GitScope() { git_libgit2_init(); }
    ~GitScope() { git_libgit2_shutdown(); }
  } gitScope;
  // Retire only the exact local title component shipped in the previous IPA.
  // It is not a server extension and otherwise causes the next MD5 check to fail.
  const QString legacy = dataRuntime + "/packages/gujianyi_title";
  QFile legacyFile(legacy + "/GujianyiTitle.qml");
  if (legacyFile.open(QIODevice::ReadOnly)
      && QCryptographicHash::hash(legacyFile.readAll(), QCryptographicHash::Sha256).toHex()
          == "7df22b87c26b411a9197d6244aaa536f43a4fa35486e494b32b5d17a8f6ceccf") {
    legacyFile.close();
    const auto entries = QDir(legacy).entryList(
        QDir::Files | QDir::Dirs | QDir::Hidden | QDir::NoDotAndDotDot);
    const QString recovery = dataRuntime + "/.core-recovery";
    if (entries == QStringList{QStringLiteral("GujianyiTitle.qml")}) {
      const QString backup = recovery + "/legacy-title-"
          + QUuid::createUuid().toString(QUuid::WithoutBraces);
      if (!QDir().mkpath(recovery) || !QDir().rename(legacy, backup)) {
        if (error) *error = QStringLiteral("Cannot retire the previous local title component.");
        return false;
      }
    }
  }
  const QString target = dataRuntime + "/packages/freekill-core";
  if (validRepository(target)) return true;

  const QString source = bundleRuntime + "/packages/freekill-core";
  auto fail = [&](const QString &message) {
    if (error) *error = message;
    return false;
  };
  // The read-only .app bundle may be owned by the iOS installer. Do not open
  // its repository with libgit2's ownership check; validate the copied stage,
  // which belongs to the running app, without disabling that safety check.
  if (!QFile::exists(source + "/.git/HEAD")
      || !QFile::exists(source + "/Fk/main.qml"))
    return fail(QStringLiteral("The bundled core repository is incomplete."));

  const QString recovery = dataRuntime + "/.core-recovery";
  const QString id = QUuid::createUuid().toString(QUuid::WithoutBraces);
  const QString staging = recovery + "/staging-" + id;
  const QString backup = recovery + "/core-" + id;
  if (!QDir().mkpath(recovery) || !QDir().mkpath(dataRuntime + "/packages"))
    return fail(QStringLiteral("Cannot create the core recovery directory."));
  if (!copyTree(source, staging) || !validRepository(staging)) {
    QDir(staging).removeRecursively();
    return fail(QStringLiteral("Cannot copy the core repository. Check free storage."));
  }

  const bool existed = QFileInfo::exists(target);
  if (existed && !QDir().rename(target, backup)) {
    QDir(staging).removeRecursively();
    return fail(QStringLiteral("Cannot preserve the previous core directory."));
  }
  if (!QDir().rename(staging, target)) {
    const bool restored = !existed || QDir().rename(backup, target);
    QDir(staging).removeRecursively();
    return fail(restored ? QStringLiteral("Cannot install the repaired core repository.")
                        : QStringLiteral("Core recovery needs help; the old core is in .core-recovery."));
  }
  return true;
}

} // namespace fkIosCoreRepair
#endif
