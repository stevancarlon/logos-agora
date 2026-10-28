#include "../backend/ForumBackend.h"
#include <QGuiApplication>
#include <QFileInfo>
#include <QJsonDocument>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickView>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTimer>
#include <functional>
#include <QDir>
#include <QSqlDatabase>
#include <QSqlQuery>
int main(int argc, char **argv) {
  QGuiApplication app(argc, argv);
  app.setOrganizationName("LogosForum");
  app.setApplicationName("ForumPreview");
  QTemporaryDir temporary;
  const auto args = app.arguments();
  if (args.contains("--screenshot") || args.contains("--demo"))
    qputenv("LOGOS_FORUM_DATA_DIR", temporary.path().toUtf8());
  else if (qEnvironmentVariableIsEmpty("LOGOS_FORUM_DATA_DIR"))
    qputenv("LOGOS_FORUM_DATA_DIR", QStandardPaths::writableLocation(
                                        QStandardPaths::AppLocalDataLocation)
                                        .toUtf8());
  ForumBackend backend;
  QString exampleThread;
  if ((args.contains("--screenshot") || args.contains("--demo")) && !args.contains("--empty")) {
    auto call = [&](QJsonObject c) {
      return QJsonDocument::fromJson(
                 backend.dispatch(QString::fromUtf8(QJsonDocument(c).toJson()))
                     .toUtf8())
          .object();
    };
    QStringList titles = {
        "[Example] What should we improve next?",
        "[Example] A small guide to running a local node",
        "[Example] How should community moderation work?",
        "[Example] Planning our next local meetup",
        "[Example] Privacy tools that actually fit into daily life",
        "[Example] What are you building this week?"};
    QStringList boards = {"general", "building", "governance", "circles", "privacy", "building"};
    QStringList bodies = {
        "An open thread for ideas, feedback, and honest critiques. What would make Agora better?",
        "I put together a simple guide for getting a local node running on a standard laptop. Feedback welcome.",
        "What principles should guide moderation here? Looking for thoughtful perspectives.",
        "Let’s discuss possible dates, locations, and what we’d like to do. All ideas welcome!",
        "What tools have made a real difference for you? Looking for practical, sustainable choices.",
        "Small updates, big milestones, or just tinkering — share what you’re working on."};
    QStringList sampleReplies = {
        "[Example reply] Better quote navigation would make long discussions easier to follow.",
        "[Example reply] Could the guide include what happens after restarting an offline node?",
        "[Example reply] I would start with clear board rules and a transparent appeal process.",
        "[Example reply] A short show-and-tell followed by a practical workshop sounds useful.",
        "[Example reply] Simple defaults matter more to me than a long list of settings.",
        "[Example reply] I am exploring a local-first reading list. The hardest part is keeping sync understandable."};
    for (int i = 0; i < titles.size(); ++i) {
      auto t =
          call({{"op", "post"},
                {"board", boards[i]},
                {"title", titles[i]},
                {"body", bodies[i]}});
      if (i == 2)
        exampleThread = t["id"].toString();
      for (int j = 0; j < i % 3; j++)
        call({{"op", "post"},
              {"board", boards[i]},
              {"thread", t["id"]},
              {"body", j == 0 ? sampleReplies[i] : QString("[Example reply] What would be the simplest way to test that idea with a small group?")}});
    }
  }
  if (args.contains("--media-dir")) {
    // Seeding is restricted to temporary previews or the dedicated examples profile.
    const auto data = qEnvironmentVariable("LOGOS_FORUM_DATA_DIR");
    if (!args.contains("--screenshot") && !args.contains("--demo") &&
        !data.endsWith("/AgoraExamples/module_data/logos_forum")) return 6;
    auto call = [&](QJsonObject c) {
      auto result = QJsonDocument::fromJson(backend.dispatch(QString::fromUtf8(QJsonDocument(c).toJson())).toUtf8()).object();
      if (!result["ok"].toBool()) qFatal("Demo media operation failed: %s", qPrintable(result["error"].toString()));
      return result;
    };
    const auto media = QDir(args.value(args.indexOf("--media-dir")+1));
    const bool inlineDemo=args.contains("--inline-video-demo");
    const QString title = inlineDemo ? "[Example] Video playback inside Agora" : "[Example] Workshop ideas - images, video and PDF";
    for (const auto &value : call({{"op","snapshot"}})["posts"].toArray()) {
      const auto p = value.toObject();
      if (p["title"].toString() == title) exampleThread = p["id"].toString();
    }
    // Existing examples are left intact; re-running does not duplicate this thread.
    bool exists = false;
    for (const auto &value : call({{"op","snapshot"}})["posts"].toArray())
      if (value.toObject()["title"].toString() == title) exists = true;
    if (!exists) {
      auto attach = [&](QString name) -> QJsonValue {
        return call({{"op","attachmentImport"},{"file",QUrl::fromLocalFile(media.filePath(name)).toString()}})["attachment"].toObject()["id"];
      };
      exampleThread = call({{"op","post"},{"board","building"},{"title",title},
        {"body",inlineDemo ? "Press Play to watch this sample inside Agora. Try pause, the seek bar, mute and volume. Playback stops when you leave this discussion." : "A rough diagram for a local-first workshop. What would you change? These are sample attachments, saved only in this examples profile."},
        {"attachments",QJsonArray{attach(inlineDemo ? "playback-test.mp4" : "workshop-diagram.png")}}})["id"].toString();
      if(!inlineDemo) call({{"op","post"},{"board","building"},{"thread",exampleThread},{"body","Here is a six-second playback test. Play it right here, then try pausing, seeking or changing the volume."},
        {"attachments",QJsonArray{attach("playback-test.mp4")}}});
      if(!inlineDemo) call({{"op","post"},{"board","building"},{"thread",exampleThread},{"body","I drafted a one-page sample agenda. Open the PDF to read it, or download a copy."},
        {"attachments",QJsonArray{attach("workshop-plan.pdf")}}});
    }
    if (args.contains("--seed-media")) { qInfo("MEDIA_EXAMPLE_THREAD %s", qPrintable(exampleThread)); return 0; }
  }
  if (args.contains("--light") && args.contains("--screenshot"))
    backend.dispatch(QStringLiteral("{\"op\":\"settings\",\"theme\":\"light\"}"));
  if (args.contains("--avatar") && args.contains("--screenshot")) {
    const auto file = QFileInfo(QStringLiteral(FORUM_QML_PATH)).absolutePath()+"/../assets/icon.png";
    backend.dispatch(QString::fromUtf8(QJsonDocument(QJsonObject{{"op","avatar"},{"file",QUrl::fromLocalFile(file).toString()}}).toJson()));
  }
  if (args.contains("--export-demo") && args.contains("--demo")) {
    for (const auto &name : QSqlDatabase::connectionNames()) {
      QSqlQuery checkpoint(QSqlDatabase::database(name));
      if (!checkpoint.exec("PRAGMA wal_checkpoint(FULL)")) return 3;
    }
    const auto destination = args.value(args.indexOf("--export-demo") + 1);
    if (destination.isEmpty() || QFileInfo::exists(destination)) return 4;
    QDir().mkpath(QFileInfo(destination).absolutePath());
    return QFile::copy(temporary.path() + "/forum.sqlite", destination) ? 0 : 5;
  }
  QQuickView view;
  view.setResizeMode(QQuickView::SizeRootObjectToView);
  view.rootContext()->setContextProperty("forumLocal", &backend);
  view.setSource(QUrl::fromLocalFile(QStringLiteral(FORUM_QML_PATH)));
  if (view.status() == QQuickView::Error)
    return 1;
  view.resize(args.contains("--wide") ? 1780 : args.contains("--reference") ? 1484 : args.contains("--compact") ? 400 : args.contains("--narrow") ? 560 : 1200, args.contains("--reference") ? 926 : 800);
  if (args.contains("--width")) view.setWidth(args.value(args.indexOf("--width") + 1).toInt());
  if (args.contains("--height")) view.setHeight(args.value(args.indexOf("--height") + 1).toInt());
  view.setTitle(args.contains("--demo") ? "Agora — local demo · sample threads" : "Agora");
  view.show();
  if (args.contains("--screenshot")) {
    if (args.contains("--identity") || args.contains("--network")) {
      const auto name = args.contains("--identity") ? QString("identityDialog") : QString("networkDialog");
      QTimer::singleShot(300, &app, [&view, name, advanced=args.contains("--network-advanced")]() {
        auto dialog = view.rootObject()->findChild<QObject *>(name);
        if (dialog && advanced) dialog->setProperty("advanced", true);
        if (dialog) QMetaObject::invokeMethod(dialog, "open");
      });
    }
    if (args.contains("--compose"))
      QTimer::singleShot(300, &app, [&view]() { QMetaObject::invokeMethod(view.rootObject(), "compose"); });
    if (args.contains("--thread"))
      QTimer::singleShot(300, &app, [&view, exampleThread]() {
        QMetaObject::invokeMethod(view.rootObject(), "openThread",
                                  Q_ARG(QVariant, QVariant(exampleThread)));
      });
    if (args.contains("--thread-end"))
      QTimer::singleShot(700, &app, [&view]() {
        auto posts = view.rootObject()->findChild<QObject *>("postsView");
        if (posts) QMetaObject::invokeMethod(posts, "positionViewAtEnd");
      });
    if (args.contains("--video")) {
      QString aid;
      const auto snapshot=QJsonDocument::fromJson(backend.dispatch("{\"op\":\"snapshot\"}").toUtf8()).object();
      for(const auto &post:snapshot["posts"].toArray())
        for(const auto &file:post.toObject()["attachments"].toArray())
          if(file.toObject()["mime"].toString().startsWith("video/")) aid=file.toObject()["id"].toString();
      QTimer::singleShot(650,&app,[&view]() {
        auto posts=view.rootObject()->findChild<QObject*>("postsView");
        if(posts) QMetaObject::invokeMethod(posts,"positionViewAtIndex",Q_ARG(int,1),Q_ARG(int,0));
      });
      QTimer::singleShot(850,&app,[&view,aid,showControls=args.contains("--video-controls")]() {
        std::function<QQuickItem*(QQuickItem*)> find = [&](QQuickItem *item)->QQuickItem* {
          if(item->objectName()=="video-"+aid) return item;
          for(auto child:item->childItems()) if(auto found=find(child)) return found;
          return nullptr;
        };
        auto player=find(view.rootObject());
        auto posts=view.rootObject()->findChild<QQuickItem*>("postsView");
        if(player && posts) {
          auto content=posts->property("contentItem").value<QQuickItem*>();
          if(content) posts->setProperty("contentY",qMax(0., player->mapToItem(content,QPointF(0,0)).y()-100));
          QMetaObject::invokeMethod(player,"playPause");
          if(showControls) player->forceActiveFocus();
        }
      });
    }
    auto path = args.value(args.indexOf("--screenshot") + 1);
    QTimer::singleShot(args.contains("--video") ? 2000 : 1000, &app, [&view, &app, path]() {
      if (!view.grabWindow().save(path))
        app.exit(2);
      else
        app.quit();
    });
  }
  return app.exec();
}
