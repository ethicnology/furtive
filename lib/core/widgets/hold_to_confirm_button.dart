import 'package:flutter/material.dart';

/// FloatingActionButton-like control that fires its callback only after the
/// user has held it down for [holdDuration]. Releasing early cancels. A
/// black-tint fill grows left→right inside the pill and the label flips to
/// a "3, 2, 1" countdown so the user keeps the visual feedback right under
/// their finger.
///
/// On a short tap the [shortTapHint] snackbar is shown once, letting the
/// user discover the gesture.
class HoldToConfirmButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String shortTapHint;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onConfirmed;
  final Duration holdDuration;

  const HoldToConfirmButton({
    super.key,
    required this.icon,
    required this.label,
    required this.shortTapHint,
    required this.onConfirmed,
    this.backgroundColor = const Color(0xFFE53935),
    this.foregroundColor = Colors.white,
    this.holdDuration = const Duration(seconds: 3),
  });

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<HoldToConfirmButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.holdDuration,
  );
  bool _hintShown = false;

  @override
  void didUpdateWidget(covariant HoldToConfirmButton old) {
    super.didUpdateWidget(old);
    // The AnimationController is `late final`, so swapping holdDuration on
    // the widget without this hook would silently ignore the new value.
    // Today every callsite passes the default (3s) but this defends
    // against latent bugs if the widget is reused with a dynamic duration.
    if (widget.holdDuration != old.holdDuration) {
      _controller.duration = widget.holdDuration;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Awaiting forward() gives us a single completion point regardless of
  // whether the animation finished naturally or was stopped early by the
  // user releasing the button. Checking _controller.value == 1.0 after
  // the await disambiguates the two — no status-listener race.
  Future<void> _start() async {
    await _controller.forward(from: 0);
    if (!mounted) return;
    if (_controller.value >= 1.0) widget.onConfirmed();
  }

  void _cancel() {
    if (!_controller.isAnimating) return;
    _controller.stop();
    _controller.reset();
  }

  void _onShortTap() {
    if (_hintShown) return;
    _hintShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.shortTapHint),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onShortTap,
      onLongPressStart: (_) => _start(),
      onLongPressEnd: (_) => _cancel(),
      onLongPressCancel: _cancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final remaining =
              (widget.holdDuration.inMilliseconds *
                      (1 - _controller.value) /
                      1000)
                  .ceil();
          final isHolding = _controller.isAnimating;
          // Visually matches FloatingActionButton.extended: stadium shape,
          // default FAB elevation, 16 px symmetric padding. A black-tint
          // overlay grows left→right while the user holds, giving the
          // progress feedback without breaking the FAB silhouette.
          return Material(
            color: widget.backgroundColor,
            elevation: 6,
            shape: const StadiumBorder(),
            // FloatingActionButton.extended is 56 px tall by default — match
            // it so the Stop pill aligns with the Pause / Follow FABs in
            // the same column.
            child: SizedBox(
              height: 56,
              child: Stack(
                // Without an explicit alignment Stack defaults to topStart,
                // which would pin icon + label to the top of the 48 px pill
                // instead of vertically centring them.
                alignment: Alignment.center,
                children: [
                  if (isHolding)
                    Positioned.fill(
                      child: ClipPath(
                        clipper: const ShapeBorderClipper(
                          shape: StadiumBorder(),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerRight,
                          widthFactor: _controller.value,
                          child: Container(color: Colors.black.withAlpha(80)),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          widget.icon,
                          color: widget.foregroundColor,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isHolding ? '$remaining' : widget.label,
                          style: TextStyle(
                            color: widget.foregroundColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
