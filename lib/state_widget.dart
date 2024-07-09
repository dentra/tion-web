import 'dart:async';

import 'package:flutter/material.dart';
import 'package:convert/convert.dart';
import 'package:tion_web/speed_widget.dart';
import 'tion.dart';

class TionStateWidget extends StatefulWidget {
  final TionBLE tion;

  const TionStateWidget({super.key, required this.tion});

  @override
  State<TionStateWidget> createState() => _TionStateWidgetState();
}

class _TionStateWidgetState extends State<TionStateWidget> {
  late StreamSubscription<TionCommand> _rxSubscription;
  late Timer _timer;

  String tionStateHex = "";
  TionBLE get _tion => widget.tion;

  TionState? _state;

  @override
  void initState() {
    super.initState();
    _rxSubscription = _tion.rx.listen((cmd) => setState(() {
          tionStateHex = "${cmd.codeHex}: ${hex.encode(cmd.data)}";
          setState(() {
            if (cmd is TionState) {
              _state = cmd;
            }
          });
        }));
    _tion.reqState();
    _timer = Timer.periodic(
        const Duration(seconds: 15), (Timer t) => _tion.reqState());
  }

  @override
  void dispose() {
    _timer.cancel();
    _rxSubscription.cancel();
    super.dispose();
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: _state == null
            ? const Center(
                child: Text("Запрос состояния..."),
              )
            : Card(
                child: Column(
                children: [
                  ListTile(
                    leading: _state!.powerState
                        ? const Icon(Icons.power_outlined)
                        : const Icon(Icons.power_off_outlined),
                    title: _state!.powerState
                        ? const Text("Включен")
                        : const Text("Выключен"),
                    subtitle: const Text("Состояние"),
                  ),
                  ListTile(
                    leading: _fanSpeedIcon,
                    title: SpeedWidget(
                        speed: _state?.fanSpeed ?? 0,
                        maxSpeed: _state?.maxSpeed ?? 0,
                        setSpeed: (speed) {
                          // do change speed here
                        }),
                    subtitle: const Text("Скорость вентиляции"),
                  ),
                  ListTile(
                    leading: _state!.heaterState
                        ? const Icon(Icons.flash_on_outlined)
                        : const Icon(Icons.flash_off_outlined),
                    title: _state!.heaterState
                        ? Text("Включен: ${_state!.heaterVar.toInt()} %")
                        : const Text("Выключен"),
                    subtitle: const Text("Обогреватель"),
                  ),
                  ListTile(
                    leading: const Icon(Icons.thermostat_outlined),
                    title: Text("${_state!.targetTemperature.toInt()} °C"),
                    subtitle: const Text("Целевая температура"),
                  ),
                  ListTile(
                    leading: const Icon(Icons.home_outlined),
                    title: Text("${_state!.currentTemperature.toInt()} °C"),
                    subtitle: const Text("Температура внутри"),
                  ),
                  ListTile(
                    leading: const Icon(Icons.park_outlined),
                    title: Text("${_state!.outdoorTemperature.toInt()} °C"),
                    subtitle: const Text("Температура снаружи"),
                  ),
                ],
              )));
  }

  Icon get _fanSpeedIcon {
    if (!_state!.powerState) {
      return const Icon(Icons.mode_fan_off);
    }
    switch (_state!.fanSpeed) {
      case 2:
        return const Icon(Icons.looks_two_outlined);
      case 3:
        return const Icon(Icons.looks_3_outlined);
      case 4:
        return const Icon(Icons.looks_4_outlined);
      case 5:
        return const Icon(Icons.looks_5_outlined);
      case 6:
        return const Icon(Icons.looks_6_outlined);
      default:
        return const Icon(Icons.looks_one_outlined);
    }
  }
}
