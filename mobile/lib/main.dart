import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'terminal_page.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: gridBlack,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: gridBlack,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const LanchatApp());
}

class LanchatApp extends StatelessWidget {
  const LanchatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LANCHAT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: gridBlack,
        colorScheme: const ColorScheme.dark(
          primary: gridGreen,
          surface: gridBlack,
        ),
      ),
      home: const GatePage(),
    );
  }
}
