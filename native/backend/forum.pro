QT += core sql
QT += gui
CONFIG += plugin c++17
TEMPLATE = lib
TARGET = forum_backend
DESTDIR = $$PWD/../forum
HEADERS += ForumBackend.h
SOURCES += ForumBackend.cpp
LIBS += -lcrypto


QMAKE_LFLAGS_RPATH =

QT += multimedia
HEADERS += $$PWD/VideoSession.h
SOURCES += $$PWD/VideoSession.cpp
