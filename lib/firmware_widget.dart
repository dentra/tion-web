import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:convert/convert.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'firmware.dart';
import 'tion.dart';
import 'log.dart';

class TionFirmwareWidget extends StatefulWidget {
  final TionBLE tion;
  final UpdateStateController updateStateController;

  const TionFirmwareWidget(
      {super.key, required this.tion, required this.updateStateController});

  @override
  State<TionFirmwareWidget> createState() => _TionFirmwareWidgetState();
}

class _TionFirmwareWidgetState extends State<TionFirmwareWidget>
    with TickerProviderStateMixin {
  late StreamSubscription<TionCommand> _rxSubscription;

  TionBLE get _tion => widget.tion;

  String _firmwareVersion = "";

  var _versions = List<FirmwareInfo>.empty();

  FirmwareInfo? _selectedFirmware;

  late AnimationController controller;

  UpdateState get _updateState => widget.updateStateController.value;
  set _updateState(UpdateState value) =>
      widget.updateStateController.value = value;

  Uint8List _firmwareData = Uint8List(0);
  int _firmwareChunkOffset = 0;

  @override
  void initState() {
    _rxSubscription = _tion.rx.listen(_checkFirmwareAnswer);
    _tion.reqDevInfo();
    controller = AnimationController(
      /// [AnimationController]s can be created with `vsync: this` because of
      /// [TickerProviderStateMixin].
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addListener(() {
        setState(() {});
      });

    _loadFirmwareVersions();

    super.initState();
  }

  @override
  void dispose() {
    _updateState = UpdateState.stopped;
    _rxSubscription.cancel();
    controller.dispose();
    super.dispose();
  }

  void _checkFirmwareAnswer(final TionCommand cmd) {
    log.d(() => "${cmd.codeHex}: ${hex.encode(cmd.data)}");
    if (cmd is TionDevInfoRsp) {
      setState(() {
        _firmwareVersion = cmd.firmwareVersionHex;
        if (_updateState == UpdateState.restart) {
          _updateState = UpdateState.stopped;
        }
      });
    } else if (cmd is TionUpdateErrorRsp) {
      log.e("Failed update");
      _reportError("Ошибка обновления");
    } else if (cmd is TionUpdateInitRsp) {
      log.i("Success update init ${cmd.deviceType}");
      _startFirmware();
    } else if (cmd is TionUpdateStartRsp) {
      log.i("Success update start");
      _nextChunkFirmware();
    } else if (cmd is TionUpdateChunkRsp) {
      log.i("Success update chunk");
      _nextChunkFirmware();
    } else if (cmd is TionUpdateFinishRsp) {
      log.i("Success update finish");
      _finishFirmware();
    }
  }

  @override
  void setState(VoidCallback fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Card(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.card_giftcard_outlined),
                    label: const Text('Поблагодарить автора'),
                    onPressed: () => launchUrlString(
                        "https://www.tinkoff.ru/cf/3dZPaLYDBAI"),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.commit_outlined),
                title: Text(_firmwareVersion),
                subtitle: const Text("Текущая версия"),
              ),
              ListTile(
                leading: const Icon(Icons.merge_type_outlined),
                title: DropdownMenu<FirmwareInfo>(
                  enabled: _versions.isNotEmpty &&
                      _updateState == UpdateState.stopped,
                  // initialSelection: selectedFirmware,
                  // controller: versionSelect,
                  requestFocusOnTap: true,
                  // label: const Text("Доступная версия"),
                  onSelected: (FirmwareInfo? fw) {
                    setState(() {
                      _selectedFirmware = fw;
                    });
                  },
                  dropdownMenuEntries: _versions.map((FirmwareInfo fw) {
                    return DropdownMenuEntry<FirmwareInfo>(
                      value: fw,
                      label: fw.name,
                      enabled: !fw.test && _firmwareVersion != fw.name,
                      leadingIcon: fw.like
                          ? const Icon(Icons.favorite)
                          : const Icon(Icons.bookmark),
                    );
                  }).toList(),
                ),
                subtitle: const Text("Доступная версия"),
              ),
              if (_updateState != UpdateState.stopped)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Column(
                    children: [
                      Text(
                        _updateStateTitle,
                        style: const TextStyle(fontSize: 20),
                      ),
                      LinearProgressIndicator(
                        value: controller.value,
                        semanticsLabel: 'Linear progress indicator',
                      ),
                    ],
                  ),
                ),
              if (_selectedFirmware != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TextButton.icon(
                      icon: _updateState == UpdateState.stopped
                          ? const Icon(Icons.system_update_outlined)
                          : const Icon(Icons.dangerous_outlined),
                      label: _updateState == UpdateState.stopped
                          ? const Text("ОБНОВИТЬ")
                          : const Text("ПРЕРВАТЬ"),
                      onPressed: () {
                        if (_updateState == UpdateState.stopped) {
                          _loadFirmware();
                        } else {
                          _reportStop();
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              if (_selectedFirmware != null)
                const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.warning_outlined,
                          size: 40,
                          color: Colors.red,
                        ),
                        Text(
                          "ВНИМАНИЕ!",
                          style: TextStyle(fontSize: 40, color: Colors.red),
                        ),
                      ],
                    ),
                    Text(
                      "Нажимая кнопку ОБНОВИТЬ Вы соглашаетесь с тем,\nчто осознаете риск и принимаете ответственность за все возможные последствия!",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, color: Colors.red),
                    ),
                    Padding(padding: EdgeInsets.symmetric(vertical: 16.0)),
                    Text(
                      "Обеспечьте стабильное питание для бризера и ПК во время обновления.\n"
                      "Не переключайтесь на другие окна и не давайте ПК заснуть.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.red),
                      //
                    ),
                  ],
                ),
            ],
          ),
        ));
  }

  String get _updateStateTitle {
    var title = _updateState.title;
    if (_updateState == UpdateState.chunk) {
      final percent = _firmwareChunkOffset.toDouble() /
          _firmwareData.length.toDouble() *
          100;
      title = "$title: ${percent.toStringAsFixed(1)} %";
    }
    return '$title...';
  }

  Future<void> _loadFirmwareVersions() async {
    final fwType = FirmwareType.fromDevName(_tion.devName);
    final res = await fwType.list(_reportError);
    if (res.isNotEmpty) {
      setState(() {
        _versions = res;
      });
    } else {
      log.w("No firmware versions loaded for ${_tion.devName}");
    }
  }

  void _reportMessage(final String message, {bool error = false}) {
    if (error) {
      log.e(message);
    } else {
      log.i(message);
    }
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  void _reportError(final String message) {
    _reportMessage(message, error: true);
    setState(() {
      _updateState = UpdateState.stopped;
    });
  }

  void _reportStop() {
    _reportError("Остановлено пользователем");
  }

  Future<void> _loadFirmware() async {
    if (_selectedFirmware == null) {
      _reportError("Прошивка не была выбрана");
      return;
    }

    controller.repeat();

    setState(() {
      _updateState = UpdateState.download;
    });

    _firmwareData = await _selectedFirmware!.load(_reportError);
    if (_firmwareData.isEmpty) {
      _updateState = UpdateState.stopped;
      return;
    }

    await _validateFirmware();
  }

  Future<void> _validateFirmware() async {
    if (_updateState == UpdateState.stopped) {
      return;
    }

    setState(() {
      _updateState = UpdateState.validate;
    });

    final valid =
        await _selectedFirmware!.validate(_firmwareData, _reportError);

    if (!valid) {
      return;
    }

    await _initFirmware();
  }

  Future<void> _initFirmware() async {
    if (_updateState == UpdateState.stopped) {
      return;
    }

    setState(() {
      _updateState = UpdateState.init;
    });

    await _tion.tx(TionUpdateInitReq());
  }

  Future<void> _startFirmware() async {
    if (_updateState == UpdateState.stopped) {
      return;
    }

    controller.value = 0;

    setState(() {
      _updateState = UpdateState.start;
    });

    _firmwareChunkOffset = 0;

    await _tion.tx(TionUpdateStartReq(_firmwareData.length));
  }

  Future<void> _nextChunkFirmware() async {
    if (_updateState == UpdateState.stopped) {
      return;
    }

    int chunkSize = 1000;
    if (_firmwareChunkOffset + chunkSize > _firmwareData.length) {
      chunkSize = _firmwareData.length - _firmwareChunkOffset;
    }

    controller.value =
        _firmwareChunkOffset.toDouble() / _firmwareData.length.toDouble();

    setState(() {
      _updateState = UpdateState.chunk;
    });

    if (_firmwareChunkOffset == -1) {
      await _tion.tx(TionUpdateFinishReq(_firmwareData.length));
    } else if (_firmwareChunkOffset == _firmwareData.length) {
      // int crc = _tion.calcCRC(_firmwareData);
      // await _tion.tx(TionUpdateChunkReq(0xFFFFFFFF,
      //     Uint8List(2)..buffer.asByteData().setUint16(0, crc, Endian.big)));
      // _firmwareChunkOffset = -1;
      // в Tion Remote отсутствует фаза отправки проверки контрольной суммы
      await _tion.tx(TionUpdateFinishReq(_firmwareData.length));
    } else {
      log.i("Sending $_firmwareChunkOffset of ${_firmwareData.length}");
      final chunkData = _firmwareData.sublist(
          _firmwareChunkOffset, _firmwareChunkOffset + chunkSize);
      log.w("chunk: offset=$_firmwareChunkOffset, size=${chunkData.length}");
      await _tion.tx(TionUpdateChunkReq(_firmwareChunkOffset, chunkData));
      _firmwareChunkOffset += chunkSize;
    }
  }

  Future<void> _finishFirmware() async {
    _reportMessage("Обновление успешно завершено");
    setState(() {
      _updateState = UpdateState.restart;
      controller.repeat();
    });
    await Future.delayed(const Duration(seconds: 5), _tion.reqDevInfo);
  }
}

enum UpdateState {
  stopped(""),
  download("Загрузка прошивки"),
  validate("Подсчет контрольной суммы"),
  init("Запрос бризера на обновление"),
  start("Запуск обновления"),
  chunk("Обновление"),
  finished("Завершение обновления"),
  restart("Ожидаем рестарт бризера");

  final String title;
  const UpdateState(this.title);
}

class UpdateStateController {
  UpdateState value = UpdateState.stopped;
}
