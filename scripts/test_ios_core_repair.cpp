// SPDX-License-Identifier: GPL-3.0-or-later
#include "platform/ioscorerepair.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QProcess>
#include <QDebug>
#include <cstdlib>

static void require(bool ok, const char *message) {
  if (!ok) { qCritical() << message; std::exit(1); }
}
static void write(const QString &path, const QByteArray &data) {
  QDir().mkpath(QFileInfo(path).absolutePath());
  QFile file(path);
  require(file.open(QIODevice::WriteOnly) && file.write(data) == data.size(), "write fixture");
}
static QByteArray read(const QString &path) {
  QFile file(path); require(file.open(QIODevice::ReadOnly), "read fixture");
  return file.readAll();
}
static void git(const QString &repo, const QStringList &args) {
  QProcess process;
  process.start("git", QStringList{"-C", repo} + args);
  require(process.waitForFinished() && process.exitCode() == 0, "git fixture");
}
int main(int argc, char **argv) {
  QCoreApplication app(argc, argv);
  QTemporaryDir tmp;
  require(tmp.isValid(), "temporary directory");
  const QString source = tmp.path() + "/bundle/packages/freekill-core";
  write(source + "/Fk/main.qml", "pristine core\n");
  git(source, {"init"});
  git(source, {"config", "user.name", "Core test"});
  git(source, {"config", "user.email", "core-test@example.invalid"});
  git(source, {"add", "."});
  git(source, {"commit", "-m", "fixture"});
  QString error;
  const QString bundle = tmp.path() + "/bundle";

  for (const QString &scenario : {QString("missing"), QString("plain-files"),
                                  QString("unborn"), QString("broken-head")}) {
    const QString data = tmp.path() + '/' + scenario;
    const QString core = data + "/packages/freekill-core";
    write(data + "/freekill.client.config.json", "private account sentinel");
    write(data + "/assets/social-private/profiles.json", "private friends sentinel");
    write(data + "/packages/packages.db", "database sentinel");
    if (scenario != "missing") write(core + "/old.lua", "old core sentinel");
    if (scenario == "unborn") git(core, {"init"});
    if (scenario == "broken-head") {
      require(fkIosCoreRepair::copyTree(source + "/.git", core + "/.git"), "copy broken metadata");
      write(core + "/.git/HEAD", "ref: refs/heads/not-a-branch\n");
    }
    require(fkIosCoreRepair::repair(bundle, data, &error), qPrintable(error));
    require(read(core + "/Fk/main.qml") == "pristine core\n", "core restored");
    require(read(data + "/freekill.client.config.json") == "private account sentinel", "account preserved");
    require(read(data + "/assets/social-private/profiles.json") == "private friends sentinel", "friends preserved");
    require(read(data + "/packages/packages.db") == "database sentinel", "database preserved");
    require(!QFile::exists(core + "/old.lua"), "broken directory replaced");
    if (scenario != "missing") {
      const auto backups = QDir(data + "/.core-recovery").entryList({"core-*"}, QDir::Dirs);
      require(backups.size() == 1, "one recoverable backup");
      require(read(data + "/.core-recovery/" + backups[0] + "/old.lua") == "old core sentinel", "old core preserved");
    }
    // A healthy repo, even if modified, must not be reset on later starts.
    write(core + "/Fk/main.qml", "intentional modification\n");
    require(fkIosCoreRepair::repair(bundle, data, &error), "idempotent repair");
    require(read(core + "/Fk/main.qml") == "intentional modification\n", "healthy repository untouched");
  }
  const QString invalid = tmp.path() + "/invalid-source";
  const QString data = tmp.path() + "/failed-repair";
  write(data + "/packages/freekill-core/old.lua", "keep on failure");
  require(!fkIosCoreRepair::repair(invalid, data, &error), "bad source rejected");
  require(read(data + "/packages/freekill-core/old.lua") == "keep on failure", "failure preserves original");
  // Do not accidentally accept a parent repository as the core repository.
  git(data, {"init"});
  require(!fkIosCoreRepair::repair(invalid, data, &error), "no parent repository discovery");
  qInfo() << "Core recovery: fresh, missing Git, unborn/broken HEAD, preservation, idempotence and failure checks passed.";
}
