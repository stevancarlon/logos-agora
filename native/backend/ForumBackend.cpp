#include "AttachmentMime.h"
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
#include <cmath>

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
bool validCid(const QString &cid) {
  return QRegularExpression("^[a-zA-Z0-9]{20,160}$").match(cid).hasMatch();
}
void validateAttachmentManifest(const QJsonObject &file) {
  const auto name=file["name"].toString(), mime=file["mime"].toString();
  const auto size=file["bytes"].toDouble(-1);
  require(!name.isEmpty() && name.size()<=180 && !name.contains('/') && !name.contains('\\') &&
          !name.contains(QChar(0)) && name != "." && name != "..", "Invalid attachment name");
  for (const auto ch : name) require(ch.category()!=QChar::Other_Control, "Invalid attachment name");
  require(QStringList{"image/png","image/jpeg","video/mp4","video/webm","application/pdf"}.contains(mime), "Unsupported attachment type");
  require(size>0 && size<=64*1024*1024 && size==double(qint64(size)), "Invalid attachment size");
  require(validCid(file["cid"].toString()), "Invalid Storage content ID");
  require(QRegularExpression("^[a-f0-9]{64}$").match(file["sha256"].toString()).hasMatch(), "Invalid attachment checksum");
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
  delete m_transfer; m_transfer=nullptr;
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
    if (root.isEmpty()) {
#ifdef Q_OS_WIN
      root = qEnvironmentVariable("APPDATA") + "/Logos/LogosBasecamp";
#else
      root = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/Logos/LogosBasecamp";
#endif
    }
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
  QStringList attachmentColumns;
  auto columns=query(m_db,"PRAGMA table_info(attachments)");
  while(columns.next()) attachmentColumns.append(columns.value(1).toString());
  for (const auto &column : QStringList{"cid","sha256"})
    if (!attachmentColumns.contains(column)) query(m_db,"ALTER TABLE attachments ADD COLUMN "+column+" TEXT NOT NULL DEFAULT ''");
  query(m_db,"CREATE INDEX IF NOT EXISTS attachment_post ON attachments(post)");
  QStringList postColumns;
  auto postInfo=query(m_db,"PRAGMA table_info(posts)");
  while(postInfo.next()) postColumns.append(postInfo.value(1).toString());
  if(!postColumns.contains("search_text")) {
    require(m_db.transaction(),"Cannot begin search migration");
    try {
      query(m_db,"ALTER TABLE posts ADD COLUMN search_text TEXT NOT NULL DEFAULT ''");
      auto oldPosts=query(m_db,"SELECT id,title,body FROM posts");
      while(oldPosts.next()) query(m_db,"UPDATE posts SET search_text=? WHERE id=?",
        {(oldPosts.value(1).toString()+" "+oldPosts.value(2).toString()).toCaseFolded(),oldPosts.value(0)});
      require(m_db.commit(),"Cannot finish search migration");
    } catch(...) {m_db.rollback();throw;}
  }
  query(m_db,"CREATE INDEX IF NOT EXISTS post_page ON posts(thread,created,id)");
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
  // Limit live intake before parsing, canonicalization or signature work. Store
  // pages use their separate bounded recovery path so a burst cannot strand the
  // saved history cursor beyond messages we temporarily declined.
  if (bytes.size() > 65536)
    return json({{"ok",false},{"error","Envelope exceeds 64 KiB"}});
  if (!m_intakeClock.isValid()) m_intakeClock.start();
  const auto elapsed=m_intakeClock.nsecsElapsed();
  m_intakeTokens=qMin(240.,m_intakeTokens+(elapsed-m_intakeLastNs)*4./1e9);
  m_intakeLastNs=elapsed;
  if(m_intakeTokens<1.) {
    ++m_rateLimited;
    return json({{"ok",false},{"rateLimited",true},{"retryAfterMs",int(std::ceil((1.-m_intakeTokens)/0.004))},
                 {"error","Live message intake limited; recover missed posts from Store"}});
  }
  m_intakeTokens-=1.;
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
QJsonValue ForumBackend::avatarImage(const QString &identity) {
  if (identity.isEmpty()) return {};
  const auto stored = setting("avatar/" + identity);
  if (stored.isEmpty()) return {};
  const auto image = QImage::fromData(QByteArray::fromBase64(stored.section(',', 1).toLatin1()))
                         .scaled(64, 64, Qt::IgnoreAspectRatio, Qt::SmoothTransformation)
                         .convertToFormat(QImage::Format_ARGB32);
  if (image.isNull()) return {};
  QJsonArray pixels;
  for (int y = 0; y < 64; ++y)
    for (int x = 0; x < 64; ++x) pixels.append(static_cast<double>(image.pixel(x, y)));
  return QJsonObject{{"size", 64}, {"pixels", pixels}};
}
QJsonObject ForumBackend::postRecord(const QString &pid) {
  auto q = query(
      m_db,
      "SELECT id,thread,board,title,body,author,mode,pub,created,status,error "
      "FROM posts WHERE id=?", {pid});
  if (q.next()) {
    QJsonObject p;
    QStringList names = {"id",      "thread", "board", "title",
                         "body",    "author", "mode",  "pub",
                         "created", "status", "error"};
    for (int i = 0; i < names.size(); ++i)
      p[names[i]] = i == 8 ? QJsonValue(q.value(i).toDouble())
                           : QJsonValue(q.value(i).toString());
    p["authorId"] = p["pub"].toString().isEmpty() ? QString() : hash(QByteArray::fromBase64(p["pub"].toString().toLatin1()));
    QJsonArray files;
    auto aq = query(m_db, "SELECT id,name,mime,bytes,cid,sha256,path FROM attachments WHERE post=? ORDER BY rowid", {p["id"].toString()});
    while (aq.next()) files.append(QJsonObject{{"id",aq.value(0).toString()},{"name",aq.value(1).toString()},{"mime",aq.value(2).toString()},{"bytes",aq.value(3).toDouble()},{"cid",aq.value(4).toString()},{"sha256",aq.value(5).toString()},{"available",QFileInfo::exists(aq.value(6).toString())}});
    p["attachments"] = files;
    return p;
  }
  return {};
}
QJsonObject ForumBackend::browse(const QJsonObject &options) {
  const auto view=options["view"].toString("recent");
  const auto thread=options["thread"].toString();
  const auto board=options["board"].toString("all");
  const auto search=options["search"].toString().trimmed().toCaseFolded();
  const auto sorting=options["sort"].toString("activity");
  require(QStringList{"recent","feed","thread"}.contains(view),"Unknown browsing view");
  require(board=="all" || boards.contains(board),"Unknown board");
  require(search.size()<=200,"Search is limited to 200 characters");
  require(QStringList{"activity","newest","replies"}.contains(sorting),"Unknown sort order");
  const int limit=qBound(1,options["limit"].toInt(view=="thread"?50:30),100);
  const auto context=hash(canonical({{"view",view},{"thread",thread},{"board",board},
    {"search",search},{"sort",sorting},{"saved",options["saved"].toBool()}}));
  const auto cursor=options["cursor"].toString();
  QJsonObject after;
  if(!cursor.isEmpty()) {
    require(cursor.size()<=1024,"Invalid page cursor");
    after=object(QString::fromUtf8(QByteArray::fromBase64(cursor.toLatin1(),QByteArray::Base64UrlEncoding|QByteArray::AbortOnBase64DecodingErrors)));
    require(after["context"].toString()==context && after["score"].toDouble(-1)>=0 && after["score"].toDouble()>-1 && after["score"].toDouble()<=9e15 &&
      after["created"].toDouble(-1)>=0 && after["created"].toDouble()<=9e15 &&
      QRegularExpression("^[a-f0-9]{64}$").match(after["id"].toString()).hasMatch(),"Cursor does not match this view");
  }
  QJsonArray posts;
  QJsonObject last;
  bool more=false;
  if(view=="recent") {
    auto rows=query(m_db,"SELECT id FROM (SELECT id,rowid FROM posts ORDER BY rowid DESC LIMIT 200) ORDER BY rowid");
    while(rows.next()) posts.append(postRecord(rows.value(0).toString()));
  } else if(view=="thread") {
    require(QRegularExpression("^[a-f0-9]{64}$").match(thread).hasMatch(),"Invalid thread ID");
    auto root=postRecord(thread);
    if(!root.isEmpty() && root["thread"].toString().isEmpty()) {
      auto stats=query(m_db,"SELECT COUNT(*),MAX(created) FROM posts WHERE thread=? AND board=?",{thread,root["board"].toString()});
      stats.next();root["replyCount"]=stats.value(0).toInt();
      root["lastActivity"]=qMax(root["created"].toDouble(),stats.value(1).toDouble());posts.append(root);
      if(options.contains("anchor")) {
        auto target=query(m_db,"SELECT created,id FROM posts WHERE id=? AND thread=? AND board=?",{options["anchor"].toString(),thread,root["board"].toString()});
        require(target.next(),"Reply is not part of this thread");
        auto before=query(m_db,"SELECT id,created FROM posts WHERE thread=? AND board=? AND (created<? OR (created=? AND id<=?)) ORDER BY created DESC,id DESC LIMIT 1 OFFSET ?",{thread,root["board"].toString(),target.value(0),target.value(0),target.value(1),limit});
        if(before.next()) after={{"id",before.value(0).toString()},{"created",before.value(1).toDouble()},{"score",before.value(1).toDouble()},{"context",context}};
      }
      QString sql="SELECT id,created FROM posts WHERE thread=? AND board=?";
      QVariantList values{thread,root["board"].toString()};
      if(!after.isEmpty()) {sql+=" AND (created>? OR (created=? AND id>?))";values<<after["created"].toDouble()<<after["created"].toDouble()<<after["id"].toString();}
      sql+=" ORDER BY created,id LIMIT ?";values<<limit+1;
      auto rows=query(m_db,sql,values);int count=0;
      while(rows.next()) {
        if(count++==limit) {more=true;break;}
        posts.append(postRecord(rows.value(0).toString()));
        last={{"created",rows.value(1).toDouble()},{"score",rows.value(1).toDouble()},{"id",rows.value(0).toString()}};
      }
    }
  } else {
    QString where="p.thread=''";
    QVariantList values;
    if(board!="all") {where+=" AND p.board=?";values<<board;}
    if(options["saved"].toBool()) where+=" AND EXISTS(SELECT 1 FROM bookmarks b WHERE b.id=p.id)";
    if(!search.isEmpty()) {
      where+=" AND (instr(p.search_text,?)>0 OR EXISTS(SELECT 1 FROM posts r WHERE r.thread=p.id AND r.board=p.board AND instr(r.search_text,?)>0))";
      values<<search<<search;
    }
    const auto count="(SELECT COUNT(*) FROM posts r WHERE r.thread=p.id AND r.board=p.board)";
    const auto activity="MAX(p.created,COALESCE((SELECT MAX(created) FROM posts r WHERE r.thread=p.id AND r.board=p.board),p.created))";
    const QString score=sorting=="replies"?count:sorting=="newest"?"p.created":activity;
    QString sql="WITH ranked AS (SELECT p.id,p.created,"+QString(count)+" AS replyCount,"+activity+" AS activity,"+score+" AS score FROM posts p WHERE "+where+") SELECT * FROM ranked";
    if(!after.isEmpty()) {
      sql+=" WHERE (score<? OR (score=? AND (created<? OR (created=? AND id<?))))";
      values<<after["score"].toDouble()<<after["score"].toDouble()<<after["created"].toDouble()<<after["created"].toDouble()<<after["id"].toString();
    }
    sql+=" ORDER BY score DESC,created DESC,id DESC LIMIT ?";values<<limit+1;
    auto rows=query(m_db,sql,values);int n=0;
    while(rows.next()) {
      if(n++==limit) {more=true;break;}
      auto root=postRecord(rows.value(0).toString());
      root["replyCount"]=rows.value(2).toInt(); root["lastActivity"]=rows.value(3).toDouble();posts.append(root);
      auto latest=query(m_db,"SELECT id FROM posts WHERE thread=? AND board=? ORDER BY created DESC,id DESC LIMIT 1",{root["id"].toString(),root["board"].toString()});
      if(latest.next()) posts.append(postRecord(latest.value(0).toString()));
      last={{"created",rows.value(1).toDouble()},{"score",rows.value(4).toDouble()},{"id",rows.value(0).toString()}};
    }
  }
  QString next;
  if(more) {last["context"]=context;next=QString::fromLatin1(canonical(last).toBase64(QByteArray::Base64UrlEncoding|QByteArray::OmitTrailingEquals));}
  const auto pageCursor=after.isEmpty()?QString():QString::fromLatin1(canonical(after).toBase64(QByteArray::Base64UrlEncoding|QByteArray::OmitTrailingEquals));
  return {{"pageCursor",pageCursor},{"posts",posts},{"view",view},{"threadId",thread},{"hasMore",more},{"nextCursor",next}};
}
QJsonObject ForumBackend::snapshot(const QJsonObject &options) {
  auto listing=browse(options);
  QJsonArray identities, saved;
  const auto posts=listing["posts"].toArray();
  QJsonObject drafts;
  auto q = query(m_db, "SELECT id,alias FROM identities ORDER BY created");
  while (q.next())
    identities.append(QJsonObject{{"id", q.value(0).toString()},
                                  {"alias", q.value(1).toString()}});
  q = query(m_db, "SELECT id FROM bookmarks");
  while (q.next())
    saved.append(q.value(0).toString());
  q = query(m_db, "SELECT id,body FROM drafts");
  while (q.next())
    drafts[q.value(0).toString()] = q.value(1).toString();
  const auto active = setting("active");
  const auto avatarValue = avatarImage(active);
  // Send each visible author's pixels once, keyed by signing identity rather
  // than display alias. Older posts retain their own identity's portrait.
  QJsonObject avatars{{active, avatarValue}};
  for (const auto &value : posts) {
    const auto post = value.toObject();
    const auto author = post["authorId"].toString();
    if (post["mode"].toString() != "anonymous" && !author.isEmpty() && !avatars.contains(author))
      avatars[author] = avatarImage(author);
  }
  return {{"posts", posts},{"view",listing["view"]},{"threadId",listing["threadId"]},{"hasMore",listing["hasMore"]},{"nextCursor",listing["nextCursor"]},
          {"liveMessagesDeferred",double(m_rateLimited)},
          {"identities", identities},
          {"saved", saved},
          {"drafts", drafts},
          {"active", setting("active")},
          {"mode", setting("mode", "alias")},
          {"theme", setting("theme", "dark")},
          {"avatar", avatarValue},
          {"avatars", avatars},
          {"rotate", setting("rotate", "false") == "true"},
          {"autoConnect", setting("autoConnect", QFileInfo(m_db.databaseName()).absolutePath().endsWith("/AgoraExamples/module_data/logos_forum") ? "false" : "true") == "true"},
          {"storageEndpoint",setting("storageEndpoint")},
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
  auto attachments = cmd["attachments"].toArray();
  require(attachments.size() <= 4, "Attach at most four files per post");
  QJsonArray manifests;
  bool localOnly = false;
  for (const auto &value : attachments) {
    auto file=query(m_db,"SELECT name,mime,bytes,cid,sha256 FROM attachments WHERE id=? AND post=''",{value.toString()});
    require(file.next(),"Attachment is unavailable or already used");
    if (file.value(3).toString().isEmpty()) localOnly=true;
    else {
      QJsonObject manifest{{"name",file.value(0).toString()},{"mime",file.value(1).toString()},
        {"bytes",file.value(2).toDouble()},{"cid",file.value(3).toString()},{"sha256",file.value(4).toString()}};
      validateAttachmentManifest(manifest); manifests.append(manifest);
    }
  }
  if (!thread.isEmpty()) {
    auto parent = query(m_db, "SELECT status FROM posts WHERE id=?", {thread});
    if (parent.next() && parent.value(0).toString() == "local") localOnly = true;
  }
  if (!attachments.isEmpty() && !localOnly) {
    envelope["v"]=2; envelope["attachments"]=manifests;
  }
  QByteArray bytes = canonical(envelope);
  QString pid = hash(bytes);
  QJsonObject wire{{"id",pid},{"payload",envelope},
    {"signature",mode == "anonymous" ? QString() : sign(bytes,secret)}};
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
    query(m_db,"UPDATE posts SET search_text=? WHERE id=?",{(title+" "+body).toCaseFolded(),pid});
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
  if (op == "attachmentTransfer")
    return {{"transfer",m_transfer ? m_transfer->state() : QJsonObject()}};
  if (op == "attachmentCancel") { if(m_transfer) m_transfer->cancel(); return {}; }
  if (op == "attachmentUpload" || op == "attachmentFetch") {
    const bool upload=op=="attachmentUpload";
    auto q=query(m_db,"SELECT name,mime,bytes,path,cid,sha256,post FROM attachments WHERE id=?",{c["id"].toString()});
    require(q.next(),"Attachment not found");
    require(!upload || q.value(6).toString().isEmpty(),"Only unattached files can be uploaded");
    if(upload && !q.value(4).toString().isEmpty()) return {{"alreadyAvailable",true}};
    if(!upload && QFileInfo::exists(q.value(3).toString())) return {{"alreadyAvailable",true}};
    QJsonObject file{{"name",q.value(0).toString()},{"mime",q.value(1).toString()},
      {"bytes",q.value(2).toDouble()},{"cid",q.value(4).toString()},{"sha256",q.value(5).toString()}};
    auto path=q.value(3).toString();
    const auto directory=QFileInfo(m_db.databaseName()).absolutePath()+"/attachments";
    if(upload) require(QFileInfo(path).isFile() && QFileInfo(path).canonicalFilePath().startsWith(QFileInfo(directory).canonicalFilePath()+"/"),"File is outside attachment storage");
    else {
      require(QDir().mkpath(directory),"Cannot create attachment directory");
      QFile::setPermissions(directory,QFile::ReadOwner|QFile::WriteOwner|QFile::ExeOwner);
      path=directory+"/transfer-"+id();
    }
    if(!m_transfer) {
      m_transfer=new StorageTransfer(this);
      connect(m_transfer,&StorageTransfer::completed,this,[this](const QJsonObject &result){
        if(!result["error"].toString().isEmpty()) return;
        const bool upload=result["action"].toString()=="upload";
        const auto path=result["path"].toString();
        try {
          if(upload) query(m_db,"UPDATE attachments SET cid=?,sha256=? WHERE id=? AND post=''",
            {result["cid"].toString(),result["sha256"].toString(),result["id"].toString()});
          else {
            const auto imported=attachment({{"op","attachmentImport"},{"file",QUrl::fromLocalFile(path).toString()}})["attachment"].toObject()["id"].toString();
            require(m_db.transaction(),"Cannot save attachment download");
            try {
              query(m_db,"UPDATE attachments SET path=(SELECT path FROM attachments WHERE id=?),preview=(SELECT preview FROM attachments WHERE id=?) WHERE id=?",{imported,imported,result["id"].toString()});
              query(m_db,"DELETE FROM attachments WHERE id=?",{imported});
              require(m_db.commit(),"Cannot commit attachment download");
            } catch(...) {m_db.rollback();throw;}
            QFile::remove(path);
          }
          emit changed();
        } catch(const std::exception &e) {
          if(!upload) QFile::remove(path);
          m_transfer->failCompletion(QString::fromUtf8(e.what()));
        }
      });
    }
    m_transfer->start(c["id"].toString(),file,setting("storageEndpoint"),path,upload);
    return {{"transfer",m_transfer->state()}};
  }
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
    const auto mime = attachmentMime(input.peek(65536));
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
    try { query(m_db,"INSERT INTO attachments (id,name,mime,bytes,path,preview,sha256) VALUES (?,?,?,?,?,?,?)",{aid,name,mime,bytes.size(),path,png,hash(bytes)}); }
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
#ifdef Q_OS_MACOS
    const QString opener = "/usr/bin/open";
#elif defined(Q_OS_WIN)
    const auto opener = QStandardPaths::findExecutable("explorer.exe");
#else
    const auto opener = QStandardPaths::findExecutable("xdg-open");
#endif
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
  require(pid == hash(bytes) && (p["v"].toInt() == 1 || p["v"].toInt() == 2),
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
  const auto files=p.value("attachments").toArray();
  if (p["v"].toInt()==2) {
    require(p["attachments"].isArray() && !files.isEmpty() && files.size()<=4,"Invalid attachment list");
    for (const auto &file : files) validateAttachmentManifest(file.toObject());
  } else require(!p.contains("attachments"),"Attachments require protocol v2");
  auto exists = query(m_db, "SELECT id FROM posts WHERE id=?", {pid});
  if (exists.next())
    return {{"duplicate", true}};
  require(m_db.transaction(),"Cannot begin received-post transaction");
  try {
  query(m_db,
        "INSERT INTO posts "
        "(id,thread,board,title,body,author,mode,pub,created,received,wire,"
        "status) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        {pid, thread, board, title, body, author, mode, pub, created, now(),
         wire, "received"});
    query(m_db,"UPDATE posts SET search_text=? WHERE id=?",{(title+" "+body).toCaseFolded(),pid});
    for(int index=0;index<files.size();++index) {
      auto file=files[index].toObject();
      query(m_db,"INSERT INTO attachments (id,post,name,mime,bytes,path,cid,sha256) VALUES (?,?,?,?,?,'',?,?)",
        {pid+"-"+QString::number(index),pid,file["name"].toString(),file["mime"].toString(),
         file["bytes"].toDouble(),file["cid"].toString(),file["sha256"].toString()});
    }
    require(m_db.commit(),"Cannot commit received post");
  } catch (...) { m_db.rollback(); throw; }

  emit changed();
  return {{"id", pid}, {"duplicate", false}};
}
QJsonObject ForumBackend::execute(const QJsonObject &c) {
  auto op = c["op"].toString();
  if (op == "postReference") {
    const auto prefix = c["reference"].toString().toLower();
    require(QRegularExpression("^[a-f0-9]{8,64}$").match(prefix).hasMatch(), "Invalid post reference");
    // Search the whole local archive, not just the currently loaded UI page.
    // Never guess when two hashes share the displayed prefix.
    auto matches = query(m_db, "SELECT id FROM posts WHERE id GLOB ? LIMIT 2", {prefix + "*"});
    if (!matches.next()) return {{"state", "missing"}};
    const auto id = matches.value(0).toString();
    if (matches.next()) return {{"state", "ambiguous"}};
    const auto post = postRecord(id);
    const auto thread = post["thread"].toString().isEmpty() ? post : postRecord(post["thread"].toString());
    return {{"state", "found"}, {"post", post},
            {"threadAvailable", !thread.isEmpty() && thread["thread"].toString().isEmpty() && thread["board"] == post["board"]}};
  }
  if(op=="postInfo") return {{"post",postRecord(c["id"].toString())}};
  if(op=="replyPage") {
    const auto reply=postRecord(c["id"].toString());
    require(!reply.isEmpty() && !reply["thread"].toString().isEmpty(),"Reply not found");
    return browse({{"view","thread"},{"thread",reply["thread"]},{"anchor",reply["id"]},{"limit",50}});
  }
  if (op.startsWith("attachment")) return attachment(c);
  if (op == "snapshot")
    return snapshot(c);
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
    if (c.contains("autoConnect")) {
      require(c["autoConnect"].isBool(), "Auto-connect must be true or false");
      setSetting("autoConnect", c["autoConnect"].toBool() ? "true" : "false");
    }
    if(c.contains("storageEndpoint")) {
      const auto endpoint=c["storageEndpoint"].toString().trimmed();
      require(endpoint.isEmpty() || StorageTransfer::validEndpoint(endpoint),"Use your local node URL: http://127.0.0.1:PORT/api/storage/v1");
      setSetting("storageEndpoint",endpoint);
    }

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
    if (c.contains("id")) {
      const auto id = c["id"].toString();
      require(!id.isEmpty(), "Missing post ID");
      query(m_db, "UPDATE posts SET status='queued',next_try=0,error='' WHERE "
                  "status='failed' AND id=?", {id});
    } else {
      query(m_db, "UPDATE posts SET status='queued',next_try=0,error='' WHERE "
                  "status='failed'");
    }
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
