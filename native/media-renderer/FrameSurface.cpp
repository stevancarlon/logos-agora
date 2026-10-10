#include <QQuickPaintedItem>
#include <QQmlExtensionPlugin>
#include <QPainter>
#include <QJsonDocument>
#include <QJsonObject>
class FrameSurface : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(QString packet WRITE setPacket READ packet NOTIFY packetChanged)
    Q_PROPERTY(int framesPresented READ framesPresented NOTIFY packetChanged)
    QImage image;
    QString m_packet;
    int m_frames = 0;
    bool m_logged = false;
public:
    using QQuickPaintedItem::QQuickPaintedItem;
    QString packet() const { return m_packet; }
    int framesPresented() const { return m_frames; }
    void setPacket(const QString &packet) {
        if(packet.isEmpty() || packet == m_packet) return;
        const auto p=QJsonDocument::fromJson(packet.toUtf8()).object();
        const int w=p["width"].toInt(), h=p["height"].toInt();
        if(w<1 || h<1 || w>640 || h>640 || packet.size()>2300000) return;
        const auto rgba=QByteArray::fromBase64(p["rgba"].toString().toLatin1());
        if(rgba.size()!=w*h*4) return;
        image=QImage(reinterpret_cast<const uchar*>(rgba.constData()),w,h,w*4,QImage::Format_RGBA8888).copy();
        m_packet=packet; ++m_frames; update(); emit packetChanged();
    }
    void paint(QPainter *p) override {
        if(image.isNull()) return;
        if(!m_logged) { qInfo("AGORA_VIDEO_RENDERED_FIRST_FRAME"); m_logged=true; }
        const auto size=image.size().scaled(boundingRect().size().toSize(),Qt::KeepAspectRatio);
        p->drawImage(QRectF((width()-size.width())/2,(height()-size.height())/2,size.width(),size.height()),image);
    }
signals: void packetChanged();
};
class MediaRendererPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override { qmlRegisterType<FrameSurface>(uri,1,0,"FrameSurface"); }
};
#include "FrameSurface.moc"
