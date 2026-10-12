QT += core gui quick qml sql
CONFIG += c++17
TEMPLATE = app
TARGET = forum-preview
HEADERS += ../backend/ForumBackend.h
SOURCES += main.cpp ../backend/ForumBackend.cpp
LIBS += -lcrypto
DEFINES += FORUM_QML_PATH=\\\"$$PWD/../forum/qml/Main.qml\\\"

QT += multimedia
HEADERS += $$PWD/../backend/VideoSession.h
SOURCES += $$PWD/../backend/VideoSession.cpp

include(../backend/storage.pri)
