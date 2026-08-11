// Relay TLS pinning.
//
// The self-hosted relay (118.145.119.50) terminates TLS at Caddy with a
// **self-signed IP certificate** (CN=118.145.119.50, valid until 2028-11-12).
// A domain certificate (Let's Encrypt via DuckDNS) is DPI-blocked on the
// user's network, so the IP cert is the only encrypted path — and the app
// must explicitly trust it.
//
// Trust model: **certificate pinning** — the SHA-256 fingerprint of the
// exact certificate is embedded below, and the `badCertificateCallback`
// only accepts a connection when:
//   1. the peer host is the pinned relay host, AND
//   2. the presented certificate's SHA-256 matches the pin.
//
// Every other host / certificate keeps the platform-default strict
// validation (callback returns false → reject). This is NOT a blanket
// `return true` bypass — a MITM would need the actual private key.
//
// ⚠️ When the relay certificate is renewed or replaced, update
// `kPinnedRelayCertSha256` to the new fingerprint (`openssl x509 -in cert.pem
// -noout -fingerprint -sha256`, lowercase hex, no colons). The unit test
// `relay_tls_test.dart` embeds the real cert DER as a canary and will fail
// loudly when the cert changes.

import 'dart:io';

import 'package:crypto/crypto.dart';

/// SHA-256 fingerprint of the relay TLS certificate (lowercase hex).
const String kPinnedRelayCertSha256 =
    '0b720d060ffb2ce03b4199f096e1e7957d98a07014bd73fc584d036be7394049';

/// Host the pin applies to — the self-hosted relay IP.
const String kPinnedRelayHost = '118.145.119.50';

/// Pure decision: is this certificate allowed for this host?
///
/// Extracted from the callback so the pin logic is unit-testable without
/// constructing a real [X509Certificate] (which dart:io does not expose).
bool relayCertAllowed({required String host, required List<int> certDer}) {
  if (host != kPinnedRelayHost) return false;
  return sha256.convert(certDer).toString() == kPinnedRelayCertSha256;
}

/// Returns an [HttpClient] that trusts the pinned relay certificate and
/// nothing else beyond the platform defaults.
///
/// Use as `customClient` for `IOWebSocketChannel.connect` and as the
/// `createHttpClient` factory of Dio's `IOHttpClientAdapter` so both the
/// WebSocket transport and the mesh REST calls accept the self-signed IP
/// cert — and only that cert.
HttpClient relayPinnedHttpClient() {
  final client = HttpClient();
  client.badCertificateCallback = (X509Certificate cert, String host, int _) {
    return relayCertAllowed(host: host, certDer: cert.der);
  };
  return client;
}
