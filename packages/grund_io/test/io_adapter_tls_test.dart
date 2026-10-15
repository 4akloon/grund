import 'dart:io' as io;

import 'package:grund/grund.dart';
import 'package:grund_io/grund_io.dart';
import 'package:test/test.dart';

/// A self-signed certificate for `localhost` and `127.0.0.1`, test only.
const certificate = 'test/fixtures/localhost_cert.pem';

/// The private key of [certificate].
const privateKey = 'test/fixtures/localhost_key.pem';

void main() {
  test('IoAdapter serves HTTPS with a security context', () async {
    final adapter = IoAdapter(
      securityContext: io.SecurityContext()
        ..useCertificateChain(certificate)
        ..usePrivateKey(privateKey),
    );
    await adapter.listen(
      (request) async => HttpResponse.text('secure'),
      address: io.InternetAddress.loopbackIPv4,
      port: 0,
    );
    addTearDown(adapter.close);
    final client = io.HttpClient(
      context: io.SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates(certificate),
    );
    addTearDown(client.close);

    final response = await (await client.getUrl(
      Uri.parse('https://localhost:${adapter.port}/'),
    )).close();

    expect(response.statusCode, 200);
    expect(await response.map(String.fromCharCodes).join(), 'secure');
  });
}
