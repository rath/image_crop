part of image_crop;

const _kCropOverlayActiveOpacity = 0.3;
const _kCropOverlayInactiveOpacity = 0.5;
const _kCropMinFraction = 0.1;

enum _CropAction { none, moving, cropping, scaling }

class Crop extends StatefulWidget {
  final ImageProvider image;
  final double? aspectRatio;
  final double maximumScale;
  final bool alwaysShowGrid;
  final ImageErrorListener? onImageError;
  final Rect? defaultArea;

  const Crop({
    Key? key,
    required this.image,
    this.aspectRatio,
    this.maximumScale = 2.0,
    this.alwaysShowGrid = false,
    this.onImageError,
    this.defaultArea,
  })  : assert(image != null),
        assert(maximumScale != null),
        assert(alwaysShowGrid != null),
        super(key: key);

  Crop.file(
    File file, {
    Key? key,
    double scale = 1.0,
    this.aspectRatio,
    this.maximumScale = 2.0,
    this.alwaysShowGrid = false,
    this.onImageError,
    this.defaultArea,
  })  : image = FileImage(file, scale: scale),
        assert(maximumScale != null),
        assert(alwaysShowGrid != null),
        super(key: key);

  Crop.asset(
    String assetName, {
    Key? key,
    AssetBundle? bundle,
    String? package,
    this.aspectRatio,
    this.maximumScale = 2.0,
    this.alwaysShowGrid = false,
    this.onImageError,
    this.defaultArea,
  })  : image = AssetImage(assetName, bundle: bundle, package: package),
        assert(maximumScale != null),
        assert(alwaysShowGrid != null),
        super(key: key);

  @override
  State<StatefulWidget> createState() => CropState();

  static CropState? of(BuildContext context) {
    return context.findAncestorStateOfType<CropState>();
  }
}

class CropState extends State<Crop> with TickerProviderStateMixin, Drag {
  final _surfaceKey = GlobalKey();
  late AnimationController _activeController;
  late AnimationController _settleController;
  ImageStream? _imageStream;
  ui.Image? _image;
  double? _scale;
  double? _ratio;
  Rect? _view;
  Rect? _area;
  late Offset _lastFocalPoint;
  _CropAction? _action;
  double? _startScale;
  Rect? _startView;
  late Tween<Rect?> _viewTween;
  late Tween<double> _scaleTween;
  late ImageStreamListener _imageListener;

  double get scale => _area!.shortestSide / _scale!;

  Rect? get area {
    return _view!.isEmpty
        ? null
        : Rect.fromLTWH(
            _area!.left * _view!.width / _scale! - _view!.left,
            _area!.top * _view!.height / _scale! - _view!.top,
            _area!.width * _view!.width / _scale!,
            _area!.height * _view!.height / _scale!,
          );
  }

  bool get _isEnabled => !_view!.isEmpty && _image != null;

  // Saving the length for the widest area for different aspectRatio's
  final Map<double?, double> _maxAreaWidthMap = {};

  // Counting pointers(number of user fingers on screen)
  int pointers = 0;

  @override
  void initState() {
    super.initState();
    _area = Rect.zero;
    _view = Rect.zero;
    _scale = 1.0;
    _ratio = 1.0;
    _lastFocalPoint = Offset.zero;
    _action = _CropAction.none;
    _activeController = AnimationController(
      vsync: this,
      value: widget.alwaysShowGrid ? 1.0 : 0.0,
    )..addListener(() => setState(() {}));
    _settleController = AnimationController(vsync: this)
      ..addListener(_settleAnimationChanged);
  }

  @override
  void dispose() {
    _imageStream?.removeListener(_imageListener);
    _activeController.dispose();
    _settleController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _getImage();
  }

  @override
  void didUpdateWidget(Crop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) {
      _getImage();
    } else if (widget.aspectRatio != oldWidget.aspectRatio) {
      _area = _calculateDefaultArea(
        viewWidth: _view!.width,
        viewHeight: _view!.height,
        imageWidth: _image?.width,
        imageHeight: _image?.height,
      );
    }
    if (widget.alwaysShowGrid != oldWidget.alwaysShowGrid) {
      if (widget.alwaysShowGrid) {
        _activate();
      } else {
        _deactivate();
      }
    }
  }

  void _getImage({bool force = false}) {
    final oldImageStream = _imageStream;
    _imageStream = widget.image.resolve(createLocalImageConfiguration(context));
    if (_imageStream!.key != oldImageStream?.key || force) {
      oldImageStream?.removeListener(_imageListener);
      _imageListener =
          ImageStreamListener(_updateImage, onError: widget.onImageError);
      _imageStream!.addListener(_imageListener);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints.expand(),
      child: Listener(
        onPointerDown: (event) => pointers++,
        onPointerUp: (event) => pointers = 0,
        child: GestureDetector(
          key: _surfaceKey,
          behavior: HitTestBehavior.opaque,
          onScaleStart: _isEnabled ? _handleScaleStart : null,
          onScaleUpdate: _isEnabled ? _handleScaleUpdate : null,
          onScaleEnd: _isEnabled ? _handleScaleEnd : null,
          child: CustomPaint(
            foregroundPainter: _CropPainter(
              image: _image,
              ratio: _ratio,
              view: _view,
              area: _area,
              scale: _scale,
              active: _activeController.value,
              defaultArea: widget.defaultArea,
            ),
            child: _image != null && widget.defaultArea == null ? Container(color: Color(0xff000000)) : null,
          ),
        ),
      ),
    );
  }

  void _activate() {
    _activeController.animateTo(
      1.0,
      curve: Curves.fastOutSlowIn,
      duration: const Duration(milliseconds: 250),
    );
  }

  void _deactivate() {
    if (!widget.alwaysShowGrid) {
      _activeController.animateTo(
        0.0,
        curve: Curves.fastOutSlowIn,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  Size? get _boundaries => _surfaceKey.currentContext!.size;

  Offset _getLocalPoint(Offset point) {
    final RenderBox box = _surfaceKey.currentContext!.findRenderObject() as RenderBox;
    return box.globalToLocal(point);
  }

  void _settleAnimationChanged() {
    setState(() {
      _scale = _scaleTween.transform(_settleController.value);
      _view = _viewTween.transform(_settleController.value);
    });
  }

  Rect _calculateDefaultArea({
    int? imageWidth,
    int? imageHeight,
    double? viewWidth,
    double? viewHeight,
  }) {
    if (imageWidth == null || imageHeight == null) {
      return Rect.zero;
    }
    double height;
    double width;
    if ((widget.aspectRatio ?? 1.0) < 1) {
      height = 1.0;
      width =
          ((widget.aspectRatio ?? 1.0) * imageHeight * viewHeight! * height) /
              imageWidth /
              viewWidth!;
      if (width > 1.0) {
        width = 1.0;
        height = (imageWidth * viewWidth * width) /
            (imageHeight * viewHeight * (widget.aspectRatio ?? 1.0));
      }
    } else {
      width = 1.0;
      height = (imageWidth * viewWidth! * width) /
          (imageHeight * viewHeight! * (widget.aspectRatio ?? 1.0));
      if (height > 1.0) {
        height = 1.0;
        width =
            ((widget.aspectRatio ?? 1.0) * imageHeight * viewHeight * height) /
                imageWidth /
                viewWidth;
      }
    }
    if (!_maxAreaWidthMap.containsKey(widget.aspectRatio)) {
      _maxAreaWidthMap[widget.aspectRatio] = width;
    }
    return Rect.fromLTWH((1.0 - width) / 2, (1.0 - height) / 2, width, height);
  }

  void _updateImage(ImageInfo imageInfo, bool synchronousCall) {
    WidgetsBinding.instance!.addPostFrameCallback((timeStamp) {
      setState(() {
        _image = imageInfo.image;
        _scale = imageInfo.scale;
        _ratio = max(
          _boundaries!.width / _image!.width,
          _boundaries!.height / _image!.height,
        );

        final viewWidth = _boundaries!.width / (_image!.width * _scale! * _ratio!);
        final viewHeight =
            _boundaries!.height / (_image!.height * _scale! * _ratio!);
        _area = _calculateDefaultArea(
          viewWidth: viewWidth,
          viewHeight: viewHeight,
          imageWidth: _image!.width,
          imageHeight: _image!.height,
        );
        if (widget.defaultArea != null) {
          _area = Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
        }
        _view = Rect.fromLTWH(
          (viewWidth - 1.0) / 2,
          (viewHeight - 1.0) / 2,
          viewWidth,
          viewHeight,
        );
      });
    });
    WidgetsBinding.instance!.ensureVisualUpdate();
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _activate();
    _settleController.stop(canceled: false);
    _lastFocalPoint = details.focalPoint;
    _action = _CropAction.none;
    _startScale = _scale;
    _startView = _view;
  }

  Rect _getViewInBoundaries(double scale) {
    return Offset(
          max(
            min(
              _view!.left,
              _area!.left * _view!.width / scale,
            ),
            _area!.right * _view!.width / scale - 1.0,
          ),
          max(
            min(
              _view!.top,
              _area!.top * _view!.height / scale,
            ),
            _area!.bottom * _view!.height / scale - 1.0,
          ),
        ) &
        _view!.size;
  }

  double get _maximumScale => widget.maximumScale;

  double get _minimumScale {
    final scaleX = _boundaries!.width * _area!.width / (_image!.width * _ratio!);
    final scaleY = _boundaries!.height * _area!.height / (_image!.height * _ratio!);
    return min(_maximumScale, max(scaleX, scaleY));
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _deactivate();

    final num targetScale = _scale!.clamp(_minimumScale, _maximumScale);
    _scaleTween = Tween<double>(
      begin: _scale,
      end: targetScale as double?,
    );

    _startView = _view;
    _viewTween = RectTween(
      begin: _view,
      end: _getViewInBoundaries(targetScale as double),
    );

    _settleController.value = 0.0;
    _settleController.animateTo(
      1.0,
      curve: Curves.fastOutSlowIn,
      duration: const Duration(milliseconds: 350),
    );
  }

  void _updateArea(
      {double? left,
      double? top,
      double? right,
      double? bottom,
      }) {
    var areaLeft = _area!.left + (left ?? 0.0);
    var areaBottom = _area!.bottom + (bottom ?? 0.0);
    var areaTop = _area!.top + (top ?? 0.0);
    var areaRight = _area!.right + (right ?? 0.0);
    double width = areaRight - areaLeft;
    double height = (_image!.width * _view!.width * width) /
        (_image!.height * _view!.height * (widget.aspectRatio ?? 1.0));
    if (height >= 1.0 || width >= 1.0) {
      height = 1.0;
    }

    // ensure minimum rectangle
    if (areaRight - areaLeft < _kCropMinFraction) {
      if (left != null) {
        areaLeft = areaRight - _kCropMinFraction;
      } else {
        areaRight = areaLeft + _kCropMinFraction;
      }
    }

    if (areaBottom - areaTop < _kCropMinFraction) {
      if (top != null) {
        areaTop = areaBottom - _kCropMinFraction;
      } else {
        areaBottom = areaTop + _kCropMinFraction;
      }
    }

    // adjust to aspect ratio if needed
    if (widget.aspectRatio != null && widget.aspectRatio! > 0.0) {
      if (top != null) {
        areaTop = areaBottom - height;
        if (areaTop < 0.0) {
          areaTop = 0.0;
          areaBottom = height;
        }
      } else {
        areaBottom = areaTop + height;
        if (areaBottom > 1.0) {
          areaTop = 1.0 - height;
          areaBottom = 1.0;
        }
      }
    }

    // ensure to remain within bounds of the view
    if (areaLeft < 0.0) {
      areaLeft = 0.0;
      areaRight = _area!.width;
    } else if (areaRight > 1.0) {
      areaLeft = 1.0 - _area!.width;
      areaRight = 1.0;
    }

    if (areaTop < 0.0) {
      areaTop = 0.0;
      areaBottom = _area!.height;
    } else if (areaBottom > 1.0) {
      areaTop = 1.0 - _area!.height;
      areaBottom = 1.0;
    }

    setState(() {
      _area = Rect.fromLTRB(areaLeft, areaTop, areaRight, areaBottom);
    });
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_action == _CropAction.none) {
      _action = pointers == 2 ? _CropAction.scaling : _CropAction.moving;
    }

    if (_action == _CropAction.cropping) {

    } else if (_action == _CropAction.moving) {
      final delta = details.focalPoint - _lastFocalPoint;
      _lastFocalPoint = details.focalPoint;

      setState(() {
        _view = _view!.translate(
          delta.dx / (_image!.width * _scale! * _ratio!),
          delta.dy / (_image!.height * _scale! * _ratio!),
        );
      });
    } else if (_action == _CropAction.scaling) {
      setState(() {
        _scale = _startScale! * details.scale;

        final dx = _boundaries!.width *
            (1.0 - details.scale) /
            (_image!.width * _scale! * _ratio!);
        final dy = _boundaries!.height *
            (1.0 - details.scale) /
            (_image!.height * _scale! * _ratio!);

        _view = Rect.fromLTWH(
          _startView!.left + dx / 2,
          _startView!.top + dy / 2,
          _startView!.width,
          _startView!.height,
        );
      });
    }
  }
}

class _CropPainter extends CustomPainter {
  final ui.Image? image;
  final Rect? view;
  final double? ratio;
  final Rect? area;
  final double? scale;
  final double? active;
  final Rect? defaultArea;

  _CropPainter({
    this.image,
    this.view,
    this.ratio,
    this.area,
    this.scale,
    this.active,
    this.defaultArea,
  });

  @override
  bool shouldRepaint(_CropPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.view != view ||
        oldDelegate.ratio != ratio ||
        oldDelegate.area != area ||
        oldDelegate.active != active ||
        oldDelegate.scale != scale;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      0,
      0,
      size.width,
      size.height,
    );

    canvas.save();
    canvas.translate(rect.left, rect.top);

    final paint = Paint()..isAntiAlias = false;

    if (image != null) {
      final src = Rect.fromLTWH(
        0.0,
        0.0,
        image!.width.toDouble(),
        image!.height.toDouble(),
      );
      final dst = Rect.fromLTWH(
        view!.left * image!.width * scale! * ratio!,
        view!.top * image!.height * scale! * ratio!,
        image!.width * scale! * ratio!,
        image!.height * scale! * ratio!,
      );

      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0.0, 0.0, rect.width, rect.height));
      canvas.drawImageRect(image!, src, dst, paint);
      canvas.restore();
    }

    if (defaultArea != null) {
      paint.color = Color.fromRGBO(
          0xff,
          0xff,
          0xff,
          _kCropOverlayActiveOpacity * active! +
              _kCropOverlayInactiveOpacity * (1.0 - active!));
      final boundaries = Rect.fromLTWH(
        rect.width * area!.left,
        rect.height * area!.top,
        rect.width * area!.width,
        rect.height * area!.height,
      );

      var path = Path()
        ..addRect(Rect.fromLTWH(0, 0, rect.width, rect.height))
        ..addOval(boundaries)
        ..fillType = PathFillType.evenOdd;

      canvas.clipPath(path);
      canvas.drawRect(Rect.fromLTWH(0, 0, rect.width, rect.height), paint);
    }

    canvas.restore();
  }
}
