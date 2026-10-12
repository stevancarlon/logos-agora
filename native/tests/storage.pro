QT += core gui sql multimedia
CONFIG += console c++17
TEMPLATE = app
TARGET = storage-probe
HEADERS += ../backend/ForumBackend.h ../backend/VideoSession.h
SOURCES += storage_probe.cpp ../backend/ForumBackend.cpp ../backend/VideoSession.cpp
LIBS += -lcrypto
include(../backend/storage.pri)
