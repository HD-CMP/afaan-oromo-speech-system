import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'screens/main_navigation.dart';
import 'providers/transcription_provider.dart';
import 'providers/subtitle_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/connection_provider.dart';
import 'providers/localization_provider.dart';
import 'providers/tts_provider.dart';
import 'config/app_theme.dart';
import 'config/api_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Initialize API config from saved preferences
  await ApiConfig.initialize();
  
  runApp(const AafanOromoSTTApp());
}

class AafanOromoSTTApp extends StatefulWidget {
  const AafanOromoSTTApp({super.key});

  @override
  State<AafanOromoSTTApp> createState() => _AafanOromoSTTAppState();
}

class _AafanOromoSTTAppState extends State<AafanOromoSTTApp> {
  late TranscriptionProvider _transcriptionProvider;
  late SubtitleProvider _subtitleProvider;
  late ThemeProvider _themeProvider;
  late ConnectionProvider _connectionProvider;
  late LocalizationProvider _localizationProvider;
  late TtsProvider _ttsProvider;

  @override
  void initState() {
    super.initState();
    _transcriptionProvider = TranscriptionProvider();
    _subtitleProvider = SubtitleProvider();
    _themeProvider = ThemeProvider();
    _connectionProvider = ConnectionProvider();
    _localizationProvider = LocalizationProvider();
    _ttsProvider = TtsProvider();
    _initializeApp();
  }
  
  Future<void> _initializeApp() async {
    await _transcriptionProvider.initialize();
    await _localizationProvider.initialize();
  }

  @override
  void dispose() {
    _transcriptionProvider.dispose();
    _subtitleProvider.dispose();
    _connectionProvider.dispose();
    _ttsProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _transcriptionProvider),
        ChangeNotifierProvider.value(value: _subtitleProvider),
        ChangeNotifierProvider.value(value: _themeProvider),
        ChangeNotifierProvider.value(value: _connectionProvider),
        ChangeNotifierProvider.value(value: _localizationProvider),
        ChangeNotifierProvider.value(value: _ttsProvider),
      ],
      child: Consumer2<ThemeProvider, LocalizationProvider>(
        builder: (context, themeProvider, localizationProvider, child) {
          return MaterialApp(
            title: localizationProvider.getString('app_name'),
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const MainNavigation(),
          );
        },
      ),
    );
  }
}
