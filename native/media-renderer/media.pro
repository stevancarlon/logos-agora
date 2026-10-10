QT += core gui quick qml
CONFIG += plugin c++17
TEMPLATE = lib
TARGET = agoramedia
DESTDIR = $$OUT_PWD/qml/Agora/Media
SOURCES += FrameSurface.cpp
QMAKE_POST_LINK += $$QMAKE_COPY $$shell_path($$PWD/qmldir) $$shell_path($$DESTDIR/qmldir)
