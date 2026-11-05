#include "../backend/ForumBackend.h"
#include "../backend/ForumDataMigration.h"
#include <QScopeGuard>
#include <QSet>
#include "../backend/AttachmentMime.h"
#include <QJsonDocument>
#include <QImage>
#include <QUrl>
#include <QMimeDatabase>
#include <QTcpServer>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QElapsedTimer>
#include <QTcpSocket>
#include <QCryptographicHash>
#include <QTemporaryDir>
#include <QtTest>
#include <memory>
class BackendTests : public QObject {
  Q_OBJECT
  QTemporaryDir dir;
  std::unique_ptr<ForumBackend> backend;
  QJsonObject call(QJsonObject c) {
    return QJsonDocument::fromJson(
               backend->dispatch(QString::fromUtf8(QJsonDocument(c).toJson()))
                   .toUtf8())
        .object();
  }
  QJsonObject post(QString body = "A useful question", QString thread = "") {
    return call({{"op", "post"},
                 {"title", "Test discussion"},
                 {"body", body},
                 {"board", "general"},
                 {"thread", thread}});
  }
private slots:
  void init() {
    qputenv(
        "LOGOS_FORUM_DATA_DIR",
        (dir.path() + "/" + QUuid::createUuid().toString(QUuid::WithoutBraces))
            .toUtf8());
    backend = std::make_unique<ForumBackend>();
    QVERIFY(backend->lastError().isEmpty());
  }
  void cleanup() { backend.reset(); }
  void migratesLegacyProfileWithWalAndAttachments() {
    backend.reset();
    QTemporaryDir profile;
    const auto previousUserDir = qgetenv("LOGOS_USER_DIR");
    const auto previousDataDir = qgetenv("LOGOS_FORUM_DATA_DIR");
    const auto restore = qScopeGuard([&] {
      backend.reset();
      qputenv("LOGOS_USER_DIR", previousUserDir);
      qputenv("LOGOS_FORUM_DATA_DIR", previousDataDir);
    });
    const auto oldRoot = profile.path() + "/module_data/logos_forum";
    const auto newRoot = profile.path() + "/module_data/agora_forum";
    qputenv("LOGOS_FORUM_DATA_DIR", oldRoot.toUtf8());
    backend = std::make_unique<ForumBackend>();
    QVERIFY(backend->lastError().isEmpty());
    const auto identity = call({{"op", "identity"}, {"alias", "migration fixture"}})["id"].toString();
    const auto root = post("Keep this signed envelope")["id"].toString();
    const QJsonValue wire = call({{"op", "wire"}, {"id", root}}).value("wire");
    QVERIFY(call({{"op", "next"}})["ok"].toBool());
    QVERIFY(call({{"op", "bookmark"}, {"id", root}})["ok"].toBool());
    QVERIFY(call({{"op", "settings"}, {"theme", "light"}, {"autoConnect", false}})["ok"].toBool());
    QImage image(12, 12, QImage::Format_RGB32); image.fill(Qt::blue);
    const auto input = profile.path() + "/fixture.png";
    QVERIFY(image.save(input));
    const auto imported = call({{"op", "attachmentImport"}, {"file", QUrl::fromLocalFile(input).toString()}});
    QVERIFY(imported["ok"].toBool());
    const auto aid = imported["attachment"].toObject()["id"].toString();
    QVERIFY(call({{"op", "avatar"}, {"file", QUrl::fromLocalFile(input).toString()}})["ok"].toBool());
    const QJsonValue portrait = call({{"op", "snapshot"}}).value("avatar");
    QVERIFY(!portrait.isNull());
    // A different app's file must stay untouched, even in the shared old folder.
    QFile other(oldRoot + "/forum.db");
    QVERIFY(other.open(QIODevice::WriteOnly)); other.write("other forum's database"); other.close();
    AgoraData::Database original(oldRoot + "/forum.sqlite"); original.open();
    original.run("PRAGMA wal_autocheckpoint=0");
    original.run("INSERT INTO drafts VALUES ('wal-only','Unfinished draft in WAL')");
    auto keyQuery = original.run("SELECT secret FROM identities WHERE id=?", {identity});
    QVERIFY(keyQuery.next()); const auto secret = keyQuery.value(0).toByteArray(); keyQuery.finish();
    auto fileQuery = original.run("SELECT path FROM attachments WHERE id=?", {aid});
    QVERIFY(fileQuery.next()); const auto oldPath = fileQuery.value(0).toString(); fileQuery.finish();
    backend.reset(); // Keep another connection open so committed WAL pages remain.
    QVERIFY(QFileInfo(oldRoot + "/forum.sqlite-wal").size() > 0);
    qputenv("LOGOS_USER_DIR", profile.path().toUtf8());
    qunsetenv("LOGOS_FORUM_DATA_DIR");
    backend = std::make_unique<ForumBackend>();
    QVERIFY2(backend->lastError().isEmpty(), qPrintable(backend->lastError()));
    const auto snapshot = call({{"op", "snapshot"}});
    QCOMPARE(snapshot["active"].toString(), identity);
    QCOMPARE(snapshot["identities"].toArray().size(), 2);
    QCOMPARE(snapshot["drafts"].toObject()["wal-only"].toString(), QString("Unfinished draft in WAL"));
    QCOMPARE(snapshot["saved"].toArray(), QJsonArray{root});
    QCOMPARE(snapshot["theme"].toString(), QString("light"));
    QCOMPARE(snapshot["avatar"], portrait);
    QVERIFY(!snapshot["autoConnect"].toBool());
    QCOMPARE(call({{"op", "wire"}, {"id", root}})["wire"], wire);
    QCOMPARE(call({{"op", "postInfo"}, {"id", root}})["post"].toObject()["status"].toString(), QString("queued"));
    {
      AgoraData::Database migrated(newRoot + "/forum.sqlite"); migrated.open();
      auto key = migrated.run("SELECT secret FROM identities WHERE id=?", {identity});
      QVERIFY(key.next()); QCOMPARE(key.value(0).toByteArray(), secret);
      auto path = migrated.run("SELECT path FROM attachments WHERE id=?", {aid});
      QVERIFY(path.next()); QVERIFY(path.value(0).toString().startsWith(newRoot + "/attachments/"));
      QVERIFY(QFileInfo::exists(path.value(0).toString()));
#ifndef Q_OS_WIN
      QCOMPARE(QFileInfo(newRoot).permissions() & (QFile::ReadGroup | QFile::WriteGroup | QFile::ExeGroup | QFile::ReadOther | QFile::WriteOther | QFile::ExeOther), QFile::Permissions());
      QCOMPARE(QFileInfo(newRoot + "/forum.sqlite").permissions() & (QFile::ReadGroup | QFile::WriteGroup | QFile::ReadOther | QFile::WriteOther), QFile::Permissions());
#endif
    }
    const auto exported = profile.path() + "/exported.png";
    QVERIFY(call({{"op", "attachmentExport"}, {"id", aid}, {"file", QUrl::fromLocalFile(exported).toString()}})["ok"].toBool());
    QCOMPARE(QImage(exported), image);
    QVERIFY(QFileInfo::exists(oldPath));
    QVERIFY(other.open(QIODevice::ReadOnly)); QCOMPARE(other.readAll(), QByteArray("other forum's database")); other.close();
    QVERIFY(!QFileInfo::exists(newRoot + "/forum.db"));
    // A restart uses the new database, never replacing it from the legacy one.
    QVERIFY(call({{"op", "settings"}, {"theme", "dark"}})["ok"].toBool());
    backend.reset(); backend = std::make_unique<ForumBackend>();
    QVERIFY(backend->lastError().isEmpty());
    QCOMPARE(call({{"op", "snapshot"}})["theme"].toString(), QString("dark"));
    auto untouched = original.run("SELECT value FROM settings WHERE key='theme'");
    QVERIFY(untouched.next()); QCOMPARE(untouched.value(0).toString(), QString("light"));
    auto oldStatus = original.run("SELECT status FROM posts WHERE id=?", {root});
    QVERIFY(oldStatus.next()); QCOMPARE(oldStatus.value(0).toString(), QString("sending"));
  }
  void migrationFailureDoesNotCreateFreshIdentity() {
    backend.reset();
    QTemporaryDir profile;
    const auto previousUserDir = qgetenv("LOGOS_USER_DIR");
    const auto previousDataDir = qgetenv("LOGOS_FORUM_DATA_DIR");
    const auto restore = qScopeGuard([&] {
      backend.reset();
      qputenv("LOGOS_USER_DIR", previousUserDir);
      qputenv("LOGOS_FORUM_DATA_DIR", previousDataDir);
    });
    const auto oldRoot = profile.path() + "/module_data/logos_forum";
    const auto newRoot = profile.path() + "/module_data/agora_forum";
    qputenv("LOGOS_FORUM_DATA_DIR", oldRoot.toUtf8());
    backend = std::make_unique<ForumBackend>();
    const QJsonValue active = call({{"op", "snapshot"}}).value("active");
    QImage image(2, 2, QImage::Format_RGB32); image.fill(Qt::red);
    const auto input = profile.path() + "/fixture.png"; QVERIFY(image.save(input));
    QVERIFY(call({{"op", "attachmentImport"}, {"file", QUrl::fromLocalFile(input).toString()}})["ok"].toBool());
    backend.reset();
    QVERIFY(QDir().rename(oldRoot + "/attachments", oldRoot + "/saved-attachments"));
    qputenv("LOGOS_USER_DIR", profile.path().toUtf8()); qunsetenv("LOGOS_FORUM_DATA_DIR");
    backend = std::make_unique<ForumBackend>();
    QVERIFY(backend->lastError().contains("attachment is missing"));
    QVERIFY(!call({{"op", "snapshot"}})["ok"].toBool());
    QVERIFY(!QFileInfo::exists(newRoot + "/forum.sqlite"));
    QVERIFY(QDir(profile.path() + "/module_data").entryList({".agora-migration-*"}, QDir::Dirs | QDir::Hidden | QDir::NoDotAndDotDot).isEmpty());
    // Restoring the missing file makes the next startup retry safely.
    backend.reset();
    QVERIFY(QDir().rename(oldRoot + "/saved-attachments", oldRoot + "/attachments"));
    backend = std::make_unique<ForumBackend>();
    QVERIFY2(backend->lastError().isEmpty(), qPrintable(backend->lastError()));
    QCOMPARE(call({{"op", "snapshot"}}).value("active"), active);
  }
  void freshProfileCoexistsWithOtherForum() {
    backend.reset();
    QTemporaryDir profile;
    const auto previousUserDir = qgetenv("LOGOS_USER_DIR");
    const auto previousDataDir = qgetenv("LOGOS_FORUM_DATA_DIR");
    const auto restore = qScopeGuard([&] {
      backend.reset(); qputenv("LOGOS_USER_DIR", previousUserDir); qputenv("LOGOS_FORUM_DATA_DIR", previousDataDir);
    });
    const auto oldRoot = profile.path() + "/module_data/logos_forum";
    QVERIFY(QDir().mkpath(oldRoot));
    QFile other(oldRoot + "/forum.db"); QVERIFY(other.open(QIODevice::WriteOnly)); other.write("other app"); other.close();
    qputenv("LOGOS_USER_DIR", profile.path().toUtf8()); qunsetenv("LOGOS_FORUM_DATA_DIR");
    backend = std::make_unique<ForumBackend>();
    QVERIFY(backend->lastError().isEmpty());
    QVERIFY(QFileInfo::exists(profile.path() + "/module_data/agora_forum/forum.sqlite"));
    QVERIFY(!QFileInfo::exists(oldRoot + "/forum.sqlite"));
    QVERIFY(other.open(QIODevice::ReadOnly)); QCOMPARE(other.readAll(), QByteArray("other app"));
  }
  void resolvesPostReferencesWithoutGuessing() {
    const auto root = post("Original post")["id"].toString();
    const auto reply = post("Referenced reply", root)["id"].toString();
    const auto found = call({{"op", "postReference"}, {"reference", reply.left(8).toUpper()}});
    QCOMPARE(found["state"].toString(), QString("found"));
    QCOMPARE(found["post"].toObject()["id"].toString(), reply);
    QCOMPARE(found["post"].toObject()["thread"].toString(), root);
    QVERIFY(found["threadAvailable"].toBool());
    QCOMPARE(call({{"op", "postReference"}, {"reference", QString(64, 'f')}})["state"].toString(), QString("missing"));
    QVERIFY(!call({{"op", "postReference"}, {"reference", "*"}})["ok"].toBool());
    QVERIFY(!call({{"op", "postReference"}, {"reference", "abc"}})["ok"].toBool());

    // Controlled prefix collision in the temporary test database only.
    const QString connection = "reference-fixture";
    {
      auto db = QSqlDatabase::addDatabase("QSQLITE", connection);
      db.setDatabaseName(qEnvironmentVariable("LOGOS_FORUM_DATA_DIR") + "/forum.sqlite");
      QVERIFY(db.open());
      QSqlQuery insert(db);
      QVERIFY(insert.prepare("INSERT INTO posts(id,thread,board,title,body,author,mode,pub,created,received,wire,status,search_text) VALUES(?,'','general','fixture','fixture','','anonymous','',1,1,'','local','fixture')"));
      for (const auto suffix : {'a', 'b'}) {
        insert.bindValue(0, QString("12345678") + QString(56, suffix));
        QVERIFY(insert.exec());
      }
      db.close();
    }
    QSqlDatabase::removeDatabase(connection);
    const auto ambiguous = call({{"op", "postReference"}, {"reference", "12345678"}});
    QCOMPARE(ambiguous["state"].toString(), QString("ambiguous"));
    QVERIFY(!ambiguous.contains("post"));
    QCOMPARE(call({{"op", "postReference"}, {"reference", QString("12345678") + QString(56, 'a')}})["state"].toString(), QString("found"));
  }
  void retryTargetsOneStoredEnvelope() {
    auto a = post("First")["id"].toString();
    auto b = post("Second")["id"].toString();
    const QJsonValue wire = call({{"op","wire"},{"id",a}})["wire"];
    for (const auto &id : {a,b})
      QVERIFY(call({{"op","delivery"},{"id",id},{"status","failed"},{"error","timeout"}})["ok"].toBool());
    QVERIFY(call({{"op","retry"},{"id",a}})["ok"].toBool());
    QCOMPARE(call({{"op","postInfo"},{"id",a}})["post"].toObject()["status"].toString(), QString("queued"));
    QCOMPARE(call({{"op","postInfo"},{"id",b}})["post"].toObject()["status"].toString(), QString("failed"));
    QCOMPARE(call({{"op","wire"},{"id",a}})["wire"], wire);
    QVERIFY(!call({{"op","retry"},{"id",""}})["ok"].toBool());
    call({{"op","delivery"},{"id",a},{"status","sent"}});
    call({{"op","retry"},{"id",a}});
    QCOMPARE(call({{"op","postInfo"},{"id",a}})["post"].toObject()["status"].toString(), QString("sent"));
  }
  void canonicalizesMp4ContentAcrossMimeDatabases() {
    QFile sample(QFINDTESTDATA("../../design/agora/demo-media/playback-test.mp4"));
    QVERIFY(sample.open(QIODevice::ReadOnly));
    QCOMPARE(attachmentMime(sample.read(65536)), QString("video/mp4"));
    QByteArray quicktime=QByteArray::fromHex("0000001466747970717420200000000071742020");
    QVERIFY(attachmentMime(quicktime)!=QString("video/mp4"));
    QVERIFY(attachmentMime(QByteArray("not a movie.mp4"))!=QString("video/mp4"));
  }
  void importsWebmContentAcrossPlatforms() {
    const auto path=QFINDTESTDATA("../../design/agora/demo-media/playback-test.webm");
    QFile sample(path);
    QVERIFY(sample.open(QIODevice::ReadOnly));
    const auto header=sample.peek(65536);
    const auto detected=QMimeDatabase().mimeTypeForData(header).name();
    QCOMPARE(attachmentMime(header), QString("video/webm"));
    auto otherDoctype=header;
    otherDoctype.replace("webm", "xxxx");
    QVERIFY(attachmentMime(otherDoctype)!=QString("video/webm"));
    QVERIFY(attachmentMime(QByteArray("not a movie.webm"))!=QString("video/webm"));
    QVERIFY(attachmentMime(QByteArray::fromHex("1a45dfa380")+"webm")!=QString("video/webm"));
    const auto imported=call({{"op","attachmentImport"},{"file",QUrl::fromLocalFile(path).toString()}});
    QVERIFY2(imported["ok"].toBool(), qPrintable(QString::fromUtf8(QJsonDocument(imported).toJson())+" detected="+detected));
    QCOMPARE(imported["attachment"].toObject()["mime"].toString(), QString("video/webm"));
  }
  void largeArchiveKeepsPagesBounded() {
    // Synthetic database fixture only: these rows are never sent over Delivery.
    const QString connection="archive-fixture";
    {
      auto db=QSqlDatabase::addDatabase("QSQLITE",connection);
      db.setDatabaseName(qEnvironmentVariable("LOGOS_FORUM_DATA_DIR")+"/forum.sqlite");
      QVERIFY(db.open()); QVERIFY(db.transaction());
      QSqlQuery insert(db);
      QVERIFY(insert.prepare("INSERT INTO posts(id,thread,board,title,body,author,mode,pub,created,received,wire,status,search_text) VALUES(?,'','general',?,'fixture','test','anonymous','',?,?,'','local',?)"));
      for(int i=0;i<12000;++i) {
        const auto title=i==0?QString("oldest archive needle"):QString("fixture %1").arg(i);
        insert.bindValue(0,QString::number(i+1,16).rightJustified(64,'0'));
        insert.bindValue(1,title); insert.bindValue(2,i); insert.bindValue(3,i); insert.bindValue(4,title);
        QVERIFY(insert.exec());
      }
      QVERIFY(db.commit()); db.close();
    }
    QSqlDatabase::removeDatabase(connection);
    QElapsedTimer timer; timer.start();
    auto page=call({{"op","snapshot"},{"view","feed"}});
    QVERIFY(page["ok"].toBool()); QCOMPARE(page["posts"].toArray().size(),30);
    QVERIFY(page["hasMore"].toBool());
    auto result=call({{"op","snapshot"},{"view","feed"},{"search","oldest archive needle"}});
    QCOMPARE(result["posts"].toArray().size(),1);
    QCOMPARE(call({{"op","snapshot"}})["posts"].toArray().size(),200);
    qInfo()<<"12,000-root archive: feed, full-archive search and bounded diagnostic snapshot in"<<timer.elapsed()<<"ms";
  }
  void paginatesThreadsAndSearchesUnloadedReplies() {
    const auto root=post("Opening")["id"].toString();
    QSet<QString> expected;
    for(int i=0;i<115;++i) {
      auto reply=post(i==0 ? "Needle CAFÉ 100%" : QString("Reply %1").arg(i),root);
      QVERIFY(reply["ok"].toBool()); expected.insert(reply["id"].toString());
    }
    QVERIFY(post("Second root")["ok"].toBool());
    QVERIFY(post("Third root")["ok"].toBool());
    QJsonObject request{{"op","snapshot"},{"view","thread"},{"thread",root},{"limit",50}};
    QSet<QString> seen; int pages=0;
    do {
      auto page=call(request); QVERIFY2(page["ok"].toBool(),qPrintable(QJsonDocument(page).toJson()));
      auto records=page["posts"].toArray(); QVERIFY(records.size()<=51);
      QCOMPARE(records.first().toObject()["replyCount"].toInt(),115);
      for(int i=1;i<records.size();++i) {
        auto id=records[i].toObject()["id"].toString(); QVERIFY(!seen.contains(id)); seen.insert(id);
      }
      ++pages; request["cursor"]=page["nextCursor"];
      if(!page["hasMore"].toBool()) break;
      QVERIFY(pages<4);
    } while(true);
    QCOMPARE(pages,3); QCOMPARE(seen,expected);
    auto search=call({{"op","snapshot"},{"view","feed"},{"search","café 100%"}});
    QCOMPARE(search["posts"].toArray().size(),2);
    QCOMPARE(search["posts"].toArray().first().toObject()["id"].toString(),root);
    QJsonObject feed{{"op","snapshot"},{"view","feed"},{"limit",1},{"sort","replies"}};
    auto first=call(feed); QCOMPARE(first["posts"].toArray().first().toObject()["replyCount"].toInt(),115);
    feed["cursor"]=first["nextCursor"]; feed["search"]="different";
    QVERIFY(!call(feed)["ok"].toBool()); feed.remove("search");
    QSet<QString> roots{root};
    for(int i=0;i<2;++i) {
      auto page=call(feed); QVERIFY(page["ok"].toBool());
      auto id=page["posts"].toArray().first().toObject()["id"].toString();
      QVERIFY(!roots.contains(id)); roots.insert(id); feed["cursor"]=page["nextCursor"];
      QCOMPARE(page["hasMore"].toBool(),i==0);
    }
    auto newest=post("Newly submitted reply",root)["id"].toString();
    auto anchored=call({{"op","replyPage"},{"id",newest}});
    QVERIFY(anchored["ok"].toBool());
    request["cursor"]=anchored["pageCursor"];
    auto selected=call(request); QVERIFY(selected["ok"].toBool());
    bool found=false;
    for(auto record:selected["posts"].toArray()) if(record.toObject()["id"].toString()==newest) found=true;
    QVERIFY(found);
  }
  void avatarPersistsAndStaysWithIdentity() {
    const auto firstId=call({{"op","snapshot"}})["active"].toString();
    const auto original=post("Written before uploading a photo")["id"].toString();
    const QJsonValue wire=call({{"op","wire"},{"id",original}})["wire"];
    const auto file=dir.path()+"/avatar.png";
    QImage picture(180,100,QImage::Format_RGB32); picture.fill(Qt::red); QVERIFY(picture.save(file));
    QVERIFY(call({{"op","avatar"},{"file",QUrl::fromLocalFile(file).toString()}})["ok"].toBool());
    backend.reset(); backend=std::make_unique<ForumBackend>();
    auto avatar=call({{"op","snapshot"}})["avatar"].toObject();
    QCOMPARE(avatar["size"].toInt(),64); QCOMPARE(avatar["pixels"].toArray().size(),4096);
    QCOMPARE(avatar["pixels"].toArray()[0].toDouble(),static_cast<double>(qRgb(255,0,0)));
    const auto secondId=call({{"op","identity"},{"alias","wanderer"}})["id"].toString();
    post("Same alias, different signing identity");
    auto snapshot=call({{"op","snapshot"}});
    QVERIFY(snapshot["avatar"].isNull());
    QCOMPARE(snapshot["avatars"].toObject()[firstId].toObject(), avatar);
    QVERIFY(snapshot["avatars"].toObject()[secondId].isNull());
    QCOMPARE(snapshot["avatars"].toObject().size(), 2);
    QCOMPARE(call({{"op","wire"},{"id",original}})["wire"], wire);
    call({{"op","settings"},{"active",firstId}});
    QVERIFY(call({{"op","snapshot"}})["avatar"].isObject());
    QVERIFY(!call({{"op","avatar"},{"file","https://example.com/photo.png"}})["ok"].toBool());
    QVERIFY(call({{"op","avatar"},{"remove",true}})["ok"].toBool());
    QVERIFY(call({{"op","snapshot"}})["avatar"].isNull());
    QVERIFY(call({{"op","snapshot"}})["avatars"].toObject()[firstId].isNull());
    QImage large(4097,1,QImage::Format_RGB32);large.fill(Qt::blue);QVERIFY(large.save(file));
    QVERIFY(!call({{"op","avatar"},{"file",QUrl::fromLocalFile(file).toString()}})["ok"].toBool());
  }
  void localAttachmentsPersistAndNeverQueue() {
    const auto file = dir.path()+"/attachment.png";
    QImage picture(320,200,QImage::Format_RGB32); picture.fill(Qt::green); QVERIFY(picture.save(file));
    auto result=call({{"op","attachmentImport"},{"file",QUrl::fromLocalFile(file).toString()}});
    QVERIFY(result["ok"].toBool());
    auto aid=result["attachment"].toObject()["id"].toString();
    QVERIFY(!aid.isEmpty());
    QVERIFY(!call({{"op","attachmentImport"},{"file","https://example.com/image.png"}})["ok"].toBool());
    auto invalid=call({{"op","post"},{"title","Files"},{"board","general"},{"body","Test"},{"attachments",QJsonArray{aid,"missing"}}});
    QVERIFY(!invalid["ok"].toBool()); // first file association rolls back too
    auto thread=call({{"op","post"},{"title","Files"},{"board","general"},{"body","Test"},{"attachments",QJsonArray{aid}}});
    QVERIFY(thread["ok"].toBool());
    QVERIFY(!call({{"op","post"},{"title","Reuse"},{"board","general"},{"body","Test"},{"attachments",QJsonArray{aid}}})["ok"].toBool());
    QVERIFY(post("Reply stays local",thread["id"].toString())["ok"].toBool());
    QVERIFY(QFile::remove(file));
    backend.reset(); backend=std::make_unique<ForumBackend>();
    auto posts=call({{"op","snapshot"}})["posts"].toArray();
    QCOMPARE(posts.size(),2);
    for (const auto &p : posts) QCOMPARE(p.toObject()["status"].toString(),QString("local"));
    QVERIFY(call({{"op","next"}})["item"].isNull());
    QVERIFY(!call({{"op","wire"},{"id",thread["id"]}})["ok"].toBool());
    QVERIFY(!call({{"op","delivery"},{"id",thread["id"]},{"status","queued"}})["ok"].toBool());
    auto image=call({{"op","attachmentPreview"},{"id",aid}})["image"].toObject();
    QCOMPARE(image["width"].toInt(),240); QCOMPARE(image["height"].toInt(),150);
    const auto copy=dir.path()+"/download.png";
    QVERIFY(call({{"op","attachmentExport"},{"id",aid},{"file",QUrl::fromLocalFile(copy).toString()}})["ok"].toBool());
    QCOMPARE(QImage(copy),picture);
    QVERIFY(!call({{"op","attachmentExport"},{"id",aid},{"file",QUrl::fromLocalFile(copy).toString()}})["ok"].toBool());
  }
  void videoPlaybackIsScopedToStoredAttachments() {
    auto imported=call({{"op","attachmentImport"},{"file",QUrl::fromLocalFile(QFINDTESTDATA("../../design/agora/demo-media/playback-test.mp4")).toString()}});
    if (!imported["ok"].toBool()) {
      QFile input(QFINDTESTDATA("../../design/agora/demo-media/playback-test.mp4"));
      input.open(QIODevice::ReadOnly);
      qWarning() << "Video import failed" << imported << "detected MIME"
                 << QMimeDatabase().mimeTypeForData(input.peek(65536)).name();
    }
    QVERIFY(imported["ok"].toBool());
    const auto aid=imported["attachment"].toObject()["id"].toString();
    QVERIFY(!call({{"op","attachmentVideo"},{"action","play"},{"id","missing"}})["ok"].toBool());
    QVERIFY(!call({{"op","attachmentVideo"},{"action","unknown"}})["ok"].toBool());
    QVERIFY(call({{"op","attachmentVideo"},{"action","play"},{"id",aid}})["ok"].toBool());
    auto state=[&]() {return call({{"op","attachmentVideo"},{"action","state"},{"id",aid}})["video"].toObject();};
    QTRY_VERIFY_WITH_TIMEOUT(!state()["frame"].toString().isEmpty(),10000);
    QVERIFY(state()["duration"].toInt()>0);
    QVERIFY(call({{"op","attachmentVideo"},{"action","pause"},{"id",aid}})["ok"].toBool());
    QVERIFY(!state()["playing"].toBool());
    call({{"op","attachmentVideo"},{"action","seek"},{"id",aid},{"position",3000}});
    QTRY_VERIFY(qAbs(state()["position"].toInt()-3000)<300);
    call({{"op","attachmentVideo"},{"action","volume"},{"id",aid},{"volume",0.25}});
    QCOMPARE(state()["volume"].toDouble(),0.25);
    call({{"op","attachmentVideo"},{"action","mute"},{"id",aid},{"muted",true}});
    QVERIFY(state()["muted"].toBool());
    call({{"op","attachmentVideo"},{"action","stop"},{"id","stale-player"}});
    QCOMPARE(state()["id"].toString(),aid);
    call({{"op","attachmentVideo"},{"action","stop"},{"id",aid}});
    QVERIFY(state()["id"].toString().isEmpty());
    QVERIFY(state()["frame"].toString().isEmpty());
  }
  void sharedAttachmentsRoundTripAndVerifyContent() {
    QTcpServer server;
    QVERIFY(server.listen(QHostAddress::LocalHost,0));
    const auto endpoint="http://127.0.0.1:"+QString::number(server.serverPort())+"/api/storage/v1";
    const auto source=dir.path()+"/shared.png";
    QImage image(16,16,QImage::Format_RGB32); image.fill(Qt::green); QVERIFY(image.save(source));
    QFile input(source); QVERIFY(input.open(QIODevice::ReadOnly)); const auto original=input.readAll();
    QByteArray stored, downloaded=original;
    bool announcementFails=true;
    int announcements=0;
    const auto cid=QByteArray("bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabcd234567abcdef");
    connect(&server,&QTcpServer::newConnection,&server,[&]{
      auto socket=server.nextPendingConnection();
      auto request=std::make_shared<QByteArray>();
      connect(socket,&QTcpSocket::disconnected,socket,&QObject::deleteLater);
      connect(socket,&QTcpSocket::readyRead,socket,[&,socket,request]{
        *request+=socket->readAll();
        const auto split=request->indexOf("\r\n\r\n"); if(split<0) return;
        qint64 length=0;
        for(const auto &line:request->left(split).split('\n'))
          if(line.toLower().startsWith("content-length:")) length=line.mid(15).trimmed().toLongLong();
        if(request->size()<split+4+length) return;
        const bool announce=request->startsWith("POST /api/storage/v1/data/"+cid+"/advertise?advertise=true ");
        const bool upload=request->startsWith("POST /api/storage/v1/data ");
        if(announce) ++announcements;
        if(upload) QVERIFY(request->left(split).toLower().contains("content-type: image/png"));
        if(upload) stored=request->mid(split+4,length);
        const auto body=announce?QByteArray():upload?cid:downloaded;
        const auto status=announce && announcementFails?QByteArray("503 Unavailable"):QByteArray("200 OK");
        socket->write("HTTP/1.1 "+status+"\r\nContent-Length: "+QByteArray::number(body.size())+"\r\nConnection: close\r\n\r\n"+body);
        socket->disconnectFromHost();
      });
    });
    QVERIFY(!call({{"op","settings"},{"storageEndpoint","http://example.com:8080/api/storage/v1"}})["ok"].toBool());
    QVERIFY(call({{"op","settings"},{"storageEndpoint",endpoint}})["ok"].toBool());
    auto aid=call({{"op","attachmentImport"},{"file",QUrl::fromLocalFile(source).toString()}})["attachment"].toObject()["id"].toString();
    QVERIFY(!aid.isEmpty());
    QVERIFY(call({{"op","attachmentUpload"},{"id",aid}})["ok"].toBool());
    auto transfer=[&]{return call({{"op","attachmentTransfer"}})["transfer"].toObject();};
    QTRY_COMPARE_WITH_TIMEOUT(transfer()["status"].toString(),QString("failed"),5000);
    QVERIFY(transfer()["error"].toString().contains("announce"));
    announcementFails=false;
    QVERIFY(call({{"op","attachmentUpload"},{"id",aid}})["ok"].toBool());
    QTRY_COMPARE_WITH_TIMEOUT(transfer()["status"].toString(),QString("complete"),5000);
    QCOMPARE(announcements,2);
    QCOMPARE(stored,original);
    auto created=call({{"op","post"},{"title","Shared image"},{"body","Signed attachment"},{"board","general"},{"attachments",QJsonArray{aid}}});
    QVERIFY2(created["ok"].toBool(),qPrintable(created["error"].toString()));
    QCOMPARE(created["status"].toString(),QString("queued"));
    const auto wire=call({{"op","wire"},{"id",created["id"]}})["wire"].toString();
    auto envelope=QJsonDocument::fromJson(wire.toUtf8()).object();
    QCOMPARE(envelope["payload"].toObject()["v"].toInt(),2);
    backend.reset(); qputenv("LOGOS_FORUM_DATA_DIR",(dir.path()+"/remote-media").toUtf8()); backend=std::make_unique<ForumBackend>();
    auto received=call({{"op","receive"},{"wire",wire}});
    QVERIFY2(received["ok"].toBool(),qPrintable(received["error"].toString()));
    auto files=call({{"op","snapshot"}})["posts"].toArray()[0].toObject()["attachments"].toArray();
    QCOMPARE(files.size(),1); QVERIFY(!files[0].toObject()["available"].toBool());
    const auto remoteId=files[0].toObject()["id"].toString();
    QVERIFY(call({{"op","settings"},{"storageEndpoint",endpoint}})["ok"].toBool());
    downloaded=QByteArray(original.size(),'x');
    QVERIFY(call({{"op","attachmentFetch"},{"id",remoteId}})["ok"].toBool());
    QTRY_COMPARE_WITH_TIMEOUT(transfer()["status"].toString(),QString("failed"),5000);
    QVERIFY(transfer()["error"].toString().contains("checksum"));
    QVERIFY(!call({{"op","attachmentExport"},{"id",remoteId},{"file",QUrl::fromLocalFile(dir.path()+"/bad.png").toString()}})["ok"].toBool());
    downloaded=original;
    QVERIFY(call({{"op","attachmentFetch"},{"id",remoteId}})["ok"].toBool());
    QTRY_COMPARE_WITH_TIMEOUT(transfer()["status"].toString(),QString("complete"),5000);
    const auto destination=dir.path()+"/downloaded.png";
    QVERIFY(call({{"op","attachmentExport"},{"id",remoteId},{"file",QUrl::fromLocalFile(destination).toString()}})["ok"].toBool());
    QFile exported(destination); QVERIFY(exported.open(QIODevice::ReadOnly)); QCOMPARE(exported.readAll(),original);
    QVERIFY(call({{"op","receive"},{"wire",wire}})["duplicate"].toBool());
    backend.reset(); backend=std::make_unique<ForumBackend>();
    files=call({{"op","snapshot"}})["posts"].toArray()[0].toObject()["attachments"].toArray();
    QVERIFY(files[0].toObject()["available"].toBool());
    auto changed=envelope["payload"].toObject(); auto manifest=changed["attachments"].toArray();
    auto altered=manifest[0].toObject(); altered["cid"]="../outside"; manifest[0]=altered; changed["attachments"]=manifest; envelope["payload"]=changed;
    QVERIFY(!call({{"op","receive"},{"wire",QString::fromUtf8(QJsonDocument(envelope).toJson(QJsonDocument::Compact))}})["ok"].toBool());
    // Rehash anonymous envelopes so validation must reject the metadata itself,
    // rather than failing earlier on the altered signature/content ID.
    changed["mode"]="anonymous"; changed["author"]=""; changed["pub"]="";
    const QList<QPair<QString,QJsonValue>> invalid{
      {"name","../outside.png"},{"bytes",64*1024*1024+1},{"bytes",1.5},
      {"mime","text/html"},{"sha256","wrong"},{"cid","http://example.com/file"}};
    for(const auto &entry:invalid) {
      auto bad=files[0].toObject();
      bad[entry.first]=entry.second;
      changed["attachments"]=QJsonArray{bad};
      const auto payload=QJsonDocument(changed).toJson(QJsonDocument::Compact);
      QJsonObject message{{"id",QString::fromLatin1(QCryptographicHash::hash(payload,QCryptographicHash::Sha256).toHex())},
                          {"payload",changed},{"signature",""}};
      QVERIFY(!call({{"op","receive"},{"wire",QString::fromUtf8(QJsonDocument(message).toJson(QJsonDocument::Compact))}})["ok"].toBool());
    }
    QCOMPARE(call({{"op","snapshot"}})["posts"].toArray().size(),1);
  }
  void themeDefaultsDarkAndPersists() {
    QCOMPARE(call({{"op","snapshot"}})["theme"].toString(), QString("dark"));
    QVERIFY(call({{"op","settings"},{"theme","light"}})["ok"].toBool());
    backend.reset(); backend = std::make_unique<ForumBackend>();
    QCOMPARE(call({{"op","snapshot"}})["theme"].toString(), QString("light"));
    QVERIFY(!call({{"op","settings"},{"theme","invalid"}})["ok"].toBool());
  }
  void autoConnectDefaultsOnAndRespectsPersistedOptOut() {
    QVERIFY(call({{"op","snapshot"}})["autoConnect"].toBool());
    QVERIFY(call({{"op","settings"},{"autoConnect",true}})["ok"].toBool());
    backend.reset(); backend = std::make_unique<ForumBackend>();
    QVERIFY(call({{"op","snapshot"}})["autoConnect"].toBool());
    QVERIFY(!call({{"op","settings"},{"autoConnect","true"}})["ok"].toBool());
    QVERIFY(call({{"op","settings"},{"autoConnect",false}})["ok"].toBool());
    backend.reset(); backend = std::make_unique<ForumBackend>();
    QVERIFY(!call({{"op","snapshot"}})["autoConnect"].toBool());
  }
  void validatesHistoryAndPersistsCursor() {
    auto id = post()["id"].toString();
    auto wire = call({{"op", "wire"}, {"id", id}})["wire"].toString();
    QJsonObject message{
        {"contentTopic", "/logos-forum/1/commons/json"},
        {"payload", QString::fromLatin1(wire.toUtf8().toBase64())}};
    QJsonObject page{
        {"statusCode", 200},
        {"paginationCursor", "cursor-1"},
        {"messages",
         QJsonArray{QJsonObject{{"message", message}},
                    QJsonObject{
                        {"message", QJsonObject{{"contentTopic", "other"}}}}}}};
    auto result =
        call({{"op", "historyPage"}, {"peer", "/test-peer"}, {"page", page}});
    QVERIFY(result["ok"].toBool());
    QCOMPARE(result["duplicates"].toInt(), 1);
    QCOMPARE(result["rejected"].toInt(), 1);
    backend.reset();
    backend = std::make_unique<ForumBackend>();
    QCOMPARE(call({{"op", "snapshot"}})["historyCursor"].toString(),
             QString("cursor-1"));
    page["statusCode"] = 503;
    QVERIFY(!call({{"op", "historyPage"}, {"page", page}})["ok"].toBool());
  }
  void storesPostAndReply() {
    auto t = post();
    QVERIFY(t["ok"].toBool());
    auto r = post("A response", t["id"].toString());
    QVERIFY(r["ok"].toBool());
    auto s = call({{"op", "snapshot"}});
    QCOMPARE(s["posts"].toArray().size(), 2);
    QCOMPARE(s["posts"].toArray()[0].toObject()["status"].toString(), "queued");
  }
  void persistsAcrossRestart() {
    post();
    call({{"op", "draft"}, {"id", "new"}, {"body", "unfinished"}});
    backend.reset();
    backend = std::make_unique<ForumBackend>();
    auto s = call({{"op", "snapshot"}});
    QCOMPARE(s["posts"].toArray().size(), 1);
    QCOMPARE(s["drafts"].toObject()["new"].toString(), "unfinished");
  }
  void anonymousOmitsIdentity() {
    call({{"op", "settings"}, {"mode", "anonymous"}});
    auto t = post();
    QVERIFY2(t["ok"].toBool(), qPrintable(t["error"].toString()));
    auto w = call({{"op", "wire"}, {"id", t["id"]}});
    auto envelope =
        QJsonDocument::fromJson(w["wire"].toString().toUtf8()).object();
    auto p = envelope["payload"].toObject();
    QVERIFY(p["author"].toString().isEmpty());
    QVERIFY(p["pub"].toString().isEmpty());
    QVERIFY(envelope["signature"].toString().isEmpty());
  }
  void freshProfilesUsePublicIdsAndRejectSpoofingAliases() {
    const auto snapshot = call({{"op", "snapshot"}});
    QCOMPARE(snapshot["mode"].toString(), QString("uid"));
    QVERIFY(!call({{"op", "identity"}, {"alias", "Anonymous"}})["ok"].toBool());
    QVERIFY(!call({{"op", "identity"}, {"alias", "c17dc191"}})["ok"].toBool());
    QVERIFY(call({{"op", "identity"}, {"alias", "forest-reader"}})["ok"].toBool());
  }
  void receivedOrderIgnoresSenderTimestamps() {
    const auto first = post("First authored");
    QTest::qWait(2);
    const auto second = post("Second authored");
    const auto firstWire = call({{"op", "wire"}, {"id", first["id"]}})["wire"].toString();
    const auto secondWire = call({{"op", "wire"}, {"id", second["id"]}})["wire"].toString();
    backend.reset();
    qputenv("LOGOS_FORUM_DATA_DIR", (dir.path() + "/receive-order").toUtf8());
    backend = std::make_unique<ForumBackend>();
    const auto secondReceived = call({{"op", "receive"}, {"wire", secondWire}});
    QVERIFY2(secondReceived["ok"].toBool(), qPrintable(secondReceived["error"].toString()));
    QTest::qWait(2);
    const auto firstReceived = call({{"op", "receive"}, {"wire", firstWire}});
    QVERIFY2(firstReceived["ok"].toBool(), qPrintable(firstReceived["error"].toString()));
    const auto posts = call({{"op", "snapshot"}, {"view", "feed"},
                             {"sort", "newest"}})["posts"].toArray();
    QCOMPARE(posts[0].toObject()["body"].toString(), QString("First authored"));
    QCOMPARE(posts[1].toObject()["body"].toString(), QString("Second authored"));
  }
  void prunesOnlyOldUnbookmarkedRemoteHistory() {
    QList<QJsonValue> wires;
    for (int i = 0; i < 101; ++i) {
      const auto created = post("Remote archive " + QString::number(i));
      wires.append(call({{"op", "wire"}, {"id", created["id"]}})["wire"]);
    }
    backend.reset();
    const auto oldLimit = qgetenv("AGORA_REMOTE_ARCHIVE_LIMIT");
    const auto restore = qScopeGuard([&] {
      if (oldLimit.isNull()) qunsetenv("AGORA_REMOTE_ARCHIVE_LIMIT");
      else qputenv("AGORA_REMOTE_ARCHIVE_LIMIT", oldLimit);
    });
    qputenv("AGORA_REMOTE_ARCHIVE_LIMIT", "100");
    qputenv("LOGOS_FORUM_DATA_DIR", (dir.path() + "/bounded-archive").toUtf8());
    backend = std::make_unique<ForumBackend>();
    for (const auto &wire : wires)
      QVERIFY(call({{"op", "receive"}, {"wire", wire}})["ok"].toBool());
    const auto posts = call({{"op", "snapshot"}})["posts"].toArray();
    QCOMPARE(posts.size(), 100);
    QSet<QString> retained;
    for (const auto &value : posts)
      retained.insert(value.toObject()["body"].toString());
    QCOMPARE(retained.size(), 100);
  }
  void rejectsTamperedSignature() {
    auto t = post();
    auto w = call({{"op", "wire"}, {"id", t["id"]}});
    auto envelope =
        QJsonDocument::fromJson(w["wire"].toString().toUtf8()).object();
    envelope["signature"] = "not-a-signature";
    auto r =
        call({{"op", "receive"},
              {"wire", QString::fromUtf8(QJsonDocument(envelope).toJson())}});
    QVERIFY(!r["ok"].toBool());
    QVERIFY(r["error"].toString().contains("signature"));
  }
  void rejectsAlteredBody() {
    auto t = post();
    auto w = call({{"op", "wire"}, {"id", t["id"]}});
    auto envelope =
        QJsonDocument::fromJson(w["wire"].toString().toUtf8()).object();
    auto p = envelope["payload"].toObject();
    p["body"] = "forged";
    envelope["payload"] = p;
    auto r =
        call({{"op", "receive"},
              {"wire", QString::fromUtf8(QJsonDocument(envelope).toJson())}});
    QVERIFY(!r["ok"].toBool());
  }
  void deduplicatesValidEnvelope() {
    auto t = post();
    auto w = call({{"op", "wire"}, {"id", t["id"]}});
    auto r = call({{"op", "receive"}, {"wire", w["wire"]}});
    QVERIFY(r["ok"].toBool());
    QVERIFY(r["duplicate"].toBool());
    QCOMPARE(call({{"op", "snapshot"}})["posts"].toArray().size(), 1);
  }
  void identityRotationUsesNewKeys() {
    auto s = call({{"op", "snapshot"}});
    QString before = s["active"].toString();
    call({{"op", "settings"}, {"rotate", true}});
    post();
    auto after = call({{"op", "snapshot"}});
    QVERIFY(before != after["active"].toString());
    QCOMPARE(after["identities"].toArray().size(), 2);
  }
  void durableOutboxSurvivesCrash() {
    auto t = post();
    auto next = call({{"op", "next"}});
    QCOMPARE(next["item"].toObject()["id"].toString(), t["id"].toString());
    backend.reset();
    backend = std::make_unique<ForumBackend>();
    auto s = call({{"op", "snapshot"}});
    QCOMPARE(s["posts"].toArray()[0].toObject()["status"].toString(), "queued");
  }
  void liveBurstIsBoundedAndHistoryStillRecovers() {
    auto original=post();
    const auto wire=call({{"op","wire"},{"id",original["id"]}})["wire"].toString();
    backend.reset();
    qputenv("LOGOS_FORUM_DATA_DIR",(dir.path()+"/rate-limited-reader").toUtf8());
    backend=std::make_unique<ForumBackend>();
    auto live=[&](const QByteArray &bytes) {return QJsonDocument::fromJson(backend->receiveBytes(bytes).toUtf8()).object();};
    QVERIFY(!live(QByteArray(65537,'x'))["ok"].toBool());
    QJsonObject limited;
    int attempts=0;
    for(;attempts<1000;++attempts) {
      limited=live("not JSON");
      if(limited["rateLimited"].toBool()) break;
    }
    QVERIFY(attempts>=240 && attempts<500);
    QVERIFY(limited["retryAfterMs"].toInt()>0 && limited["retryAfterMs"].toInt()<=250);
    QCOMPARE(call({{"op","snapshot"}})["posts"].toArray().size(),0);
    QJsonObject message{{"contentTopic","/logos-forum/1/commons/json"},{"payload",QString::fromLatin1(wire.toUtf8().toBase64())}};
    QJsonObject page{{"statusCode",200},{"paginationCursor","after-burst"},{"messages",QJsonArray{QJsonObject{{"message",message}}}}};
    auto recovered=call({{"op","historyPage"},{"peer","/private-test-peer"},{"page",page}});
    QVERIFY(recovered["ok"].toBool());
    QCOMPARE(recovered["accepted"].toInt(),1);
    QCOMPARE(call({{"op","snapshot"}})["historyCursor"].toString(),QString("after-burst"));
    QTest::qWait(300);
    auto retry=live(wire.toUtf8());
    QVERIFY(retry["ok"].toBool());
    QVERIFY(retry["duplicate"].toBool());
  }
  void boundsAndRejectsInvalidInput() {
    QVERIFY(!post("   ")["ok"].toBool());
    QVERIFY(!post(QString(12001, 'x'))["ok"].toBool());
    QVERIFY(!post("reply", "nonexistent")["ok"].toBool());
    QVERIFY(!call({{"op", "receive"}, {"wire", "<script>"}})["ok"].toBool());
  }
  void twoDatabasesExchangeAndDeduplicate() {
    auto t = post();
    QString wire = call({{"op", "wire"}, {"id", t["id"]}})["wire"].toString();
    backend.reset();
    qputenv(
        "LOGOS_FORUM_DATA_DIR",
        (dir.path() + "/second-" + QUuid::createUuid().toString()).toUtf8());
    backend = std::make_unique<ForumBackend>();
    auto first = call({{"op", "receive"}, {"wire", wire}});
    QVERIFY(first["ok"].toBool());
    QVERIFY(!first["duplicate"].toBool());
    QVERIFY(call({{"op", "receive"}, {"wire", wire}})["duplicate"].toBool());
    QCOMPARE(call({{"op", "snapshot"}})["posts"]
                 .toArray()[0]
                 .toObject()["status"]
                 .toString(),
             "received");
  }
};
QTEST_GUILESS_MAIN(BackendTests)
#include "backend_tests.moc"
