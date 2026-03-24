import 'package:flutter/material.dart';
import 'nasira_home_page.dart';
import 'embedding_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EmbeddingService.init();
  runApp(const NasiraApp());
}

class NasiraApp extends StatelessWidget {
  const NasiraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nasira',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: const NasiraHomePage(),
    );
  }
}
