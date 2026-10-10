#include "ForumBackend.h"
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QImageReader>
#include <QBuffer>
#include <QPainter>
#include <QUrl>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QProcess>
#include <QTemporaryDir>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSignalBlocker>
#include <QSqlError>
#include <QSqlQuery>
#include <QStandardPaths>
#include <QUuid>
#include <memory>
#include <openssl/evp.h>
#include <stdexcept>

namespace {
using Key = std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)>;
using Context = std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)>;
QString json(const QJsonObject &o) {
  return QString::fromUtf8(QJsonDocument(o).toJson(QJsonDocument::Compact));
}
QJsonObject object(const QString &s) {
  QJsonParseError e;
  auto d = QJsonDocument::fromJson(s.toUtf8(), &e);
  if (e.error != QJsonParseError::NoError || !d.isObject())
    throw std::runtime_error("Invalid JSON object");
  return d.object();
}
void require(bool ok, const QString &message) {
  if (!ok)
    throw std::runtime_error(message.toStdString());
}
QSqlQuery query(QSqlDatabase db, const QString &sql,
                const QVariantList &args = {}) {
  QSqlQuery q(db);
  if (!q.prepare(sql))
    throw std::runtime_error(q.lastError().text().toStdString());
  for (const auto &a : args)
    q.addBindValue(a.metaType().id() == QMetaType::QString &&
                           a.toString().isNull()
                       ? QVariant(QStringLiteral(""))
                       : a);
  if (!q.exec())
    throw std::runtime_error(q.lastError().text().toStdString());
  return q;
}
QString id() { return QUuid::createUuid().toString(QUuid::WithoutBraces); }
qint64 now() { return QDateTime::currentMSecsSinceEpoch(); }
const QStringList boards = {"general", "privacy", "building", "circles",
                            "governance"};
QByteArray canonical(const QJsonObject &o) {
  return QJsonDocument(o).toJson(QJsonDocument::Compact);
}
QString hash(const QByteArray &b) {
  return QString::fromLatin1(
      QCryptographicHash::hash(b, QCryptographicHash::Sha256).toHex());
}
QPair<QByteArray, QByteArray> keys() {
  EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_ED25519, nullptr);
  require(ctx, "Cannot initialize signing");
  EVP_PKEY *raw = nullptr;
  int ok = EVP_PKEY_keygen_init(ctx) == 1 && EVP_PKEY_keygen(ctx, &raw) == 1;
  EVP_PKEY_CTX_free(ctx);
  require(ok, "Cannot generate signing key");
  Key key(raw, EVP_PKEY_free);
  QByteArray priv(32, 0), pub(32, 0);
  size_t a = 32, b = 32;
  require(
      EVP_PKEY_get_raw_private_key(
          key.get(), reinterpret_cast<unsigned char *>(priv.data()), &a) == 1 &&
          EVP_PKEY_get_raw_public_key(
              key.get(), reinterpret_cast<unsigned char *>(pub.data()), &b) ==
              1,
      "Cannot export signing key");
  return {priv, pub};
}
QString sign(const QByteArray &body, const QByteArray &secret) {
  Key key(EVP_PKEY_new_raw_private_key(
              EVP_PKEY_ED25519, nullptr,
              reinterpret_cast<const unsigned char *>(secret.data()),
              secret.size()),
          EVP_PKEY_free);
  Context ctx(EVP_MD_CTX_new(), EVP_MD_CTX_free);
  unsigned char signature[64];
  size_t size = 64;
  require(
      key && ctx &&
          EVP_DigestSignInit(ctx.get(), nullptr, nullptr, nullptr, key.get()) ==
              1 &&
          EVP_DigestSign(ctx.get(), signature, &size,
                         reinterpret_cast<const unsigned char *>(body.data()),
                         body.size()) == 1,
      "Signing failed");
  return QString::fromLatin1(
      QByteArray(reinterpret_cast<char *>(signature), size).toBase64());
}
bool verify(const QByteArray &body, const QByteArray &pub,
            const QByteArray &signature) {
  if (pub.size() != 32 || signature.size() != 64)
    return false;
  Key key(EVP_PKEY_new_raw_public_key(
              EVP_PKEY_ED25519, nullptr,
              reinterpret_cast<const unsigned char *>(pub.data()), pub.size()),
          EVP_PKEY_free);
  Context ctx(EVP_MD_CTX_new(), EVP_MD_CTX_free);
  return key && ctx &&
         EVP_DigestVerifyInit(ctx.get(), nullptr, nullptr, nullptr,
                              key.get()) == 1 &&
         EVP_DigestVerify(
             ctx.get(),
             reinterpret_cast<const unsigned char *>(signature.data()),
             signature.size(),
             reinterpret_cast<const unsigned char *>(body.data()),
             body.size()) == 1;
}
} // namespace
ForumBackend::ForumBackend(QObject *parent) : QObject(parent) {
  try {
    initialize();
  } catch (const std::exception &e) {
    m_error = QString::fromUtf8(e.what());
  }
}
ForumBackend::~ForumBackend() {
  if (m_db.isOpen())
    m_db.close();
  auto name = m_db.connectionName();
  m_db = QSqlDatabase();
  QSqlDatabase::removeDatabase(name);
}
void ForumBackend::initialize() {
  QString root = qEnvironmentVariable("LOGOS_FORUM_DATA_DIR");
  if (root.isEmpty()) {
    root = qEnvironmentVariable("LOGOS_USER_DIR");
    if (root.isEmpty())
      root = QDir::homePath() + "/.local/share/Logos/LogosBasecamp";
    root += "/module_data/logos_forum";
  }
  require(QDir().mkpath(root), "Cannot create forum data directory");
  QFile::setPermissions(root,
                        QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
  m_db = QSqlDatabase::addDatabase("QSQLITE", "forum-" + id());
  m_db.setDatabaseName(root + "/forum.sqlite");
  require(m_db.open(), m_db.lastError().text());
  QFile::setPermissions(root + "/forum.sqlite",
                        QFile::ReadOwner | QFile::WriteOwner);
  query(m_db, "PRAGMA journal_mode=WAL");
  query(m_db, "PRAGMA busy_timeout=5000");
  query(m_db, "PRAGMA foreign_keys=ON");
  query(m_db, "CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, "
              "value TEXT NOT NULL)");
  query(m_db, "CREATE TABLE IF NOT EXISTS identities (id TEXT PRIMARY KEY, "
              "alias TEXT NOT NULL, secret BLOB NOT NULL, public BLOB NOT "
              "NULL, created INTEGER NOT NULL)");
  query(m_db,
        "CREATE TABLE IF NOT EXISTS posts (id TEXT PRIMARY KEY, thread TEXT "
        "NOT NULL, board TEXT NOT NULL, title TEXT NOT NULL, body TEXT NOT "
        "NULL, author TEXT NOT NULL, mode TEXT NOT NULL, pub TEXT NOT NULL, "
        "created INTEGER NOT NULL, received INTEGER NOT NULL, wire TEXT NOT "
        "NULL, status TEXT NOT NULL, request TEXT NOT NULL DEFAULT '', "
        "attempts INTEGER NOT NULL DEFAULT 0, next_try INTEGER NOT NULL "
        "DEFAULT 0, error TEXT NOT NULL DEFAULT '')");
  query(m_db,
        "CREATE INDEX IF NOT EXISTS post_thread ON posts(thread,created)");
  query(m_db,
        "CREATE INDEX IF NOT EXISTS post_queue ON posts(status,next_try)");
  query(m_db, "CREATE TABLE IF NOT EXISTS attachments (id TEXT PRIMARY KEY, post TEXT NOT NULL DEFAULT '', name TEXT NOT NULL, mime TEXT NOT NULL, bytes INTEGER NOT NULL, path TEXT NOT NULL, preview BLOB)");
  query(m_db, "CREATE TABLE IF NOT EXISTS bookmarks (id TEXT PRIMARY KEY)");
  query(m_db, "CREATE TABLE IF NOT EXISTS drafts (id TEXT PRIMARY KEY, body "
              "TEXT NOT NULL)");
  query(m_db,
        "UPDATE posts SET status='queued', request='' WHERE status='sending'");
  auto q = query(m_db, "SELECT id FROM identities LIMIT 1");
  if (!q.next())
    identity("wanderer");
  qInfo("FORUM_BACKEND_READY SQLite and Ed25519 initialized");
}
QString ForumBackend::setting(const QString &key, const QString &fallback) {
  auto q = query(m_db, "SELECT value FROM settings WHERE key=?", {key});
  return q.next() ? q.value(0).toString() : fallback;
}
void ForumBackend::setSetting(const QString &key, const QString &value) {
  query(m_db, "INSERT OR REPLACE INTO settings VALUES (?,?)", {key, value});
}
QJsonObject ForumBackend::identity(const QString &name) {
  auto alias = name.trimmed();
  require(!alias.isEmpty() && alias.size() <= 32,
          "Alias must contain 1–32 characters");
  auto pair = keys();
  QString uid = hash(pair.second);
  query(m_db, "INSERT INTO identities VALUES (?,?,?,?,?)",
        {uid, alias, pair.first, pair.second, now()});
  setSetting("active", uid);
  return {{"id", uid}, {"alias", alias}};
}
QString ForumBackend::receiveBytes(const QByteArray &bytes) {
  return dispatch(
      json({{"op", "receive"}, {"wire", QString::fromUtf8(bytes)}}));
}
QString ForumBackend::dispatch(const QString &request) {
  try {
    require(m_error.isEmpty(), m_error);
    require(request.toUtf8().size() < 4 * 1024 * 1024, "Request too large");
    auto result = execute(object(request));
    result["ok"] = true;
    return json(result);
  } catch (const std::exception &e) {
    return json({{"ok", false}, {"error", QString::fromUtf8(e.what())}});
  }
}
QJsonObject ForumBackend::snapshot() {
  QJsonArray identities, posts, saved;
  QJsonObject drafts;
  auto q = query(m_db, "SELECT id,alias FROM identities ORDER BY created");
  while (q.next())
    identities.append(QJsonObject{{"id", q.value(0).toString()},
                                  {"alias", q.value(1).toString()}});
  q = query(
      m_db,
      "SELECT id,thread,board,title,body,author,mode,pub,created,status,error "
      "FROM posts ORDER BY created LIMIT 10000");
  while (q.next()) {
    QJsonObject p;
    QStringList names = {"id",      "thread", "board", "title",
                         "body",    "author", "mode",  "pub",
                         "created", "status", "error"};
    for (int i = 0; i < names.size(); ++i)
      p[names[i]] = i == 8 ? QJsonValue(q.value(i).toDouble())
                           : QJsonValue(q.value(i).toString());
    p["authorId"] = p["pub"].toString().isEmpty() ? QString() : hash(QByteArray::fromBase64(p["pub"].toString().toLatin1()));
    QJsonArray files;
    auto aq = query(m_db, "SELECT id,name,mime,bytes FROM attachments WHERE post=? ORDER BY rowid", {p["id"].toString()});
    while (aq.next()) files.append(QJsonObject{{"id",aq.value(0).toString()},{"name",aq.value(1).toString()},{"mime",aq.value(2).toString()},{"bytes",aq.value(3).toDouble()}});
    p["attachments"] = files;
    posts.append(p);
  }
  q = query(m_db, "SELECT id FROM bookmarks");
  while (q.next())
    saved.append(q.value(0).toString());
  q = query(m_db, "SELECT id,body FROM drafts");
  while (q.next())
    drafts[q.value(0).toString()] = q.value(1).toString();
  QJsonValue avatarValue;
  const auto storedAvatar = setting("avatar/" + setting("active"));
  if (!storedAvatar.isEmpty()) {
    const auto image = QImage::fromData(QByteArray::fromBase64(storedAvatar.section(',',1).toLatin1())).scaled(64,64,Qt::IgnoreAspectRatio,Qt::SmoothTransformation).convertToFormat(QImage::Format_ARGB32);
    if (!image.isNull()) {
      QJsonArray pixels;
      for (int y=0;y<64;++y) for(int x=0;x<64;++x) pixels.append(static_cast<double>(image.pixel(x,y)));
      avatarValue = QJsonObject{{"size",64},{"pixels",pixels}};
    }
  }
  return {{"posts", posts},
          {"identities", identities},
          {"saved", saved},
          {"drafts", drafts},
          {"active", setting("active")},
          {"mode", setting("mode", "alias")},
          {"theme", setting("theme", "dark")},
          {"avatar", avatarValue},
          {"rotate", setting("rotate", "false") == "true"},
          {"historyPeer", setting("historyPeer")},
          {"historyCursor", setting("historyCursor")}};
}
QJsonObject ForumBackend::post(const QJsonObject &cmd) {
  QString body = cmd["body"].toString().trimmed(),
          title = cmd["title"].toString().trimmed(),
          thread = cmd["thread"].toString(), board = cmd["board"].toString();
  require(!body.isEmpty() && body.size() <= 12000,
          "Message must contain 1–12,000 characters");
  require(boards.contains(board), "Unknown board");
  if (thread.isEmpty())
    require(!title.isEmpty() && title.size() <= 160,
            "Title must contain 1–160 characters");
  else {
    auto t = query(m_db, "SELECT board FROM posts WHERE id=? AND thread=''",
                   {thread});
    require(t.next(), "Thread is not available locally");
    board = t.value(0).toString();
    title = "";
  }
  QString mode = setting("mode", "alias");
  QString author, pub;
  QByteArray secret;
  if (mode != "anonymous") {
    auto q =
        query(m_db, "SELECT alias,secret,public FROM identities WHERE id=?",
              {setting("active")});
    require(q.next(), "Select an identity");
    secret = q.value(1).toByteArray();
    pub = QString::fromLatin1(q.value(2).toByteArray().toBase64());
    author =
        mode == "uid" ? hash(q.value(2).toByteArray()) : q.value(0).toString();
  }
  QJsonObject envelope{
      {"v", 1},           {"nonce", id()},
      {"thread", thread}, {"board", board},
      {"title", title},   {"body", body},
      {"mode", mode},     {"author", author},
      {"pub", pub},       {"created", static_cast<double>(now())}};
  QByteArray bytes = canonical(envelope);
  QString pid = hash(bytes);
  QJsonObject wire{
      {"id", pid},
      {"payload", envelope},
      {"signature", mode == "anonymous" ? QString() : sign(bytes, secret)}};
  auto attachments = cmd["attachments"].toArray();
  require(attachments.size() <= 4, "Attach at most four files per post");
  bool localOnly = !attachments.isEmpty();
  if (!thread.isEmpty()) {
    auto parent = query(m_db, "SELECT status FROM posts WHERE id=?", {thread});
    if (parent.next() && parent.value(0).toString() == "local") localOnly = true;
  }
  require(m_db.transaction(), "Cannot begin transaction");
  try {
    for (const auto &value : attachments) {
      auto file = query(m_db, "SELECT post FROM attachments WHERE id=?", {value.toString()});
      require(file.next() && file.value(0).toString().isEmpty(), "Attachment is unavailable or already used");
      query(m_db, "UPDATE attachments SET post=? WHERE id=?", {pid,value.toString()});
    }
    query(m_db,
          "INSERT INTO posts "
          "(id,thread,board,title,body,author,mode,pub,created,received,wire,"
          "status) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
          {pid, thread, board, title, body, author, mode, pub, now(), now(),
           json(wire), localOnly ? "local" : "queued"});
    query(m_db, "DELETE FROM drafts WHERE id=?",
          {thread.isEmpty() ? QString("new") : thread});
    if (setting("rotate", "false") == "true" && thread.isEmpty() &&
        mode != "anonymous")
      identity("wanderer-" + id().left(5));
    require(m_db.commit(), "Commit failed");
  } catch (...) {
    m_db.rollback();
    throw;
  }
  emit changed();
  return {{"id", pid}, {"status", localOnly ? "local" : "queued"}};
}
QJsonObject ForumBackend::attachment(const QJsonObject &c) {
  const auto op = c["op"].toString();
  if (op == "attachmentVideo") {
    const auto action = c["action"].toString();
    require(QStringList{"play","pause","stop","seek","volume","mute","state"}.contains(action),"Unknown video action");
    if(!m_video) m_video = new VideoSession(this);
    if(action == "play") {
      auto q = query(m_db,"SELECT path,mime FROM attachments WHERE id=?",{c["id"].toString()});
      require(q.next() && q.value(1).toString().startsWith("video/"),"Video attachment not found");
      const auto path=q.value(0).toString();
      const auto root=QFileInfo(m_db.databaseName()).absolutePath()+"/attachments";
      require(QFileInfo(path).isFile() && QFileInfo(path).canonicalFilePath().startsWith(QFileInfo(root).canonicalFilePath()+"/"),"Video file is missing or outside attachment storage");
      m_video->play(c["id"].toString(),path);
    }
    return m_video->command(c);
  }
  if (op == "attachmentImport") {
    const QUrl url(c["file"].toString());
    require(url.isLocalFile(), "Choose a file from this device");
    QFile input(url.toLocalFile());
    require(input.open(QIODevice::ReadOnly), "Cannot read attachment");
    require(input.size() > 0 && input.size() <= 64 * 1024 * 1024, "Attachments must be smaller than 64 MB");
    const auto mime = QMimeDatabase().mimeTypeForData(input.peek(65536)).name();
    const QMap<QString,QString> formats{{"image/png","png"},{"image/jpeg","jpg"},{"application/pdf","pdf"},{"video/mp4","mp4"},{"video/webm","webm"}};
    require(formats.contains(mime), "Choose a PNG, JPEG, MP4, WebM or PDF file");
    QImage preview;
    if (mime.startsWith("image/")) {
      QImageReader reader(&input); reader.setAutoTransform(true);
      require(reader.size().isValid() && qint64(reader.size().width()) * reader.size().height() <= 24000000, "Image exceeds 24 megapixels");
      preview = reader.read();
      require(!preview.isNull(), "Invalid image");
      input.seek(0);
    }
    const auto aid = id();
    const auto directory = QFileInfo(m_db.databaseName()).absolutePath() + "/attachments";
    require(QDir().mkpath(directory), "Cannot create attachment directory");
    QFile::setPermissions(directory, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    const auto path = directory + "/" + aid + "." + formats.value(mime);
    QFile output(path);
    require(output.open(QIODevice::WriteOnly | QIODevice::NewOnly), "Cannot save attachment");
    const auto bytes = input.read(64 * 1024 * 1024 + 1);
    if (bytes.isEmpty() || bytes.size() > 64 * 1024 * 1024) { output.close(); QFile::remove(path); require(false, "Attachment size changed while reading"); }
    if (output.write(bytes) != bytes.size()) { output.close(); QFile::remove(path); require(false,"Cannot save attachment"); }
    output.close(); QFile::setPermissions(path,QFile::ReadOwner | QFile::WriteOwner);
    // Optional local thumbnail helpers; never fetch URLs or run shell text.
    if (preview.isNull()) {
      QTemporaryDir tmp;
      QProcess process;
      if (mime == "application/pdf") {
        const auto exe = QStandardPaths::findExecutable("pdftoppm");
        if (!exe.isEmpty()) process.start(exe,{"-f","1","-singlefile","-scale-to","240","-png",path,tmp.path()+"/preview"});
      } else {
        const auto exe = QStandardPaths::findExecutable("ffmpeg");
        if (!exe.isEmpty()) process.start(exe,{"-nostdin","-loglevel","error","-protocol_whitelist","file,pipe","-i",path,"-frames:v","1","-vf","scale=240:160:force_original_aspect_ratio=decrease",tmp.path()+"/preview.png"});
      }
      if (process.state() != QProcess::NotRunning && !process.waitForFinished(5000)) { process.kill(); process.waitForFinished(); }
      preview.load(tmp.path()+"/preview.png");
    }
    QByteArray png;
    if (!preview.isNull()) {
      preview = preview.scaled(240,160,Qt::KeepAspectRatio,Qt::SmoothTransformation);
      QBuffer buffer(&png); buffer.open(QIODevice::WriteOnly); preview.save(&buffer,"PNG");
    }
    const auto name = QFileInfo(url.toLocalFile()).fileName().left(180);
    try { query(m_db,"INSERT INTO attachments (id,name,mime,bytes,path,preview) VALUES (?,?,?,?,?,?)",{aid,name,mime,bytes.size(),path,png}); }
    catch (...) { QFile::remove(path); throw; }
    return {{"attachment",QJsonObject{{"id",aid},{"name",name},{"mime",mime},{"bytes",bytes.size()}}}};
  }
  auto q = query(m_db,"SELECT path,preview,mime FROM attachments WHERE id=?",{c["id"].toString()});
  require(q.next(), "Attachment not found");
  const auto path = q.value(0).toString();
  if (op == "attachmentPreview") {
    const auto img = QImage::fromData(q.value(1).toByteArray()).convertToFormat(QImage::Format_ARGB32);
    if (img.isNull()) return {{"image",QJsonValue::Null}};
    QJsonArray pixels;
    for(int y=0;y<img.height();y++) for(int x=0;x<img.width();x++) pixels.append(double(img.pixel(x,y)));
    return {{"image",QJsonObject{{"width",img.width()},{"height",img.height()},{"pixels",pixels}}}};
  }
  require(QFileInfo::exists(path),"Attachment file is missing");
  if (op == "attachmentOpen") {
    const auto opener = QStandardPaths::findExecutable("xdg-open");
    require(!opener.isEmpty() && QProcess::startDetached(opener,{path}),"Could not start the system viewer");
    return {};
  }
  if (op == "attachmentExport") {
    const QUrl destination(c["file"].toString());
    require(destination.isLocalFile(),"Choose a local destination");
    require(!QFileInfo::exists(destination.toLocalFile()),"Choose a new filename; existing files are not overwritten");
    require(QFile::copy(path,destination.toLocalFile()),"Could not save attachment");
    return {};
  }
  require(false,"Unknown attachment operation");
  return {};
}
QJsonObject ForumBackend::receive(const QString &wire) {
  require(wire.toUtf8().size() <= 65536, "Envelope exceeds 64 KiB");
  auto w = object(wire), p = w["payload"].toObject();
  auto bytes = canonical(p);
  auto pid = w["id"].toString();
  require(pid == hash(bytes) && p["v"].toInt() == 1,
          "Invalid version or content hash");
  QString body = p["body"].toString(), thread = p["thread"].toString(),
          board = p["board"].toString(), title = p["title"].toString(),
          mode = p["mode"].toString(), author = p["author"].toString(),
          pub = p["pub"].toString();
  require(boards.contains(board) && !body.trimmed().isEmpty() &&
              body.size() <= 12000 && title.size() <= 160,
          "Invalid content");
  require(thread.isEmpty()
              ? !title.trimmed().isEmpty()
              : QRegularExpression("^[a-f0-9]{64}$").match(thread).hasMatch(),
          "Invalid thread reference");
  const double timestamp = p["created"].toDouble();
  require(timestamp > 0 && timestamp <= static_cast<double>(now() + 300000), "Invalid timestamp");
  auto created = static_cast<qint64>(timestamp);
  if (mode == "anonymous")
    require(author.isEmpty() && pub.isEmpty() &&
                w["signature"].toString().isEmpty(),
            "Anonymous envelope includes identity");
  else {
    require(mode == "alias" || mode == "uid", "Invalid identity mode");
    auto publicKey = QByteArray::fromBase64(pub.toLatin1());
    require(
        verify(bytes, publicKey,
               QByteArray::fromBase64(w["signature"].toString().toLatin1())),
        "Invalid signature");
    require(mode == "uid" ? author == hash(publicKey)
                          : !author.isEmpty() && author.size() <= 32,
            "Invalid author");
  }
  if (!thread.isEmpty()) {
    auto parent = query(
        m_db, "SELECT board FROM posts WHERE id=? AND thread=''", {thread});
    if (parent.next())
      require(parent.value(0).toString() == board,
              "Reply board does not match thread");
  }
  auto exists = query(m_db, "SELECT id FROM posts WHERE id=?", {pid});
  if (exists.next())
    return {{"duplicate", true}};
  query(m_db,
        "INSERT INTO posts "
        "(id,thread,board,title,body,author,mode,pub,created,received,wire,"
        "status) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        {pid, thread, board, title, body, author, mode, pub, created, now(),
         wire, "received"});
  emit changed();
  return {{"id", pid}, {"duplicate", false}};
}
QJsonObject ForumBackend::execute(const QJsonObject &c) {
  auto op = c["op"].toString();
  if (op.startsWith("attachment")) return attachment(c);
  if (op == "snapshot")
    return snapshot();
  if (op == "avatar") {
    const auto key = "avatar/" + setting("active");
    if (c["remove"].toBool()) {
      setSetting(key, "");
    } else {
      const QUrl url(c["file"].toString());
      require(url.isLocalFile(), "Choose an image from this device");
      QFile file(url.toLocalFile());
      require(file.open(QIODevice::ReadOnly), "Cannot open this image");
      require(file.size() > 0 && file.size() <= 8 * 1024 * 1024, "Choose an image smaller than 8 MB");
      QImageReader reader(&file);
      const auto format = reader.format().toLower();
      require(format == "png" || format == "jpeg" || format == "jpg", "Choose a PNG or JPEG image");
      const auto size = reader.size();
      require(size.isValid() && size.width() <= 4096 && size.height() <= 4096, "Choose an image up to 4096 pixels per side");
      reader.setAutoTransform(true);
      const auto original = reader.read();
      require(!original.isNull(), "This image could not be read");
      const auto scaled = original.scaled(128, 128, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
      QImage avatar(128,128,QImage::Format_ARGB32_Premultiplied);
      avatar.fill(Qt::transparent);
      { QPainter painter(&avatar); painter.drawImage((128-scaled.width())/2, (128-scaled.height())/2, scaled); }
      QByteArray bytes; QBuffer buffer(&bytes); buffer.open(QIODevice::WriteOnly);
      require(avatar.save(&buffer,"PNG"), "Could not save the avatar");
      setSetting(key, "data:image/png;base64," + QString::fromLatin1(bytes.toBase64()));
    }
    emit changed();
    return {};
  }
  if (op == "historyPage") {
    const auto page = c["page"].toObject();
    require(page["statusCode"].toInt() == 200,
            "Store peer did not return a successful history page");
    const auto messages = page["messages"].toArray();
    require(messages.size() <= 50, "History page exceeds 50 messages");
    int accepted = 0, duplicates = 0, rejected = 0;
    {
      QSignalBlocker blocker(this);
      for (const auto &item : messages) {
        auto message = item.toObject()["message"].toObject();
        if (message["contentTopic"].toString() !=
            QStringLiteral("/logos-forum/1/commons/json")) {
          ++rejected;
          continue;
        }
        const auto bytes =
            QByteArray::fromBase64(message["payload"].toString().toLatin1(),
                                   QByteArray::AbortOnBase64DecodingErrors);
        try {
          auto result = receive(QString::fromUtf8(bytes));
          if (result["duplicate"].toBool())
            ++duplicates;
          else
            ++accepted;
        } catch (const std::exception &) {
          ++rejected;
        }
      }
    }
    setSetting("historyPeer", c["peer"].toString());
    setSetting("historyCursor", page["paginationCursor"].toString());
    emit changed();
    return {{"accepted", accepted},
            {"duplicates", duplicates},
            {"rejected", rejected}};
  }

  if (op == "post")
    return post(c);
  if (op == "receive")
    return receive(c["wire"].toString());
  if (op == "identity") {
    auto out = identity(c["alias"].toString());
    emit changed();
    return out;
  }
  if (op == "settings") {
    if (c.contains("active")) {
      auto q = query(m_db, "SELECT id FROM identities WHERE id=?",
                     {c["active"].toString()});
      require(q.next(), "Unknown identity");
      setSetting("active", c["active"].toString());
    }
    if (c.contains("mode")) {
      auto mode = c["mode"].toString();
      require(QStringList{"alias", "uid", "anonymous"}.contains(mode),
              "Unknown mode");
      setSetting("mode", mode);
    }
    if (c.contains("theme")) {
      const auto theme = c["theme"].toString();
      require(theme == "dark" || theme == "light", "Unknown theme");
      setSetting("theme", theme);
    }
    if (c.contains("rotate")) {
      setSetting("rotate", c["rotate"].toBool() ? "true" : "false");
    }
    emit changed();
    return {};
  }
  if (op == "draft") {
    auto body = c["body"].toString();
    require(body.size() <= 15000, "Draft too large");
    query(m_db, "INSERT OR REPLACE INTO drafts VALUES (?,?)",
          {c["id"].toString(), body});
    return {};
  }
  if (op == "bookmark") {
    auto pid = c["id"].toString();
    auto q = query(m_db, "SELECT id FROM bookmarks WHERE id=?", {pid});
    if (q.next())
      query(m_db, "DELETE FROM bookmarks WHERE id=?", {pid});
    else
      query(m_db, "INSERT INTO bookmarks VALUES (?)", {pid});
    emit changed();
    return {};
  }
  if (op == "next") {
    auto q =
        query(m_db,
              "SELECT id,wire,attempts FROM posts WHERE (status='queued' OR "
              "status='failed') AND next_try<=? ORDER BY created LIMIT 1",
              {now()});
    if (!q.next())
      return {{"item", QJsonValue::Null}};
    QString pid = q.value(0).toString(), wire = q.value(1).toString();
    int attempts = q.value(2).toInt();
    query(m_db,
          "UPDATE posts SET status='sending',attempts=attempts+1,next_try=? "
          "WHERE id=?",
          {now() + 60000, pid});
    m_outbound = wire.toUtf8();
    emit changed();
    return {
        {"item",
         QJsonObject{{"id", pid}, {"wire", wire}, {"attempts", attempts + 1}}}};
  }
  if (op == "delivery") {
    QString status = c["status"].toString();
    require(QStringList{"sending", "sent", "failed", "queued"}.contains(status),
            "Invalid delivery status");
    QString pid = c["id"].toString();
    auto q = query(m_db, "SELECT attempts,status FROM posts WHERE id=?", {pid});
    require(q.next(), "Unknown queued message");
    require(q.value(1).toString() != "received" && q.value(1).toString() != "local",
            "Cannot alter received message delivery");
    int attempt = q.value(0).toInt();
    qint64 delay = qMin<qint64>(3600000, 5000LL * (1LL << qMin(attempt, 9)));
    query(m_db,
          "UPDATE posts SET status=?,request=?,error=?,next_try=? WHERE id=?",
          {status, c["request"].toString(), c["error"].toString().left(2000),
           now() + delay, pid});
    emit changed();
    return {};
  }
  if (op == "retry") {
    query(m_db, "UPDATE posts SET status='queued',next_try=0,error='' WHERE "
                "status='failed'");
    emit changed();
    return {};
  }
  if (op == "wire") {
    auto q =
        query(m_db, "SELECT wire FROM posts WHERE id=? AND status != 'local'", {c["id"].toString()});
    require(q.next(), "Unknown post");
    return {{"wire", q.value(0).toString()}};
  }
  throw std::runtime_error("Unknown operation");
}
