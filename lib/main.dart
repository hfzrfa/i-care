import 'package:flutter/material.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const useFirebase = bool.fromEnvironment('USE_FIREBASE', defaultValue: true);
  runApp(const MyApp(initializeFirebase: useFirebase));
}
