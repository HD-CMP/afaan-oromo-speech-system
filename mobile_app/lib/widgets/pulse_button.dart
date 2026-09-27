import 'package:flutter/material.dart';
import '../config/app_constants.dart';

class PulseButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;
  
  const PulseButton({
    super.key,
    required this.child,
    this.onPressed,
    this.color,
    this.size = 80.0,
  });

  @override
  State<PulseButton> createState() => _PulseButtonState();
}

class _PulseButtonState extends State<PulseButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _animation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: _animation.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color ?? Theme.of(context).primaryColor,
              boxShadow: [
                BoxShadow(
                  color: (widget.color ?? Theme.of(context).primaryColor)
                      .withOpacity(0.4 * _animation.value),
                  blurRadius: 20 * _animation.value,
                  spreadRadius: 10 * (_animation.value - 1),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onPressed,
                customBorder: const CircleBorder(),
                child: Center(child: widget.child),
              ),
            ),
          ),
        );
      },
    );
  }
}
