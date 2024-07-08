import 'dart:async';
import 'dart:typed_data';

import 'package:crclib/catalog.dart';
import 'package:convert/convert.dart';

import 'log.dart';

abstract class TionCommand {
  final Uint8List _data;

  int get code;
  Uint8List get data => _data;

  String get codeHex => code.toRadixString(16).padLeft(4, '0');

  TionCommand(this._data);

  factory TionCommand.fromRsp(final int cmd, final Uint8List data) {
    final call = _tionCommandsRsp[cmd];
    if (call != null) {
      return call(data);
    }
    log.w(
        "Response command not found: ${cmd.toRadixString(16).padLeft(4, '0')}");
    return TionUnknownCommand(cmd, data);
  }
}

class TionUnknownCommand extends TionCommand {
  final int _code;

  @override
  int get code => _code;

  TionUnknownCommand(this._code, super._data);
}

final Map<int, TionCommand Function(Uint8List)> _tionCommandsRsp = {
  TionUpdateInitRsp.id: (data) => TionUpdateInitRsp(data),
  TionUpdateStartRsp.id: (data) => TionUpdateStartRsp(data),
  TionUpdateChunkRsp.id: (data) => TionUpdateChunkRsp(data),
  TionUpdateFinishRsp.id: (data) => TionUpdateFinishRsp(data),
  TionUpdateErrorRsp.id: (data) => TionUpdateErrorRsp(data),
  TionDevInfoRsp4S.id: (data) => TionDevInfoRsp4S(data),
  TionDevInfoRspLT.id: (data) => TionDevInfoRspLT(data),
  TionStateRsp4S.id: (data) => TionStateRsp4S(data),
  TionStateRspLT.id: (data) => TionStateRspLT(data),
};

class TionBLE {
  static const String tionServiceUUID = "98f00001-3788-83ea-453e-f52244709ddb";
  static const String tionCharTxUUID = "98f00002-3788-83ea-453e-f52244709ddb";
  static const String tionCharRxUUID = "98f00003-3788-83ea-453e-f52244709ddb";

  static const String tionName4S = "Breezer 4S";
  static const String tionNameLT = "Br Lite";

  static const maxMTUsize = 20;
  static const maxDataSize = maxMTUsize - 1;

  static const frameMagic = 0x3a;
  static const frameRandom = 0xad;

  // first packet. 0x00
  static const pktTypeFirst = 0 << 6;
  // n-th packet. 0x40
  static const pktTypeCurrent = 1 << 6;
  // first and last packet at the same time. 0x80
  static const pktTypeSingle = 2 << 6;
  // last packet 0xC0
  static const pktTypeLast = 3 << 6;

  Uint8List _rxBuf = Uint8List(0);

  final _rxController = StreamController<TionCommand>.broadcast();
  StreamSubscription<ByteData>? _rxSubscription;

  Stream<TionCommand> get rx => _rxController.stream;

  Future<void> Function(Uint8List data) _bleTx = _emptyBleTx;

  String _devName = "";

  String get devName => _devName;

  bool get connected => _devName.isNotEmpty;

  static Future<void> _emptyBleTx(final Uint8List data) async {
    log.w("Not connected");
  }

  Future<void> connect(final String devName, final Stream<ByteData> bleRx,
      Future<void> Function(Uint8List data) bleTx) async {
    disconnect();
    _devName = devName;
    _bleTx = bleTx;
    _rxSubscription = bleRx.listen((data) => _rxRaw(data.buffer.asUint8List()));
  }

  void disconnect() {
    _rxSubscription?.cancel();
    _bleTx = _emptyBleTx;
    _devName = "";
  }

  int calcCRC(Uint8List data) {
    return Crc16CcittFalse().convert(data).toBigInt().toInt();
  }

  void _rxFrame(Uint8List data) {
    log.t(() => "RX[frame]: ${hex.encode(data)} (${data.length})");

    final magic = data[2];
    if (magic != frameMagic) {
      log.e("Invalid frame magic: $magic");
      return;
    }

    final size = ByteData.view(data.buffer, 0, 2).getUint16(0, Endian.little);
    if (size != data.length) {
      log.e("Invalid frame size: $size");
      return;
    }

    if (calcCRC(data) != 0) {
      log.e("Invalid frame CRC");
      return;
    }

    final cmd = ByteData.view(data.buffer, 4, 2).getUint16(0, Endian.little);
    // also skip ble_request_id
    final rsp = data.sublist(10, data.length - 2);
    log.t(() =>
        "RX[cmd]: ${cmd.toRadixString(16).padLeft(4, '0')}, ${hex.encode(rsp)}");

    _rxController.add(TionCommand.fromRsp(cmd, rsp));
  }

  void _rxRaw(Uint8List value) {
    log.t(() => "RX[raw]: ${hex.encode(value)}");

    final type = value[0];
    final data = value.sublist(1);

    if (type == pktTypeSingle) {
      _rxFrame(data);
      return;
    }

    if (type == pktTypeFirst) {
      _rxBuf = data;
      return;
    }

    final tmp = Uint8List.fromList(_rxBuf + data);

    if (type == pktTypeCurrent) {
      _rxBuf = tmp;
      return;
    }

    if (type == pktTypeLast) {
      _rxFrame(tmp);
      _rxBuf = Uint8List(0);
      return;
    }

    log.e("Unknown packet type: $type");
  }

  Future<void> _txBuf(final int pktType, final Uint8List data) async {
    final toSend = Uint8List.fromList([pktType] + data);
    log.t(() => "TX[raw]: ${hex.encode(toSend)} (${toSend.length})");
    await _bleTx(toSend);
  }

  Future<void> _txRaw(final Uint8List value) async {
    var data = value;
    var size = value.length;
    var dataPacketSize = maxDataSize;

    pktProcess(final int morePkt, final int lessPkt) async {
      dataPacketSize = size > dataPacketSize ? dataPacketSize : size;
      size -= dataPacketSize;
      await _txBuf(
          size > 0 ? morePkt : lessPkt, data.sublist(0, dataPacketSize));
      data = data.sublist(dataPacketSize);
    }

    await pktProcess(pktTypeFirst, pktTypeSingle);
    while (size > 0) {
      await pktProcess(pktTypeCurrent, pktTypeLast);
    }
  }

  Future<void> _txFrame(final int cmd, final Uint8List data) async {
    final frameData = Uint8List(data.length + 12);

    final frame = frameData.buffer.asByteData();
    frame.setUint16(0, frame.lengthInBytes, Endian.little);
    frame.setUint8(2, frameMagic);
    frame.setUint8(3, frameRandom);
    frame.setUint16(4, cmd, Endian.little);
    frame.setUint32(6, 1, Endian.little); // ble_request_id

    frameData.setAll(10, data);

    frame.setUint16(10 + data.length,
        calcCRC(frameData.sublist(0, frameData.length - 2)), Endian.big);

    log.t(() => "TX[frame]: ${hex.encode(frameData)} (${frameData.length})");

    await _txRaw(frameData);
  }

  Future<void> tx(final TionCommand cmd) async {
    log.d(() =>
        "TX[cmd]: ${cmd.codeHex}, ${hex.encode(cmd.data)} (${cmd.data.length})");
    await _txFrame(cmd.code, cmd.data);
  }

  Future<void> reqState() async {
    await tx(TionStateReq.fromDevName(_devName));
  }

  Future<void> reqDevInfo() async {
    await tx(TionDevInfoReq.fromDevName(_devName));
  }
}

enum TionWorkMode { unknown, normal, update }

enum TionDeviceType { unknown, br4S, brLT }

abstract class TionDevInfoRsp extends TionCommand {
  late TionWorkMode workMode;
  late TionDeviceType deviceType;
  late int firmwareVersion;
  late int hardwareVersion;

  String get firmwareVersionHex =>
      firmwareVersion.toRadixString(16).padLeft(4, '0').toUpperCase();
  String get hardwareVersionHex =>
      hardwareVersion.toRadixString(16).padLeft(4, '0').toUpperCase();

  TionDevInfoRsp(super._data) {
    // 01 0380 0000 0c13 0861 0000 0000000000000000000000000000
    workMode = data[0] == 1
        ? TionWorkMode.normal
        : data[0] == 2
            ? TionWorkMode.update
            : TionWorkMode.unknown;
    final ByteData bd = ByteData.view(data.buffer);

    final devType = bd.getUint16(1, Endian.little);

    deviceType = devType == 0x8003
        ? TionDeviceType.br4S
        : devType == 0x8002
            ? TionDeviceType.brLT
            : TionDeviceType.unknown;
    firmwareVersion = bd.getUint16(5, Endian.little);
    hardwareVersion = bd.getUint16(7, Endian.little);
  }
}

class TionDevInfoRsp4S extends TionDevInfoRsp {
  static const int id = 0x3331;
  @override
  int get code => id;

  TionDevInfoRsp4S(super._data);
}

abstract class _TionEmptyReq extends TionCommand {
  _TionEmptyReq() : super(Uint8List(0));
}

abstract class TionDevInfoReq extends _TionEmptyReq {
  TionDevInfoReq();
  factory TionDevInfoReq.fromDevName(final String devName) {
    if (devName == TionBLE.tionNameLT) {
      return TionDevInfoReqLT();
    }
    return TionDevInfoReq4S();
  }
}

class TionDevInfoReq4S extends TionDevInfoReq {
  static const int id = 0x3332;
  @override
  int get code => id;
}

class TionDevInfoRspLT extends TionDevInfoRsp {
  static const int id = 0x400a;
  @override
  int get code => id;

  TionDevInfoRspLT(super._data);
}

class TionDevInfoReqLT extends TionDevInfoReq {
  static const int id = 0x4009;
  @override
  int get code => id;
}

abstract class TionState extends TionCommand {
  late int fanSpeed;
  late bool powerState;
  late bool heaterState;
  late bool soundState;
  late bool ledState;
  late int targetTemperature;
  late int currentTemperature;
  late int outdoorTemperature;
  TionState(super._data);
}

abstract class TionStateReq extends _TionEmptyReq {
  TionStateReq();

  factory TionStateReq.fromDevName(final String devName) {
    if (devName == TionBLE.tionNameLT) {
      return TionStateReqLT();
    }
    return TionStateReq4S();
  }
}

class TionStateRsp4S extends TionState {
  static const int id = 0x3231;
  @override
  int get code => id;

  TionStateRsp4S(super._data) {
    final ByteData bd = data.buffer.asByteData(4); // skip req_id
    final flags = bd.getUint8(0);
    powerState = (flags & (1 << 0)) != 0;
    soundState = (flags & (1 << 1)) != 0;
    ledState = (flags & (1 << 2)) != 0;
    heaterState = (flags & (1 << 4)) == 0;
    // final gatePos = bd.getUint8(2);
    targetTemperature = bd.getInt8(4);
    fanSpeed = bd.getUint8(4);
    outdoorTemperature = bd.getInt8(5);
    currentTemperature = bd.getInt8(6);
  }
}

class TionStateReq4S extends TionStateReq {
  static const int id = 0x3232;
  @override
  int get code => id;
}

class TionStateRspLT extends TionState {
  static const int id = 0x1231;
  @override
  int get code => id;

  TionStateRspLT(super._data) {
    final ByteData bd = data.buffer.asByteData(4); // skip req_id
    final flags = bd.getUint8(0);
    powerState = (flags & (1 << 0)) != 0;
    soundState = (flags & (1 << 1)) != 0;
    ledState = (flags & (1 << 2)) != 0;
    heaterState = (flags & (1 << 6)) == 0;
    // final gatePos = bd.getUint8(2);
    targetTemperature = bd.getInt8(3);
    fanSpeed = bd.getUint8(4);
    outdoorTemperature = bd.getInt8(5);
    currentTemperature = bd.getInt8(6);
  }
}

class TionStateReqLT extends TionStateReq {
  static const int id = 0x1232;
  @override
  int get code => id;
}

// Шаг 1. Запрос на подготовку бризера к обновлению.
// Пакет пустой.
class TionUpdateInitReq extends _TionEmptyReq {
  static const int id = 0x400e;

  @override
  int get code => id;
}

// Ответ на запрос о готовности принимать данные прошивки.
// Содержимое пакета: структура firmware_versions_t.
class TionUpdateInitRsp extends TionCommand {
  static const int id = 0x4004;

  @override
  int get code => id;

  int get deviceType => data.buffer.asByteData().getUint32(0, Endian.little);
  int get unknown => data.buffer.asByteData().getUint16(4, Endian.little);
  int get hardwareVersion =>
      data.buffer.asByteData().getUint16(6, Endian.little);

  TionUpdateInitRsp(super._data);
}

abstract class _TionUpdateFirmwareInfoCommand extends TionCommand {
  _TionUpdateFirmwareInfoCommand(int firmwareSize) : super(Uint8List(132)) {
    _data.buffer.asByteData().setUint32(0, firmwareSize + 130, Endian.little);
  }
}

// Шаг 2. Запрос старта обновления.
// Содержимое пакета: структура firmware_info_t.
class TionUpdateStartReq extends _TionUpdateFirmwareInfoCommand {
  static const int id = 0x4005;

  @override
  int get code => id;

  TionUpdateStartReq(super.firmwareSize);
}

// Подтверждение готовности к приему прошивки.
class TionUpdateStartRsp extends TionCommand {
  static const int id = 0x400c;

  @override
  int get code => id;

  TionUpdateStartRsp(super._data);
}

// Шаг 3. Отправка части прошивки.
// Содержимое певрго пакета: структура firmware_chunk_t.
// Содержимое последнего пакета: структура firmware_chunk_crc_t.
class TionUpdateChunkReq extends TionCommand {
  static const int id = 0x4006;

  @override
  int get code => id;

  TionUpdateChunkReq(int offset, Uint8List data)
      : super(Uint8List.fromList((Uint8List(4)
              ..buffer.asByteData().setUint32(0, offset, Endian.little)) +
            data));
}

// Подтверждение приема части прошивки.
// Пакет пустой.
class TionUpdateChunkRsp extends TionCommand {
  static const int id = 0x400b;

  @override
  int get code => id;

  TionUpdateChunkRsp(super._data);
}

// Шаг N (финальный). Верификация прошивки.
// Содержимое пакета: структура firmware_info_t.
class TionUpdateFinishReq extends _TionUpdateFirmwareInfoCommand {
  static const int id = 0x4007;

  @override
  int get code => id;

  TionUpdateFinishReq(super.firmwareSize);
}

// Прошивка успешно установилась.
// Пакет пустой.
class TionUpdateFinishRsp extends TionCommand {
  static const int id = 0x400d;

  @override
  int get code => id;

  TionUpdateFinishRsp(super._data);
}

// Ошибка обновления прошивки.
// Пакет пока неизвестен.
class TionUpdateErrorRsp extends TionCommand {
  static const int id = 0x4008;

  @override
  int get code => id;

  TionUpdateErrorRsp(super._data);
}
