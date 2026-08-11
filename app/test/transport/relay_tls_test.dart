import 'dart:convert';

import 'package:app/data/transport/relay_tls.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// DER (base64) of the actual relay TLS certificate
/// (CN=118.145.119.50, self-signed, valid until 2028-11-12).
/// Serves double duty: the `true` branch of the pin check AND a
/// canary — if the server cert changes (renewal/replacement), this
/// fixture stops hashing to the pin and the test fails loudly,
/// reminding us to re-pin.
const _relayCertDerB64 =
    'MIIDJDCCAgygAwIBAgIUPpa3PNLKW6TraJWl+vKfQxo89lEwDQYJKoZIhvcNAQELBQAwGTEXMBUGA1UEAwwOMTE4LjE0NS4xMTkuNTAwHhcNMjYwODEwMTY1OTAzWhcNMjgxMTEyMTY1OTAzWjAZMRcwFQYDVQQDDA4xMTguMTQ1LjExOS41MDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKRJSa+k1YN39KhPXAiDd07MD9fvcupU3qqPVPVSzCO/XvcjN4RVOJshtA70vrir3xj2m28cGbYSkOTOxmy/YYc+hAHhKckrWsGS+Yxoo6ufS3gLytluYZUuKCLFPd1rYpnMfNWmFakSYZNWzqnDr3XQtF6WyIdNzO4L7gQYAav8cSTPCPH0H5zvFUjSrEGaozc7G5VZi88GsznaEzo9KAVJQq3OBSd8Q7ONdTWvdiHn2hqjkAyFptuTJj76Sd5Rgwog2z8DZwQ195dE0VAG+bUu3/5IqjT820HhdNeoOLKT1NWPLZN8sJ1r7+Z/9GeLZRpRSUSEWbXnoHteANRA0VUCAwEAAaNkMGIwHQYDVR0OBBYEFFV2WBsmob4xsGe6ILv4dUzg3VwcMB8GA1UdIwQYMBaAFFV2WBsmob4xsGe6ILv4dUzg3VwcMA8GA1UdEwEB/wQFMAMBAf8wDwYDVR0RBAgwBocEdpF3MjANBgkqhkiG9w0BAQsFAAOCAQEANooga7CF4u4x2T3rJhgB6HThcdeMwCgJcSIDIQB57BcE6oGTKMsnDZtdaxZE/M5ojhBuqOdwFlUYIosBLdoiwPf4adbBS+cQf4j+V7HNDF2TyeVFFTmyKNjeNkeBQyPphEaPzgZiPcA40MvFRIXZav6OVuZqvCZoEqRFmW9kzT7W0oqwPphcStOknjClm0Aq+aC4z8i4uv3RFaojWtJAU7gjATLkmsnc6vMHpmO9MgNSpudU0xjj22BIoBmuIQs5vRByyf5tJie2w98sraT6HfsopdZi/u6FCmyuwwr8ky6B8vr49cbPOsX1oCIINQGMMU0jclZDcHJq4UoTk8bbRA==';

void main() {
  group('relay_tls pin', () {
    test('pin constant matches the embedded relay certificate', () {
      final der = base64.decode(_relayCertDerB64);
      expect(
        sha256.convert(der).toString(),
        kPinnedRelayCertSha256,
        reason: 'Cert renewal? Update kPinnedRelayCertSha256 and the fixture.',
      );
    });

    test('accepts only the pinned host + pinned cert', () {
      final der = base64.decode(_relayCertDerB64);

      // Pinned host with the real cert → allowed.
      expect(relayCertAllowed(host: kPinnedRelayHost, certDer: der), isTrue);

      // Wrong host, even with the real cert → rejected.
      expect(
        relayCertAllowed(host: 'relay-rp1.jacobmoura.work', certDer: der),
        isFalse,
      );
      expect(relayCertAllowed(host: '118.145.119.51', certDer: der), isFalse);

      // Pinned host with any other cert → rejected.
      expect(
        relayCertAllowed(
          host: kPinnedRelayHost,
          certDer: utf8.encode('not a certificate'),
        ),
        isFalse,
      );
      expect(relayCertAllowed(host: kPinnedRelayHost, certDer: const []), isFalse);
    });

    test('relayPinnedHttpClient builds a working HttpClient', () {
      // badCertificateCallback is setter-only on dart:io HttpClient —
      // the factory wiring is verified implicitly by the pure-function
      // tests above; here we just assert construction/close works.
      final client = relayPinnedHttpClient();
      client.close(force: true);
    });
  });
}
