#include "../backend/ForumBackend.h"
#include <QQmlContext>
#include <QQmlEngine>
#include <QTemporaryDir>
#include <QtQuickTest/quicktest.h>
#include <memory>
class Setup : public QObject {
  Q_OBJECT
  QTemporaryDir data;
  std::unique_ptr<ForumBackend> backend;
public slots:
  void applicationAvailable() {
    qputenv("LOGOS_FORUM_DATA_DIR", data.path().toUtf8());
    backend = std::make_unique<ForumBackend>();
  }
  void qmlEngineAvailable(QQmlEngine *engine) {
    engine->rootContext()->setContextProperty("forumLocal", backend.get());
    connect(engine, &QObject::destroyed, this, [this] { backend.reset(); });
  }
};
QUICK_TEST_MAIN_WITH_SETUP(forum_ui, Setup)
#include "ui_main.moc"
