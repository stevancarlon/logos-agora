#include "../backend/ForumBackend.h"
#include <QJsonDocument>
#include <QImage>
#include <QUrl>
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
  void avatarPersistsAndStaysWithIdentity() {
    const auto firstId=call({{"op","snapshot"}})["active"].toString();
    const auto file=dir.path()+"/avatar.png";
    QImage picture(180,100,QImage::Format_RGB32); picture.fill(Qt::red); QVERIFY(picture.save(file));
    QVERIFY(call({{"op","avatar"},{"file",QUrl::fromLocalFile(file).toString()}})["ok"].toBool());
    backend.reset(); backend=std::make_unique<ForumBackend>();
    auto avatar=call({{"op","snapshot"}})["avatar"].toObject();
    QCOMPARE(avatar["size"].toInt(),64); QCOMPARE(avatar["pixels"].toArray().size(),4096);
    QCOMPARE(avatar["pixels"].toArray()[0].toDouble(),static_cast<double>(qRgb(255,0,0)));
    call({{"op","identity"},{"alias","second"}});
    QVERIFY(call({{"op","snapshot"}})["avatar"].isNull());
    call({{"op","settings"},{"active",firstId}});
    QVERIFY(call({{"op","snapshot"}})["avatar"].isObject());
    QVERIFY(!call({{"op","avatar"},{"file","https://example.com/photo.png"}})["ok"].toBool());
    QVERIFY(call({{"op","avatar"},{"remove",true}})["ok"].toBool());
    QVERIFY(call({{"op","snapshot"}})["avatar"].isNull());
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
  void themeDefaultsDarkAndPersists() {
    QCOMPARE(call({{"op","snapshot"}})["theme"].toString(), QString("dark"));
    QVERIFY(call({{"op","settings"},{"theme","light"}})["ok"].toBool());
    backend.reset(); backend = std::make_unique<ForumBackend>();
    QCOMPARE(call({{"op","snapshot"}})["theme"].toString(), QString("light"));
    QVERIFY(!call({{"op","settings"},{"theme","invalid"}})["ok"].toBool());
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
