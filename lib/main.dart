import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_web_bluetooth/flutter_web_bluetooth.dart';
import "package:flutter_web_bluetooth/js_web_bluetooth.dart";

import 'firmware_widget.dart';
import 'tion.dart';
import 'state_widget.dart';
import 'log.dart';

void main() async {
  initLog();
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TionFlasherApp());
}

class TionFlasherApp extends StatefulWidget {
  const TionFlasherApp({super.key});

  @override
  State<TionFlasherApp> createState() => _TionFlasherAppState();
}

class _TionFlasherAppState extends State<TionFlasherApp>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  BluetoothDevice? _device;
  BuildContext? _floatContext;

  final tion = TionBLE();
  final updateStateController = UpdateStateController();

  @override
  void initState() {
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 0 &&
          updateStateController.value != UpdateState.stopped) {
        updateStateController.value = UpdateState.stopped;
      }
    });
    super.initState();
  }

  @override
  void dispose() {
    updateStateController.value = UpdateState.stopped;
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const title = 'Tion Web';
    return MaterialApp(
      title: title,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: ThemeMode.system,
      home: DefaultTabController(
        length: tion.connected ? 2 : 1,
        child: Scaffold(
          appBar: AppBar(
            // backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            title: Text(tion.connected ? "$title: ${tion.devName}" : title),
            bottom: TabBar(
              controller: tion.connected ? _tabController : null,
              tabs: [
                if (!tion.connected)
                  const Tab(
                    icon: Icon(Icons.info_outline),
                    text: "Подключение",
                  ),
                if (tion.connected &&
                    updateStateController.value == UpdateState.stopped)
                  const Tab(
                    icon: Icon(Icons.hvac_outlined),
                    text: "Состояние",
                  ),
                if (tion.connected)
                  const Tab(
                    icon: Icon(Icons.system_update_alt_outlined),
                    text: "Прошивка",
                  ),
              ],
            ),
          ),
          body: TabBarView(
            controller: tion.connected ? _tabController : null,
            children: [
              if (!tion.connected)
                const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('Ожидание соединения...'),
                    Padding(padding: EdgeInsets.symmetric(vertical: 8.0)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.warning_outlined,
                          color: Colors.amber,
                        ),
                        Text(
                            'При первичном подключении Вам необходимо ввести бризер в режим сопряжения.'),
                      ],
                    ),
                  ],
                ),
              if (tion.connected)
                TionStateWidget(
                  tion: tion,
                ),
              if (tion.connected)
                TionFirmwareWidget(
                  tion: tion,
                  updateStateController: updateStateController,
                ),
            ],
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          floatingActionButton: !FlutterWebBluetooth
                  .instance.isBluetoothApiSupported
              ? null
              : Builder(builder: (context) {
                  return FloatingActionButton(
                    onPressed: _requestDevice(context),
                    tooltip:
                        tion.connected ? 'Переподключиться' : 'Подключиться',
                    child: Icon(tion.connected
                        ? Icons.bluetooth_connected_outlined
                        : Icons.bluetooth_outlined),
                  );
                }),
        ),
      ),
    );
  }

  VoidCallback _requestDevice(BuildContext context) {
    _floatContext = context;
    return requestDevice;
  }

  Future<void> requestDevice() async {
    if (!FlutterWebBluetooth.instance.isBluetoothApiSupported) {
      _reportError("Отсутствует поддержка Bluetooth в браузере");
      return;
    }

    _device?.disconnect();

    try {
      _device = await FlutterWebBluetooth.instance
          .requestDevice(RequestOptionsBuilder([
        RequestFilterBuilder(services: [TionBLE.tionServiceUUID])
      ]));
      log.d("Device got! ${_device!.name}, ${_device!.id}");

      _device!.connected.listen((state) async {
        if (!state) {
          tion.disconnect();
        } else {
          final tionService = (await _device!.discoverServices())
              .firstWhere((service) => service.uuid == TionBLE.tionServiceUUID);
          log.t(tionService.uuid);

          final tionCharRx =
              await tionService.getCharacteristic(TionBLE.tionCharRxUUID);
          log.t(tionCharRx.uuid);

          await tionCharRx.startNotifications();
          log.t("Started listening notifications");

          final tionCharTx =
              await tionService.getCharacteristic(TionBLE.tionCharTxUUID);
          log.t(tionCharTx.uuid);

          tion.connect(_device!.name ?? "", tionCharRx.value,
              tionCharTx.writeValueWithResponse);
        }
        setState(() {});
      });

      await _device!.connect();
      log.i("Device ${_device!.name ?? ""} connected");
      _reportError("Подключено");
    } on BluetoothAdapterNotAvailable {
      _reportError("Отсутствует Bluetooth-адаптер");
    } on UserCancelledDialogError {
      _reportError("Подключение отменено");
    } on DeviceNotFoundError {
      _reportError("Не найдено подходящих устройств");
    } catch (e, s) {
      _reportError(e.toString());
      log.e(e, stackTrace: s);
    }
  }

  void _reportError(final String message) {
    if (_floatContext == null) {
      return;
    }
    if (!_floatContext!.mounted) {
      return;
    }
    ScaffoldMessenger.of(_floatContext!).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }
}
