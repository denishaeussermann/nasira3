import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'embedding_service.dart';
import 'nasira_app_state.dart';
import 'screens/startseite_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EmbeddingService.init();
  runApp(
    ChangeNotifierProvider(
      create: (_) => NasiraAppState(),
      child: const NasiraApp(),
    ),
  );
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
      home: const StartseiteScreen(),
    );
  }
}
