# Set OPENSSL_ROOT_DIR on hosts where OpenSSL is not on the compiler's defaults.
OPENSSL_PREFIX = $$(OPENSSL_ROOT_DIR)
!isEmpty(OPENSSL_PREFIX) {
    INCLUDEPATH += $$quote($$OPENSSL_PREFIX/include)
    LIBS += -L$$quote($$OPENSSL_PREFIX/lib)
}
win32-msvc: LIBS += -llibcrypto
else: LIBS += -lcrypto
macx: CONFIG -= app_bundle
