// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

// import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:convert/convert.dart';
import 'package:logger/logger.dart';
import 'package:tion_web/firmware.dart';

import 'package:tion_web/tion.dart';
import 'package:tion_web/log.dart';

void logError(String message) {
  throw Exception(message);
}

void main() {
  test('create update start request', () async {
    const size = 0xAABB - 130;
    final startReq = TionUpdateStartReq(size);
    expect(
        startReq.data,
        Uint8List(132)
          ..buffer.asByteData().setUint32(0, size + 130, Endian.little));

    initLog(level: Level.trace);
    final tion = TionBLE();
    final dummy = StreamController<ByteData>();
    tion.connect(TionBLE.tionName4S, dummy.stream, (data) async {
      log.w(hex.encode(data));
    });

    await tion.tx(startReq);
  });

  test('list fw', () async {
    final list = await FirmwareType.br4S.list(logError);
    expect(list.length, 4);
  });

  test('sha1 webcrypto', () async {
    final list = await FirmwareType.unknown.list(logError);
    await Future.forEach(list, (fwInfo) async {
      log.i("Processing ${fwInfo.type.type} ${fwInfo.name}");
      // final fwFile = File(
      //     "../tion-firmware-gh/firmware_${fwInfo.type.type}_${fwInfo.name}.bin");
      // log.d("Processing $fwFile");
      // expect(fwFile.existsSync(), true);
      // final fwData = await fwFile.readAsBytes();
      final fwData = await fwInfo.load(logError);
      final result = await fwInfo.validate(fwData, logError);
      expect(result, true);
    });
  });

  // testWidgets('Counter increments smoke test', (WidgetTester tester) async {
  //   // Build our app and trigger a frame.
  //   await tester.pumpWidget(const MyApp());

  //   // Verify that our counter starts at 0.
  //   expect(find.text('0'), findsOneWidget);
  //   expect(find.text('1'), findsNothing);

  //   // Tap the '+' icon and trigger a frame.
  //   await tester.tap(find.byIcon(Icons.add));
  //   await tester.pump();

  //   // Verify that our counter has incremented.
  //   expect(find.text('0'), findsNothing);
  //   expect(find.text('1'), findsOneWidget);
  // });
}
