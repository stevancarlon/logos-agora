#pragma once
#include <QByteArray>
#include <QMimeDatabase>
#include <QtEndian>

// Qt's bundled MIME database calls ISO MP4 files QuickTime on some hosts.
// Canonicalize MP4 brands from the bounded ftyp box, never from a filename.
inline QString attachmentMime(const QByteArray &header) {
  const auto detected = QMimeDatabase().mimeTypeForData(header).name();
  if (header.size() >= 16 && header.mid(4, 4) == "ftyp" &&
      !detected.startsWith("audio/")) {
    const auto size = qFromBigEndian<quint32>(header.constData());
    if (size >= 16 && size <= quint32(header.size()) && size % 4 == 0) {
      const QList<QByteArray> brands{"isom", "iso2", "iso3", "iso4", "iso5",
                                    "iso6", "mp41", "mp42", "avc1", "M4V "};
      if (brands.contains(header.mid(8, 4))) return "video/mp4";
      for (quint32 offset = 16; offset < size; offset += 4)
        if (brands.contains(header.mid(offset, 4))) return "video/mp4";
    }
  }
  return detected;
}
