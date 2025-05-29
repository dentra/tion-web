import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:http/http.dart' as http;
import 'package:webcrypto/webcrypto.dart';

import 'log.dart';
import 'tion.dart';

const _fwRepo = "dentra/tion-firmware";
const _fwBranch = "master";
const _fwPathPrefix = "https://raw.githubusercontent.com/$_fwRepo/$_fwBranch";
const _fwMeta = "$_fwPathPrefix/manifest.json";

enum FirmwareType {
  unknown(""),
  br4S("4s"),
  brLT("lt");

  final String type;
  const FirmwareType(this.type);

  factory FirmwareType.fromBrType(final String brType) {
    if (FirmwareType.br4S.type == brType) {
      return FirmwareType.br4S;
    }
    if (FirmwareType.brLT.type == brType) {
      return FirmwareType.brLT;
    }
    return FirmwareType.unknown;
  }

  factory FirmwareType.fromDevName(final String devName) {
    if (TionBLE.tionName4S == devName) {
      return FirmwareType.br4S;
    }
    if (TionBLE.tionNameLT == devName) {
      return FirmwareType.brLT;
    }
    return FirmwareType.unknown;
  }

  Future<List<FirmwareInfo>> list(void Function(String) reportError) async {
    return _loadFirmwareInfo(this, reportError);
  }

  bool get isEmpty => type.isEmpty;
  bool get isNotEmpty => type.isNotEmpty;
}

class FirmwareInfo {
  final FirmwareType type;
  final String name;
  final String path;
  final int size;
  final String hash;
  final bool like;
  final bool test;
  int get version => int.parse(name, radix: 16);

  const FirmwareInfo({
    this.type = FirmwareType.unknown,
    this.name = "",
    this.path = "",
    this.size = 0,
    this.hash = "",
    this.like = false,
    this.test = false,
  });

  factory FirmwareInfo.fromJson(final Map<String, dynamic> meta) {
    return FirmwareInfo(
      type: FirmwareType.fromBrType(meta["type"] ?? ""),
      name: meta["code"] ?? "",
      path: meta["path"] ?? "",
      size: meta["size"] ?? 0,
      hash: meta["sha1"] ?? "",
      like: meta["like"] ?? false,
      test: meta["test"] ?? false,
    );
  }

  Future<bool> validate(
      final Uint8List data, void Function(String) reportError) async {
    return _validateFirmware(this, data, reportError);
  }

  Future<Uint8List> load(void Function(String) reportError) async {
    return _loadFirmware(this, reportError);
  }
}

Future<http.Response?> _load(
    final String url, void Function(String) reportError) async {
  log.t("Loading $url");
  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) {
    reportError("statusCode ${response.statusCode}, $url");
    return null;
  }
  return response;
}

Future<T> _loadJson<T>(final String url, T Function(dynamic) transform,
    void Function(String) reportError) async {
  final response = await _load(url, reportError);
  return transform(response == null ? null : jsonDecode(response.body));
}

Future<List<FirmwareInfo>> _loadFirmwareInfo(
    final FirmwareType type, void Function(String) reportError) async {
  log.d("Loading firmware metadata for $type");

  final meta = await _loadJson(
      _fwMeta,
      (json) => List<Map<String, dynamic>>.from(json),
      (message) =>
          reportError("Ошибка загрузки метаданных прошивок: $message"));

  return meta
      .map((json) => FirmwareInfo.fromJson(json))
      .where((info) => type.isEmpty ? true : info.type == type)
      .toList();
}

Future<Uint8List> _loadFirmware(
    final FirmwareInfo info, void Function(String) reportError) async {
  log.d("Loading firmware: ${info.path}");
  Uint8List? data = (await _load("$_fwPathPrefix/${info.path}",
          (message) => reportError("Ошибка загрузки файла прошивки: $message")))
      ?.bodyBytes;

  if (data == null) {
    return Uint8List(0);
  }

  return data;
}

Future<bool> _validateFirmware(final FirmwareInfo info, final Uint8List data,
    void Function(String) reportError) async {
  log.d("Validating firmware ${info.name} metadata for ${info.type}");

  if (data.length != info.size) {
    reportError(
        "Ошибка длинны загруженного файла ${data.length}, ожидаемо ${info.size}");
    return false;
  }

  if (info.hash.isNotEmpty) {
    final digest = await Hash.sha1.digestBytes(data);
    final hash = hex.encode(digest);
    if (hash != info.hash) {
      reportError("Ошибка контрольной суммы загруженного файла: $hash");
      return false;
    }
  }

  return true;
}
