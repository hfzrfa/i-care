import 'package:flutter/material.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const useFirebase = bool.fromEnvironment('USE_FIREBASE', defaultValue: true);
  const useMockSensor = bool.fromEnvironment('USE_MOCK_SENSOR', defaultValue: true);
  runApp(
    const MyApp(
      initializeFirebase: useFirebase,
      useMockSensor: useMockSensor,
    ),
  );
}
