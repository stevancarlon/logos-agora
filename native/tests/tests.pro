QT += core sql testlib
QT += gui
CONFIG += console c++17 testcase
TEMPLATE = app
TARGET = backend_tests
HEADERS += ../backend/ForumBackend.h
SOURCES += backend_tests.cpp ../backend/ForumBackend.cpp
LIBS += -lcrypto

QT += multimedia
HEADERS += $$PWD/../backend/VideoSession.h
SOURCES += $$PWD/../backend/VideoSession.cpp

include(../backend/storage.pri)
