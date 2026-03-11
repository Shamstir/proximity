import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:touch/screens/home_screen.dart';
import 'package:touch/services/mesh_service.dart';
import 'package:touch/services/nfc_service.dart';
import 'package:touch/utils/constants.dart';


void main() {
  runApp(
    MultiProvider(
      providers: [
        Provider<MeshService>(create: (_) => MeshService()),
        Provider<NfcService>(create: (_) => NfcService()),
      ],
      child: const TouchKeyApp(),
    ),
  );
}

class TouchKeyApp extends StatelessWidget {
  const TouchKeyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PROXIMITY',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      home: const HomeScreen(),
    );
  }
}
