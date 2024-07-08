// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:async';
import 'dart:typed_data';

// import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:convert/convert.dart';
import 'package:logger/logger.dart';

import 'package:tion_web/tion.dart';
import 'package:tion_web/log.dart';

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
