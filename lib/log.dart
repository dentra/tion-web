import 'package:logger/logger.dart';

final log = Logger();

void initLog({Level level = Level.info}) {
  Logger.level = level;
}
