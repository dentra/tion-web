import 'package:flutter/material.dart';

class SpeedWidget extends StatelessWidget {
  final int speed;
  final int maxSpeed;
  final Function(int) setSpeed;

  const SpeedWidget(
      {super.key,
      required this.speed,
      required this.maxSpeed,
      required this.setSpeed});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            if (maxSpeed > 0) _button(context, 1, speed == 1),
            if (maxSpeed > 1) _button(context, 2, speed == 2),
            if (maxSpeed > 2) _button(context, 3, speed == 3),
            if (maxSpeed > 3) _button(context, 4, speed == 4),
            if (maxSpeed > 4) _button(context, 5, speed == 5),
            if (maxSpeed > 5) _button(context, 6, speed == 6),
          ],
        ),
      ],
    );
  }

  ButtonStyleButton _button(BuildContext context, int btnSpeed, bool isActive) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
          // onPrimary: isActive ? Colors.black : Colors.white,
          // primary: isActive ? Colors.white : Colors.transparent,
          backgroundColor:
              isActive ? Theme.of(context).indicatorColor : Colors.transparent,
          minimumSize: const Size(38, 38),
          // padding: const EdgeInsets.all(4),
          shape: const CircleBorder(),
          // side: BorderSide(color: Colors.white.withOpacity(0.4)),
          elevation: 0),
      onPressed: () => setSpeed(btnSpeed),
      child: Text(btnSpeed.toString()),
    );
  }
}
