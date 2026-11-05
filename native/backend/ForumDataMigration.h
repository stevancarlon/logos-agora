#pragma once

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLockFile>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QTemporaryDir>
#include <QUuid>
#include <stdexcept>

// Only the default Basecamp profile is migrated. Explicit test/custom data
// directories remain exactly where their owner put them.
namespace AgoraData {
inline void require(bool ok, const QString &detail) {
    if (!ok)
        throw std::runtime_error(("Agora data migration: " + detail +
            ". Original data has been kept in module_data/logos_forum.").toStdString());
}

class Database {
public:
    QSqlDatabase db;
    Database(const QString &path, bool readOnly = false) {
        db = QSqlDatabase::addDatabase("QSQLITE", "agora-migration-" + QUuid::createUuid().toString());
        db.setDatabaseName(path);
        if (readOnly) db.setConnectOptions("QSQLITE_OPEN_READONLY");
    }
    ~Database() {
        const auto name = db.connectionName();
        db.close();
        db = QSqlDatabase();
        QSqlDatabase::removeDatabase(name);
    }
    void open() { require(db.open(), "cannot open migration database: " + db.lastError().text()); }
    QSqlQuery run(const QString &sql, const QVariantList &args = {}) {
        QSqlQuery q(db);
        require(q.prepare(sql), q.lastError().text());
        for (const auto &arg : args) q.addBindValue(arg);
        require(q.exec(), q.lastError().text());
        return q;
    }
};

inline void migrate(const QString &moduleData) {
    const auto legacy = moduleData + "/logos_forum";
    const auto destination = moduleData + "/agora_forum";
    require(!QFileInfo(destination).isSymLink(), "destination is a symbolic link");
    // Never merge into or overwrite an existing Agora database.
    if (QFileInfo::exists(destination + "/forum.sqlite")) return;
    if (!QFileInfo::exists(legacy + "/forum.sqlite")) return;

    QLockFile lock(moduleData + "/.agora-migration.lock");
    require(lock.tryLock(5000), "another migration is running; close Agora and retry");
    if (QFileInfo::exists(destination + "/forum.sqlite")) return;
    require(!QFileInfo(legacy).isSymLink() && !QFileInfo(legacy + "/forum.sqlite").isSymLink(),
            "legacy data is a symbolic link; restore a regular Agora backup first");
    require(!QFileInfo::exists(destination) ||
            (QFileInfo(destination).isDir() && QDir(destination).isEmpty()),
            "new data directory is not empty; inspect it before retrying");

    QTemporaryDir stage(moduleData + "/.agora-migration-XXXXXX");
    require(stage.isValid(), "cannot stage the migration");
    require(QFile::setPermissions(stage.path(), QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner),
            "cannot protect staged data");
    const auto database = stage.path() + "/forum.sqlite";
    {
        Database source(legacy + "/forum.sqlite", true);
        source.open();
        source.run("PRAGMA busy_timeout=5000");
        // Recognize Agora, not another forum's database. Older Agora versions
        // can lack newer optional columns; initialize() upgrades the copy.
        source.run("SELECT id,alias,secret,public,created FROM identities LIMIT 0");
        source.run("SELECT id,thread,wire,status,request,attempts,next_try FROM posts LIMIT 0");
        source.run("SELECT key,value FROM settings LIMIT 0");
        source.run("SELECT id,body FROM drafts LIMIT 0");
        source.run("SELECT id FROM bookmarks LIMIT 0");
        source.run("SELECT id,path FROM attachments LIMIT 0");
        // SQLite produces a consistent snapshot including committed WAL pages.
        // Copying only forum.sqlite would silently lose recent posts and keys.
        source.run("VACUUM INTO ?", {database});
    }
    require(QFile::setPermissions(database, QFile::ReadOwner | QFile::WriteOwner),
            "cannot protect the migrated database");
    {
        Database copy(database);
        copy.open();
        auto integrity = copy.run("PRAGMA quick_check");
        require(integrity.next() && integrity.value(0).toString() == "ok", "database integrity check failed");
        integrity.finish();
        auto files = copy.run("SELECT id,path FROM attachments WHERE path<>''");
        const auto oldFiles = QFileInfo(legacy + "/attachments").canonicalFilePath();
        require(copy.db.transaction(), "cannot begin attachment migration");
        while (files.next()) {
            const auto attachment = QFileInfo(files.value(1).toString());
            require(!oldFiles.isEmpty() && !attachment.isSymLink() && attachment.isFile() &&
                    QFileInfo(attachment.canonicalFilePath()).absolutePath() == oldFiles,
                    "an attachment is missing or outside Agora storage; restore it before retrying");
            const auto folder = stage.path() + "/attachments";
            require(QDir().mkpath(folder), "cannot create attachment directory");
            require(QFile::setPermissions(folder, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner),
                    "cannot protect attachments");
            const auto target = folder + "/" + attachment.fileName();
            if (!QFileInfo::exists(target))
                require(QFile::copy(attachment.absoluteFilePath(), target), "cannot copy attachment");
            require(QFile::setPermissions(target, QFile::ReadOwner | QFile::WriteOwner),
                    "cannot protect attachment");
            copy.run("UPDATE attachments SET path=? WHERE id=?",
                     {destination + "/attachments/" + attachment.fileName(), files.value(0)});
        }
        files.finish();
        require(copy.db.commit(), "cannot commit attachment migration");
    }
    // Install the complete private directory atomically. A failure leaves no
    // partial database that a later startup could mistake for a fresh profile.
    if (QFileInfo::exists(destination)) require(QDir().rmdir(destination), "cannot replace empty destination");
    require(QDir().rename(stage.path(), destination), "cannot install migrated data");
    stage.setAutoRemove(false);
}
} // namespace AgoraData
