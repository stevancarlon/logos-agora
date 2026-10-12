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
  // Qt's bundled database also identifies WebM as generic Matroska. Read the
  // bounded EBML header's DocType element; a filename or stray "webm" is not proof.
  if (header.startsWith(QByteArray::fromHex("1a45dfa3")) && !detected.startsWith("audio/")) {
    qsizetype cursor = 4;
    auto readVint = [&](qsizetype limit, int maximum, bool keepMarker, quint64 &value) {
      if (cursor >= limit) return false;
      const auto first = static_cast<unsigned char>(header[cursor++]);
      unsigned mask = 0x80;
      int length = 1;
      while (mask && !(first & mask)) { mask >>= 1; ++length; }
      if (!mask || length > maximum || length - 1 > limit - cursor) return false;
      value = keepMarker ? first : (first & (mask - 1));
      for (int i = 1; i < length; ++i)
        value = (value << 8) | static_cast<unsigned char>(header[cursor++]);
      return keepMarker || value != ((quint64(1) << (7 * length)) - 1);
    };
    quint64 length = 0;
    if (readVint(header.size(), 8, false, length) && length <= quint64(header.size() - cursor)) {
      const auto end = cursor + qsizetype(length);
      while (cursor < end) {
        quint64 element = 0, bytes = 0;
        if (!readVint(end, 4, true, element) || !readVint(end, 8, false, bytes) ||
            bytes > quint64(end - cursor)) break;
        if (element == 0x4282) {
          if (bytes == 4 && header.mid(cursor, 4) == "webm") return "video/webm";
          break;
        }
        cursor += qsizetype(bytes);
      }
    }
  }
  return detected;
}
