#include "VideoSession.h"
#include <QVideoFrame>
#include <QJsonDocument>
#include <QUrl>
#include <QImage>
VideoSession::VideoSession(QObject *parent):QObject(parent) {
  m_player.setAudioOutput(&m_audio); m_audio.setVolume(.7);
  m_player.setVideoSink(&m_sink); m_pacing.start();
  connect(&m_sink,&QVideoSink::videoFrameChanged,this,[this](const QVideoFrame &frame) {
    if(!frame.isValid() || (m_pacing.elapsed()<32 && m_player.isPlaying())) return;
    auto image=frame.toImage(); if(image.isNull()) return;
    if(image.width()>640 || image.height()>640) image=image.scaled(640,640,Qt::KeepAspectRatio,Qt::FastTransformation);
    image=image.convertToFormat(QImage::Format_RGBA8888);
    QByteArray bytes; bytes.reserve(image.width()*image.height()*4);
    for(int y=0;y<image.height();++y) bytes.append(reinterpret_cast<const char*>(image.constScanLine(y)),image.width()*4);
    m_frame=QString::fromUtf8(QJsonDocument(QJsonObject{{"width",image.width()},{"height",image.height()},{"rgba",QString::fromLatin1(bytes.toBase64())}}).toJson(QJsonDocument::Compact));
    ++m_generation; m_pacing.restart();
  });
}
VideoSession::~VideoSession() { m_player.stop(); m_player.setVideoSink(nullptr); m_player.setAudioOutput(nullptr); }
void VideoSession::play(const QString &id,const QString &path) {
  if(m_id!=id) {m_player.stop();m_id=id;m_frame.clear();++m_generation;m_player.setSource(QUrl::fromLocalFile(path));}
  m_player.play();
}
QJsonObject VideoSession::command(const QJsonObject &c) {
  const auto action=(c["id"].toString().isEmpty() || c["id"].toString()==m_id) ? c["action"].toString() : QString("state");
  if(action=="pause") m_player.pause();
  else if(action=="stop") {m_player.stop();m_id.clear();m_frame.clear();++m_generation;}
  else if(action=="seek" && m_player.isSeekable()) m_player.setPosition(qBound<qint64>(0,qint64(c["position"].toDouble()),m_player.duration()));
  else if(action=="volume") m_audio.setVolume(qBound(0.,c["volume"].toDouble(),1.));
  else if(action=="mute") m_audio.setMuted(c["muted"].toBool());
  QJsonObject state{{"id",m_id},{"position",double(m_player.position())},{"duration",double(m_player.duration())},
    {"playing",m_player.isPlaying()},{"seekable",m_player.isSeekable()},{"volume",m_audio.volume()},{"muted",m_audio.isMuted()},
    {"error",m_player.errorString()},{"generation",m_generation},{"hasVideo",m_player.hasVideo()}};
  if(c["generation"].toInt(-1)!=m_generation) state["frame"]=m_frame;
  return {{"video",state}};
}
