import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:http/browser_client.dart';
import 'package:http/http.dart';
import 'package:cryptography/cryptography.dart';

import 'tion.dart';
import 'log.dart';

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
}

class FirmwareInfo {
  final FirmwareType type;
  final String name;
  final String path;
  final int size;
  final String hash;
  final bool fav;
  final bool test;
  int get version => int.parse(name, radix: 16);
  const FirmwareInfo({
    required this.type,
    required this.name,
    required this.path,
    required this.size,
    required this.hash,
    required this.fav,
    required this.test,
  });
  factory FirmwareInfo.fromJson(final Map<String, dynamic> meta) {
    return FirmwareInfo(
      type: FirmwareType.fromBrType(meta["type"] ?? ""),
      name: meta["code"] ?? "",
      path: meta["path"] ?? "",
      size: meta["size"] ?? 0,
      hash: meta["sha1"] ?? "",
      fav: meta["fav"] ?? false,
      test: meta["test"] ?? false,
    );
  }
}

Future<Response?> _load(
    final String url, void Function(String) reportError) async {
  log.t("Loading $url");
  final client = BrowserClient();
  final response = await client.get(Uri.parse(url));
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

Future<List<FirmwareInfo>> loadFirmwareInfo(
    final FirmwareType type, void Function(String) reportError) async {
  log.d("Loading firmware metadata for $type");

  final meta = await _loadJson(
      _fwMeta,
      (json) => List<Map<String, dynamic>>.from(json),
      (message) =>
          reportError("Ошибка загрузки метаданных прошивок: $message"));

  return meta
      .map((json) => FirmwareInfo.fromJson(json))
      .where((info) => info.type == type)
      .toList();
}

Future<Uint8List> loadFirmware(
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

Future<bool> validateFirmware(final FirmwareInfo info, final Uint8List data,
    void Function(String) reportError) async {
  log.d("Validating firmware ${info.name} metadata for ${info.type}");

  if (data.length != info.size) {
    reportError(
        "Не соответсвующая длинна загруженного файла ${data.length}, ожидаемо ${info.size}");
    return false;
  }

  if (info.hash.isNotEmpty) {
    final algorithm = Sha1();
    final hash = hex.encode((await algorithm.hash(data)).bytes);
    if (hash != info.hash) {
      reportError(
          "Не соответсвующая контрольная сумма загруженного файла: $hash");
      return false;
    }
  }

  return true;
}
