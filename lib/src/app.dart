import 'package:flutter/material.dart';

import 'spike/spike_screen.dart';

class StillApp extends StatelessWidget {
  const StillApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Still (M1 spike)',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const SpikeScreen(),
    );
  }
}
