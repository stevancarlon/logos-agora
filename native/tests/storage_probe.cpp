#include "../backend/ForumBackend.h"
#include <QCoreApplication>
#include <QJsonDocument>
#include <QTemporaryDir>
#include <QTimer>
#include <QEventLoop>
#include <QUrl>
#include <QFile>
#include <QCryptographicHash>
#include <iostream>
#include <stdexcept>

static QJsonObject call(ForumBackend &backend,const QJsonObject &request) {
  auto result=QJsonDocument::fromJson(backend.dispatch(QString::fromUtf8(QJsonDocument(request).toJson())).toUtf8()).object();
  if(!result["ok"].toBool()) throw std::runtime_error(result["error"].toString().toStdString());
  return result;
}
static void waitTransfer(ForumBackend &backend) {
  QEventLoop loop; QTimer poll,timeout;
  QObject::connect(&poll,&QTimer::timeout,&loop,[&]{
    const auto state=call(backend,{{"op","attachmentTransfer"}})["transfer"].toObject();
    if(state["status"]!="running") loop.quit();
  });
  QObject::connect(&timeout,&QTimer::timeout,&loop,&QEventLoop::quit);
  poll.start(100);timeout.start(190000);loop.exec();
  const auto state=call(backend,{{"op","attachmentTransfer"}})["transfer"].toObject();
  if(state["status"]!="complete") throw std::runtime_error(state["error"].toString("Transfer incomplete").toStdString());
}
int main(int argc,char **argv) {
  QCoreApplication app(argc,argv);
  if(argc!=4) {std::cerr<<"usage: storage-probe PROVIDER_API CONSUMER_API FILE\n";return 2;}
  QTemporaryDir work;
  try {
    qputenv("LOGOS_FORUM_DATA_DIR",(work.path()+"/author").toUtf8());ForumBackend author;
    call(author,{{"op","settings"},{"storageEndpoint",argv[1]}});
    const auto file=call(author,{{"op","attachmentImport"},{"file",QUrl::fromLocalFile(QString::fromLocal8Bit(argv[3])).toString()}})["attachment"].toObject();
    call(author,{{"op","attachmentUpload"},{"id",file["id"]}});waitTransfer(author);
    const auto posted=call(author,{{"op","post"},{"board","general"},{"title","Isolated Storage acceptance"},{"body","Synthetic attachment test"},{"attachments",QJsonArray{file["id"]}}});
    const auto wire=call(author,{{"op","wire"},{"id",posted["id"]}})["wire"].toString();
    qputenv("LOGOS_FORUM_DATA_DIR",(work.path()+"/reader").toUtf8());ForumBackend reader;
    call(reader,{{"op","settings"},{"storageEndpoint",argv[2]}});
    call(reader,{{"op","receive"},{"wire",wire}});
    const auto remote=call(reader,{{"op","snapshot"}})["posts"].toArray()[0].toObject()["attachments"].toArray()[0].toObject();
    call(reader,{{"op","attachmentFetch"},{"id",remote["id"]}});waitTransfer(reader);
    const auto path=work.path()+"/exported";
    call(reader,{{"op","attachmentExport"},{"id",remote["id"]},{"file",QUrl::fromLocalFile(path).toString()}});
    QFile original(QString::fromLocal8Bit(argv[3])),downloaded(path);
    if(!original.open(QIODevice::ReadOnly)||!downloaded.open(QIODevice::ReadOnly)||original.readAll()!=downloaded.readAll())
      throw std::runtime_error("Export differs from uploaded original");
    std::cout<<QJsonDocument(QJsonObject{{"passed",true},{"cid",remote["cid"]},{"sha256",remote["sha256"]},
      {"bytes",remote["bytes"]},{"mime",remote["mime"]},{"crossMachineVerified",false}}).toJson().constData();
    return 0;
  } catch(const std::exception &error) {std::cerr<<error.what()<<"\n";return 1;}
}
