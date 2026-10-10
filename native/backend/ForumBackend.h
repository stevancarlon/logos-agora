#pragma once
#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QSqlDatabase>
#include "VideoSession.h"

class ForumBackend : public QObject {
  Q_OBJECT
  Q_PLUGIN_METADATA(IID "org.logos.forum.backend/1.0" FILE
                        "../forum/metadata.json")
  Q_PROPERTY(QByteArray outboundPayload READ outboundPayload NOTIFY changed)
  Q_PROPERTY(QString lastError READ lastError NOTIFY changed)
public:
  explicit ForumBackend(QObject *parent = nullptr);
  ~ForumBackend() override;
  QByteArray outboundPayload() const { return m_outbound; }
  Q_INVOKABLE QString receiveBytes(const QByteArray &bytes);
  QString lastError() const { return m_error; }
  Q_INVOKABLE QString dispatch(const QString &request);
signals:
  void changed();

private:
  QSqlDatabase m_db;
  VideoSession *m_video = nullptr;
  QByteArray m_outbound;
  QString m_error;
  void initialize();
  QJsonObject execute(const QJsonObject &cmd);
  QJsonObject snapshot();
  QJsonObject attachment(const QJsonObject &cmd);
  QJsonObject post(const QJsonObject &cmd);
  QJsonObject receive(const QString &wire);
  QJsonObject identity(const QString &alias);
  QString setting(const QString &key, const QString &fallback = QString());
  void setSetting(const QString &key, const QString &value);
};
