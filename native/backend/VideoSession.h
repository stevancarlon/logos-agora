#pragma once
#include <QObject>
#include <QMediaPlayer>
#include <QAudioOutput>
#include <QVideoSink>
#include <QElapsedTimer>
#include <QJsonObject>
class VideoSession : public QObject {
  Q_OBJECT
  QMediaPlayer m_player;
  QAudioOutput m_audio;
  QVideoSink m_sink;
  QElapsedTimer m_pacing;
  QString m_id, m_frame;
  int m_generation=0;
public:
  explicit VideoSession(QObject *parent=nullptr);
  ~VideoSession() override;
  void play(const QString &id, const QString &path);
  QJsonObject command(const QJsonObject &c);
};
