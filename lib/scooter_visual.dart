import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../domain/scooter_state.dart';
import '../domain/theme_helper.dart';
import '../domain/color_utils.dart';
import '../services/image_cache_service.dart';

class ScooterVisual extends StatefulWidget {
  final ScooterState? state;
  final bool scanning;
  final bool blinkerLeft;
  final bool blinkerRight;
  final int? color;
  final String? colorHex;
  final String? cloudImageUrl;
  final bool hasCustomColor;
  final bool winter;
  final bool aprilFools;
  final bool halloween;

  const ScooterVisual({
    required this.state,
    required this.scanning,
    required this.blinkerLeft,
    required this.blinkerRight,
    this.winter = false,
    this.aprilFools = false,
    this.halloween = false,
    this.color,
    this.colorHex,
    this.cloudImageUrl,
    this.hasCustomColor = false,
    super.key,
  });

  @override
  State<ScooterVisual> createState() => _ScooterVisualState();
}

class _ScooterVisualState extends State<ScooterVisual> {
  // controls whether the light ring is flickering:
  // when true the ring is considered hidden (flickering), when false it's visible
  bool _ringFlickering = false;

  // current AnimatedOpacity duration for the light ring. We switch this to
  // a short duration while flickering to get quick blinks, then restore it.
  Duration _ringOpacityDuration = const Duration(milliseconds: 1000);

  final Random _rand = Random();

  // timers scheduled for flicker sequences and the loop timer
  final List<Timer> _scheduledTimers = [];
  Timer? _nextLoopTimer;

  bool get _baseOn => widget.state != null && widget.state!.isOn;

  @override
  void initState() {
    super.initState();
    _ringFlickering = !_baseOn;
    if (widget.halloween && _baseOn) {
      // initial spooky flicker immediately
      _doFlickerSequence();
    }
  }

  @override
  void didUpdateWidget(covariant ScooterVisual oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If flicker flag changed or power state changed, adjust behavior
    if (widget.halloween != oldWidget.halloween) {
      if (widget.halloween && _baseOn) {
        _doFlickerSequence();
      } else {
        _cancelAllFlickers();
        setState(() {
          _ringOpacityDuration = const Duration(milliseconds: 1000);
          _ringFlickering = !_baseOn;
        });
      }
    }

    // If scooter turned on while flicker is enabled, start a sequence
    if (widget.halloween && !_baseOn && oldWidget.state != null && oldWidget.state!.isOn) {
      // turned off -> ensure ring hidden (inverted -> flickering = true)
      _cancelAllFlickers();
      setState(() => _ringFlickering = true);
    }

    if (widget.halloween && _baseOn && !(oldWidget.state?.isOn ?? false)) {
      // just turned on
      _doFlickerSequence();
    }

    // If flicker is disabled but the base on-state changed, reflect it
    if (!widget.halloween && _baseOn != (oldWidget.state != null && oldWidget.state!.isOn)) {
      setState(() => _ringFlickering = !_baseOn);
    }
  }

  @override
  void dispose() {
    _cancelAllFlickers();
    super.dispose();
  }

  void _cancelAllFlickers() {
    for (var t in _scheduledTimers) {
      t.cancel();
    }
    _scheduledTimers.clear();
    _nextLoopTimer?.cancel();
    _nextLoopTimer = null;
  }

  void _doFlickerSequence() {
    // cancel any pending timers for an ongoing sequence
    for (var t in _scheduledTimers) {
      t.cancel();
    }
    _scheduledTimers.clear();

    // If scooter not on, don't flicker
    if (!_baseOn) return;

    // number of toggles for the spooky launch effect
    final toggles = 6 + _rand.nextInt(6); // 6..11 toggles

    // cumulative delay tracker
    int cumulative = 0;

    for (var i = 0; i < toggles; i++) {
      final ms = 1 + _rand.nextInt(300); // 1..349 ms between toggles
      cumulative += ms;
      final t = Timer(Duration(milliseconds: cumulative), () {
        if (!mounted) return;
        setState(() {
          // fast opacity during toggles
          _ringOpacityDuration = Duration(
            milliseconds: 60 + _rand.nextInt(140),
          );
          _ringFlickering = !_ringFlickering;
        });
      });
      _scheduledTimers.add(t);
    }

    // After sequence ends, restore stable visibility and duration
    cumulative += 200;
    final restore = Timer(Duration(milliseconds: cumulative), () {
      if (!mounted) return;
      setState(() {
        _ringOpacityDuration = const Duration(milliseconds: 1000);
        _ringFlickering = false; // settle to visible when on (inverted)
      });
      // schedule next loop in 10..30 seconds
      _scheduleNextLoop();
    });
    _scheduledTimers.add(restore);
  }

  void _scheduleNextLoop() {
    _nextLoopTimer?.cancel();
    final seconds = 10 + _rand.nextInt(21); // 10..30
    _nextLoopTimer = Timer(Duration(seconds: seconds), () {
      if (!mounted) return;
      if (!widget.halloween || !_baseOn) return;
      _doFlickerSequence();
    });
  }
=======
  const ScooterVisual(
      {required this.state,
      required this.scanning,
      required this.blinkerLeft,
      required this.blinkerRight,
      this.winter = false,
      this.aprilFools = false,
      this.color,
      this.colorHex,
      this.cloudImageUrl,
      this.hasCustomColor = false,
      super.key});
>>>>>>> 2081bc6 (feat: update main page immediately when connecting to target scooter)

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (widget.halloween)
          AnimatedOpacity(
            opacity: widget.state == ScooterState.disconnected ? 0 : 1,
            duration: const Duration(milliseconds: 500),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 700, maxHeight: 300),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 80.0),
                child: Image(
                  fit: BoxFit.contain,
                  image: AssetImage(
                    "images/decoration/wings.webp",
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.55,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 500),
                  firstChild: Shimmer.fromColors(
                    baseColor: context.isDarkMode ? Colors.black : Colors.black45,
                    highlightColor: widget.scanning
                        ? Colors.transparent
                        : context.isDarkMode
                            ? Colors.black
                            : Colors.black45,
                    enabled: widget.scanning,
                    direction: ShimmerDirection.ltr,
                    period: const Duration(seconds: 2),
                    child: const Image(
                      image: AssetImage("images/scooter/disconnected.webp"),
                    ),
                  ),
                  secondChild: Opacity(
                    opacity: 1,
                    child: Image(
                      image: AssetImage(
                        "images/scooter/base_${widget.aprilFools ? 9 : widget.color ?? 1}.webp",
                      ),
                    ),
                  ),
                  crossFadeState:
                      widget.state == ScooterState.disconnected ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                ),
                if (widget.winter && widget.state != ScooterState.disconnected)
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 500),
                    firstChild: const Image(
                      image: AssetImage(
                        "images/scooter/seasonal/winter_on.webp",
                      ),
                    ),
                    secondChild: Opacity(
                      opacity: 1,
                      child: _buildScooterImage(),
                    ),
                    crossFadeState: state == ScooterState.disconnected ||
                            state == ScooterState.connectingAuto
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                  ),
                  if (winter &&
                      state != ScooterState.disconnected &&
                      state != ScooterState.connectingAuto)
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 500),
                      firstChild: const Image(
                        image: AssetImage(
                            "images/scooter/seasonal/winter_on.webp"),
                      ),
                      secondChild: const Image(
                        image: AssetImage(
                            "images/scooter/seasonal/winter_off.webp"),
                      ),
                      crossFadeState: state != null && state!.isOn
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                    ),
                  AnimatedOpacity(
                    opacity: state != null && state!.isOn ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 1000),
                    child: const Image(
                      image: AssetImage("images/scooter/light_ring.webp"),
                    ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: widget.state == ScooterState.ready ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 1000),
                  child: const Image(
                    image: AssetImage("images/scooter/light_beam.webp"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    //BlinkerWidget(blinkerLeft: blinkerLeft, blinkerRight: blinkerRight),
  }

  /// Builds the main scooter image, handling both local assets and cloud images
  Widget _buildScooterImage() {
    if (hasCustomColor && cloudImageUrl != null) {
      // Use cached cloud image for custom colors - use "front" image for main screen
      return FutureBuilder<File?>(
        future: ImageCacheService().getImage(cloudImageUrl!),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return Image.file(
              snapshot.data!,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                // Fallback to color-based placeholder
                return _buildColorPlaceholder();
              },
            );
          } else if (snapshot.hasError) {
            return _buildColorPlaceholder();
          } else {
            // Loading state - show asset image while loading
            return Image(
              image: AssetImage(
                  "images/scooter/base_${aprilFools ? 9 : color ?? 1}.webp"),
            );
          }
        },
      );
    } else {
      // Use local asset image for predefined colors
      return Image(
        image: AssetImage(
            "images/scooter/base_${aprilFools ? 9 : color ?? 1}.webp"),
      );
    }
  }

  /// Builds a color-based placeholder when cloud image fails to load
  Widget _buildColorPlaceholder() {
    Color effectiveColor = _getEffectiveColor();
    
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: effectiveColor,
          width: 2,
        ),
      ),
      child: Icon(
        Icons.electric_scooter,
        size: 120,
        color: effectiveColor,
      ),
    );
  }

  /// Gets the effective color for display
  Color _getEffectiveColor() {
    if (colorHex != null) {
      return ColorUtils.parseHexColor(colorHex) ?? ColorUtils.getColorValue(color ?? 1);
    }
    
    // Return predefined color
    return ColorUtils.getColorValue(color ?? 1);
  }

  IconData stateIcon() {
    if (widget.scanning) {
      return Icons.wifi_tethering;
    }
    switch (widget.state) {
      case ScooterState.standby:
        return Icons.power_settings_new;
      case ScooterState.off:
        return Icons.block;
      case ScooterState.parked:
        return Icons.local_parking;
      case ScooterState.shuttingDown:
        return Icons.settings_power;
      case ScooterState.ready:
        return Icons.check_circle;
      case ScooterState.hibernating:
        return Icons.bedtime;
      default:
        return Icons.error;
    }
  }
}

class BlinkerWidget extends StatefulWidget {
  final bool blinkerLeft;
  final bool blinkerRight;

  const BlinkerWidget({
    required this.blinkerLeft,
    required this.blinkerRight,
    super.key,
  });

  @override
  State<BlinkerWidget> createState() => _BlinkerWidgetState();
}

class _BlinkerWidgetState extends State<BlinkerWidget> {
  bool _showBlinker = true;

  // Timer to toggle the image every second
  late Timer _timer;

  @override
  void initState() {
    super.initState();

    var anyBlinker = widget.blinkerLeft || widget.blinkerRight;

    if (anyBlinker) {
      _timer = Timer.periodic(const Duration(milliseconds: 600), (Timer t) {
        setState(() => _showBlinker = !_showBlinker);
      });
    }
  }

  @override
  void dispose() {
    // Cancel the timer to avoid memory leaks
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const blinkerDuration = Duration(milliseconds: 200);

    var showBlinkerLeft = _showBlinker && widget.blinkerLeft;
    var showBlinkerRight = _showBlinker && widget.blinkerRight;

    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedOpacity(
          opacity: showBlinkerLeft ? 1.0 : 0.0,
          duration: blinkerDuration,
          child: const Image(
            image: AssetImage("images/scooter/blinker_l.webp"),
          ),
        ),
        AnimatedOpacity(
          opacity: showBlinkerRight ? 1.0 : 0.0,
          duration: blinkerDuration,
          child: const Image(
            image: AssetImage("images/scooter/blinker_r.webp"),
          ),
        ),
      ],
    );
  }
}
