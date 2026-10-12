#pragma once
#include <QObject>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QNetworkReply>
#include <QFile>
#include <QTimer>

// A bounded client of the user's own local Logos Storage node, never a remote
// HTTP gateway. Network data availability remains the Storage node's job.
class StorageTransfer : public QObject {
  Q_OBJECT
public:
  explicit StorageTransfer(QObject *parent=nullptr);
  ~StorageTransfer() override;
  QJsonObject state() const { return m_state; }
  void failCompletion(const QString &error) { m_state["status"]="failed"; m_state["error"]=error; }
  void start(const QString &id, const QJsonObject &file, const QString &endpoint,
             const QString &path, bool upload);
  void cancel();
  static bool validEndpoint(const QString &endpoint);
signals:
  void completed(const QJsonObject &result);
private:
  QNetworkAccessManager m_network;
  QPointer<QNetworkReply> m_reply;
  QTimer m_timeout;
  QFile m_file;
  QJsonObject m_state;
  QByteArray m_response;
  QString m_failure;
  bool m_upload=false;
  qint64 m_expected=0, m_received=0;
  void drain();
};
