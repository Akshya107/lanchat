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

class LanchatApp extends StatefulWidget {
  const LanchatApp({super.key});

  @override
  State<LanchatApp> createState() => _LanchatAppState();
}

class _LanchatAppState extends State<LanchatApp> with WidgetsBindingObserver {
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _hidden = state != AppLifecycleState.resumed;
    });
  }

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
      builder: (context, child) {
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            if (_hidden) const ColoredBox(color: gridBlack, child: SizedBox.expand()),
          ],
        );
      },
      home: const GatePage(),
    );
  }
}
