// Kopiere diesen Code in ein neues File `show_structure.dart` in lib/
// ignore_for_file: avoid_print
import 'dart:io';

void main() async {
  final dir = Directory('lib');
  print('=== LIB FOLDER ===');
  await for (final entity in dir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final relative = entity.path.replaceFirst('lib/', '');
      print(relative);
    }
  }
  print('=== END ===');
}
