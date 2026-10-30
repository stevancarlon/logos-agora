#include "AttachmentMime.h"
#include "StorageTransfer.h"
#include <QCryptographicHash>
#include <QFileInfo>
#include <QImageReader>
#include <QMimeDatabase>
#include <QRegularExpression>
#include <stdexcept>

bool StorageTransfer::validEndpoint(const QString &endpoint) {
  const QUrl url(endpoint);
  return url.isValid() && url.scheme()=="http" &&
    (url.host()=="127.0.0.1" || url.host()=="::1") &&
    url.port()>0 && url.userInfo().isEmpty() && !url.hasQuery() && !url.hasFragment() &&
    url.path()=="/api/storage/v1";
}
StorageTransfer::StorageTransfer(QObject *parent):QObject(parent),m_network(this) {
  m_timeout.setSingleShot(true);
  connect(&m_timeout,&QTimer::timeout,this,[this]{m_failure="Storage transfer timed out";cancel();});
}
StorageTransfer::~StorageTransfer() {
  if(m_reply) {m_reply->disconnect(this);m_reply->abort();}
  m_file.close();
  if(!m_upload && m_state["status"]=="running") QFile::remove(m_file.fileName());
}
void StorageTransfer::cancel() {
  if(m_reply) {
    if(m_failure.isEmpty()) m_failure="Storage transfer cancelled";
    m_reply->abort();
  }
}
void StorageTransfer::drain() {
  if(!m_reply || m_upload || !m_reply->isOpen()) return;
  const auto bytes=m_reply->readAll();
  if(!m_failure.isEmpty()) return;
  m_received+=bytes.size();
  if(m_received>m_expected || m_file.write(bytes)!=bytes.size()) {
    m_failure=m_received>m_expected ? "Attachment exceeds signed size" : "Cannot save downloaded attachment";
    cancel();
  }
}
void StorageTransfer::finish(QJsonObject result,QNetworkReply *reply) {
  m_timeout.stop();
  m_state["status"]=m_failure.isEmpty()?"complete":"failed";
  m_state["error"]=m_failure;
  result["error"]=m_failure;
  m_reply=nullptr; reply->deleteLater();
  emit completed(result);
}
void StorageTransfer::announce(QJsonObject result,const QString &endpoint) {
  // Re-uploading an existing CID can skip Storage's onBlockStored callback.
  // Explicitly refresh its provider announcement, including after a retry.
  QNetworkRequest request(QUrl(endpoint+"/data/"+result["cid"].toString()+"/advertise?advertise=true"));
  request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,QNetworkRequest::ManualRedirectPolicy);
  request.setTransferTimeout(30000);
  request.setHeader(QNetworkRequest::ContentTypeHeader,"application/octet-stream");
  auto reply=m_network.post(request,QByteArray());
  m_reply=reply;
  reply->setReadBufferSize(512);
  m_response.clear();
  connect(reply,&QNetworkReply::readyRead,this,[this]{
    m_response+=m_reply->readAll();
    if(m_response.size()>512) {m_failure="Invalid Storage announcement response";cancel();}
  });
  connect(reply,&QNetworkReply::finished,this,[this,reply,result]{
    if(m_failure.isEmpty() && (reply->error()!=QNetworkReply::NoError ||
        reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt()!=200))
      m_failure="Storage could not announce the attachment. Retry uploading.";
    finish(result,reply);
  });
}
void StorageTransfer::start(const QString &id,const QJsonObject &file,const QString &endpoint,
                            const QString &path,bool upload) {
  if(m_reply) throw std::runtime_error("Another attachment transfer is in progress");
  if(!validEndpoint(endpoint)) throw std::runtime_error("Configure your local Logos Storage endpoint first");
  m_upload=upload; m_received=0; m_response.clear(); m_failure.clear();
  m_expected=qint64(file["bytes"].toDouble());
  if(m_expected<=0 || m_expected>64*1024*1024) throw std::runtime_error("Invalid attachment size");
  const auto cid=file["cid"].toString();
  if(!upload && !QRegularExpression("^[a-zA-Z0-9]{20,160}$").match(cid).hasMatch())
    throw std::runtime_error("Invalid Storage content ID");
  m_file.setFileName(path);
  if(!m_file.open(upload ? QIODevice::ReadOnly : QIODevice::WriteOnly|QIODevice::NewOnly))
    throw std::runtime_error("Cannot open attachment file");
  if(!upload) m_file.setPermissions(QFile::ReadOwner|QFile::WriteOwner);
  if(upload && m_file.size()!=m_expected) {m_file.close();throw std::runtime_error("Attachment size changed");}
  m_state={{"id",id},{"action",upload?"upload":"download"},{"status","running"},{"bytes",0},{"total",double(m_expected)}};
  QNetworkRequest request(QUrl(endpoint+(upload ? "/data" : "/data/"+cid+"/network/stream?advertise=false")));
  request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,QNetworkRequest::ManualRedirectPolicy);
  // Manifest and block-provider discovery can each take a cold lookup round.
  // Leave room for both; the independent overall deadline stays at 180 s.
  request.setTransferTimeout(upload ? 30000 : 150000);
  request.setHeader(QNetworkRequest::ContentTypeHeader,upload?file["mime"].toString():"application/octet-stream");
  m_reply=upload ? m_network.post(request,&m_file) : m_network.get(request);
  auto reply=m_reply.data();
  reply->setReadBufferSize(65536);
  connect(reply,&QNetworkReply::readyRead,this,[this]{
    if(m_upload) {
      m_response+=m_reply->readAll();
      if(m_response.size()>512) {m_failure="Invalid Storage response";cancel();}
    } else drain();
  });
  connect(reply,upload?&QNetworkReply::uploadProgress:&QNetworkReply::downloadProgress,this,
    [this](qint64 bytes,qint64){m_state["bytes"]=double(bytes);});
  connect(reply,&QNetworkReply::finished,this,[this,reply,file,path,id,upload,endpoint]{
    if(upload) m_response+=reply->readAll(); else drain();
    const auto code=reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if(m_failure.isEmpty() && reply->error()==QNetworkReply::OperationCanceledError)
      m_failure="Storage node did not respond in time. Check its peer connection and retry.";
    if(m_failure.isEmpty() && (reply->error()!=QNetworkReply::NoError || code!=200))
      m_failure="Logos Storage request failed (HTTP "+QString::number(code)+"): "+reply->errorString();
    m_file.close();
    QJsonObject result{{"id",id},{"action",upload?"upload":"download"},{"path",path}};
    if(m_failure.isEmpty() && upload) {
      const auto cid=QString::fromUtf8(m_response).trimmed();
      if(m_response.size()>512 || !QRegularExpression("^[a-zA-Z0-9]{20,160}$").match(cid).hasMatch()) m_failure="Invalid Storage content ID";
      else result["cid"]=cid;
    }
    if(m_failure.isEmpty()) {
      QFile bytes(path);
      if(!bytes.open(QIODevice::ReadOnly)) m_failure="Cannot verify attachment";
      else {
        QCryptographicHash hash(QCryptographicHash::Sha256); hash.addData(&bytes);
        const auto digest=QString::fromLatin1(hash.result().toHex());
        result["sha256"]=digest;
        if(bytes.size()!=m_expected || (!file["sha256"].toString().isEmpty() && digest!=file["sha256"].toString()))
          m_failure="Attachment does not match signed size/checksum";
        if(!upload && m_failure.isEmpty()) {
          bytes.seek(0);
          if(attachmentMime(bytes.peek(65536))!=file["mime"].toString()) m_failure="Attachment type does not match signed metadata";
          if(file["mime"].toString().startsWith("image/")) {
            QImageReader reader(&bytes);
            const auto size=reader.size();
            if(!size.isValid() || qint64(size.width())*size.height()>24000000) m_failure="Invalid or oversized image";
          }
        }
      }
    }
    if(!upload && !m_failure.isEmpty()) QFile::remove(path);
    if(upload && m_failure.isEmpty()) {
      reply->deleteLater();
      announce(result,endpoint);
    } else finish(result,reply);
  });
  m_timeout.start(180000);
}
