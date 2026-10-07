import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../l10n.dart';

Future<Uint8List?> cropPhoto(
  BuildContext context,
  Uint8List bytes, {
  double? aspect,
  int maxSide = 1024,
  int quality = 80,
}) {
  return Navigator.of(context).push<Uint8List>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => PhotoCropScreen(bytes: bytes, aspect: aspect, maxSide: maxSide, quality: quality),
  ));
}

class PhotoCropScreen extends StatefulWidget {
  final Uint8List bytes;
  final double? aspect;
  final int maxSide;
  final int quality;
  const PhotoCropScreen({
    super.key,
    required this.bytes,
    this.aspect,
    this.maxSide = 1024,
    this.quality = 80,
  });

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  ui.Image? _img;
  final TransformationController _ctrl = TransformationController();
  bool _busy = false;
  String? _error;

  double _freeAspect = 0;

  Size _frame = Size.zero;
  double _baseScale = 1;
  Size? _lastFrame;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final f = await codec.getNextFrame();
      if (mounted) setState(() => _img = f.image);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double get _aspect {
    if (widget.aspect != null) return widget.aspect!;
    if (_freeAspect > 0) return _freeAspect;
    final i = _img!;
    return i.width / i.height;
  }

  Future<void> _rotate() async {
    final src = _img;
    if (src == null || _busy) return;
    setState(() => _busy = true);
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.translate(src.height.toDouble(), 0);
    c.rotate(math.pi / 2);
    c.drawImage(src, Offset.zero, Paint()..filterQuality = FilterQuality.high);
    final out = await rec.endRecording().toImage(src.height, src.width);
    if (!mounted) return;
    setState(() {
      _img = out;
      _busy = false;
      _lastFrame = null;
    });
  }

  void _setAspect(double a) {
    setState(() {
      _freeAspect = a;
      _lastFrame = null;
    });
  }

  void _centerIfNeeded(Size frame, Size child) {
    if (_lastFrame == frame) return;
    _lastFrame = frame;
    final dx = (frame.width - child.width) / 2;
    final dy = (frame.height - child.height) / 2;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ctrl.value = Matrix4.translationValues(dx, dy, 0);
    });
  }

  Future<void> _confirm() async {
    final src = _img;
    if (src == null || _busy) return;
    setState(() => _busy = true);
    try {
      final m = _ctrl.value;
      final zoom = m.getMaxScaleOnAxis();
      final tx = m.getTranslation().x;
      final ty = m.getTranslation().y;
      final k = 1 / (zoom * _baseScale);
      var sx = -tx * k;
      var sy = -ty * k;
      var sw = _frame.width * k;
      var sh = _frame.height * k;
      sx = sx.clamp(0.0, src.width.toDouble()).toDouble();
      sy = sy.clamp(0.0, src.height.toDouble()).toDouble();
      sw = math.min(sw, src.width - sx);
      sh = math.min(sh, src.height - sy);

      final scaleOut = math.min(1.0, widget.maxSide / math.max(sw, sh));
      final ow = math.max(1, (sw * scaleOut).round());
      final oh = math.max(1, (sh * scaleOut).round());

      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      c.drawImageRect(
        src,
        Rect.fromLTWH(sx, sy, sw, sh),
        Rect.fromLTWH(0, 0, ow.toDouble(), oh.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final out = await rec.endRecording().toImage(ow, oh);
      final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw Exception('crop');
      final jpg = await compute(_encodeJpg, _Raw(data.buffer.asUint8List(), ow, oh, widget.quality));
      if (mounted) Navigator.of(context).pop(jpg);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('photo.error', {'error': e}))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final src = _img;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(tr('crop.title')),
        actions: [
          IconButton(
            tooltip: tr('crop.rotate'),
            icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
            onPressed: src == null || _busy ? null : _rotate,
          ),
          IconButton(
            tooltip: tr('crop.reset'),
            icon: const Icon(Icons.fit_screen_outlined),
            onPressed: src == null || _busy ? null : () => setState(() => _lastFrame = null),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: _error != null
                ? Center(
                    child: Text(tr('photo.error', {'error': _error}),
                        style: const TextStyle(color: Colors.white)))
                : src == null
                    ? const Center(child: CircularProgressIndicator())
                    : LayoutBuilder(builder: (context, box) => _editor(src, box)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(tr('crop.hint'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          if (widget.aspect == null && src != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
                _aspectChip(tr('crop.original'), 0),
                _aspectChip('4:3', 4 / 3),
                _aspectChip('3:4', 3 / 4),
                _aspectChip('1:1', 1),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: Text(tr('common.cancel')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: src == null || _busy ? null : _confirm,
                  icon: _busy
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(tr('crop.use')),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _aspectChip(String label, double a) {
    final sel = _freeAspect == a;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      onSelected: _busy ? null : (_) => _setAspect(a),
    );
  }

  Widget _editor(ui.Image src, BoxConstraints box) {
    const pad = 20.0;
    final maxW = box.maxWidth - pad * 2;
    final maxH = box.maxHeight - pad * 2;
    final a = _aspect;
    var fw = maxW;
    var fh = fw / a;
    if (fh > maxH) {
      fh = maxH;
      fw = fh * a;
    }
    final frame = Size(fw, fh);
    final base = math.max(fw / src.width, fh / src.height);
    final child = Size(src.width * base, src.height * base);
    _frame = frame;
    _baseScale = base;
    _centerIfNeeded(frame, child);

    return Center(
      child: Stack(clipBehavior: Clip.none, children: [
        SizedBox(
          width: fw,
          height: fh,
          child: ClipRect(
            child: InteractiveViewer(
              transformationController: _ctrl,
              constrained: false,
              minScale: 1,
              maxScale: 8,
              boundaryMargin: EdgeInsets.zero,
              child: SizedBox(
                width: child.width,
                height: child.height,
                child: RawImage(image: src, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _GridPainter()),
          ),
        ),
      ]),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final line = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    canvas.drawRect(Offset.zero & size, border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Raw {
  final Uint8List rgba;
  final int w;
  final int h;
  final int quality;
  _Raw(this.rgba, this.w, this.h, this.quality);
}

Uint8List _encodeJpg(_Raw r) {
  final im = img.Image.fromBytes(
    width: r.w,
    height: r.h,
    bytes: r.rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(im, quality: r.quality);
}
