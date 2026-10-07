import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';
import 'common.dart';

const String _qrPrefix = 'familyrecipes:join:';
const String _joinUrl = 'https://viperonedodge.github.io/FamilyRecipes/join.html';

String groupQrData(String code) => '$_joinUrl?code=$code';

String? codeFromQr(String? raw) {
  if (raw == null) return null;
  var t = raw.trim();
  final uri = Uri.tryParse(t);
  if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
    if (!uri.host.endsWith('github.io') || !uri.path.endsWith('/join.html')) return null;
    t = uri.queryParameters['code'] ?? '';
  }
  if (t.toLowerCase().startsWith(_qrPrefix)) t = t.substring(_qrPrefix.length);
  t = t.toUpperCase().replaceAll(RegExp(r'\s'), '');
  return RegExp(r'^[A-Z0-9]{6,32}$').hasMatch(t) ? t : null;
}

class GroupQr extends StatelessWidget {
  final String code;
  final double size;
  const GroupQr({super.key, required this.code, this.size = 220});

  @override
  Widget build(BuildContext context) {
    final logo = size * 0.24;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(14),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          QrImageView(
            data: groupQrData(code),
            size: size,
            padding: EdgeInsets.zero,
            backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.H,
            eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
            dataModuleStyle:
                const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
          ),
          Container(
            width: logo + 8,
            height: logo + 8,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            padding: const EdgeInsets.all(4),
            child: Image.asset('assets/gian_trip_logo.png', width: logo, height: logo),
          ),
        ]),
      ),
    );
  }
}

class GroupQrCard extends StatefulWidget {
  final String code;
  final String groupName;
  const GroupQrCard({super.key, required this.code, required this.groupName});

  @override
  State<GroupQrCard> createState() => _GroupQrCardState();
}

class _GroupQrCardState extends State<GroupQrCard> {
  final GlobalKey _key = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 4);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/FamilyRecipes-${widget.code}.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: tr('family.qrShareText', {'name': widget.groupName, 'code': widget.code}),
      ));
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Center(
        child: RepaintBoundary(
          key: _key,
          child: GroupQr(code: widget.code),
        ),
      ),
      const SizedBox(height: 8),
      Center(
        child: OutlinedButton.icon(
          onPressed: _busy ? null : _share,
          icon: const Icon(Icons.share),
          label: Text(tr('family.qrShare')),
        ),
      ),
    ]);
  }
}

Future<String?> scanGroupQr(BuildContext context) =>
    Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _QrScanScreen()));

Future<String?> groupQrFromImage(BuildContext context) async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return null;
  final controller = MobileScannerController(autoStart: false, formats: const [BarcodeFormat.qrCode]);
  try {
    final capture = await controller.analyzeImage(picked.path, formats: const [BarcodeFormat.qrCode]);
    for (final b in capture?.barcodes ?? const <Barcode>[]) {
      final code = codeFromQr(b.rawValue);
      if (code != null) return code;
    }
  } catch (_) {
  } finally {
    await controller.dispose();
  }
  if (context.mounted) showSnack(context, tr('family.qrNotFound'));
  return null;
}

class _QrScanScreen extends StatefulWidget {
  const _QrScanScreen();

  @override
  State<_QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<_QrScanScreen> {
  final MobileScannerController _controller =
      MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final code = codeFromQr(b.rawValue);
      if (code != null) {
        _done = true;
        Navigator.of(context).pop(code);
        return;
      }
    }
  }

  Future<void> _fromImage() async {
    final code = await groupQrFromImage(context);
    if (code != null && mounted && !_done) {
      _done = true;
      Navigator.of(context).pop(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('family.scanQr')),
        actions: [
          IconButton(
            tooltip: tr('family.qrFromImage'),
            icon: const Icon(Icons.image_outlined),
            onPressed: _fromImage,
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(tr('family.cameraDenied'),
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ]),
    );
  }
}
