QT += core gui quick qml sql qmltest
CONFIG += c++17 testcase
TEMPLATE = app
TARGET = forum-ui-tests
HEADERS += ../backend/ForumBackend.h
SOURCES += ui_main.cpp ../backend/ForumBackend.cpp
include(../backend/crypto.pri)

QT += multimedia
HEADERS += $$PWD/../backend/VideoSession.h
SOURCES += $$PWD/../backend/VideoSession.cpp

include(../backend/storage.pri)
