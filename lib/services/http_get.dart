import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Attesa massima per collegarsi e per ogni pezzo della risposta.
const Duration httpTimeout = Duration(seconds: 15);

/// Scarica [url] con una GET; errore se la risposta non è 200.
/// Con [maxBytes] smette di leggere appena li supera (pagine enormi).
Future<Uint8List> httpGet(String url, {String? userAgent, Map<String, String> headers = const {}, int? maxBytes}) async {
  final client = HttpClient()..connectionTimeout = httpTimeout;
  if (userAgent != null) client.userAgent = userAgent;
  try {
    final req = await client.getUrl(Uri.parse(url)).timeout(httpTimeout);
    headers.forEach(req.headers.set);
    final res = await req.close().timeout(httpTimeout);
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    final b = BytesBuilder(copy: false);
    await for (final chunk in res.timeout(httpTimeout)) {
      b.add(chunk);
      if (maxBytes != null && b.length > maxBytes) break;
    }
    return b.takeBytes();
  } finally {
    client.close();
  }
}
