import 'package:flutter/material.dart';

class Skeleton extends StatelessWidget {
  const Skeleton({
    this.width,
    this.height,
    this.widthFactor,
    this.heightFactor,
    this.shape = BoxShape.rectangle,
    this.alignment = AlignmentDirectional.center,
  });

  final double? width;
  final double? height;
  final double? widthFactor;
  final double? heightFactor;
  final BoxShape shape;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        shape: shape,
        color: theme.hintColor.withValues(alpha: .16),
      ),
    );

    if (widthFactor == null && heightFactor == null) return box;

    // FractionallySizedBox 需要父约束**有界**；放进 Row / 无界列表项时父宽是无限的
    // （BoxConstraints forces an infinite width）会直接崩。这种场景下退回固定尺寸。
    return LayoutBuilder(
      builder: (context, constraints) {
        final canWidth = widthFactor == null || constraints.hasBoundedWidth;
        final canHeight = heightFactor == null || constraints.hasBoundedHeight;
        if (!canWidth || !canHeight) return box;
        return FractionallySizedBox(
          widthFactor: widthFactor,
          heightFactor: heightFactor,
          alignment: alignment,
          child: box,
        );
      },
    );
  }
}
