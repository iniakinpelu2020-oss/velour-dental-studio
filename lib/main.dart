import 'package:flutter/material.dart';

import 'screens/agent_chat_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/universal_auto_reply_screen.dart';
import 'screens/workflow_builder_screen.dart';
import 'services/platform_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ApexAgentApp());
}

class ApexAgentApp extends StatelessWidget {
  const ApexAgentApp({super.key});

  static const Color bg = Color(0xFF0A0E14);
  static const Color surface = Color(0xFF121923);
  static const Color surfaceAlt = Color(0xFF182233);
  static const Color accent = Color(0xFF00E5A0);
  static const Color accentSoft = Color(0xFF1A3A32);
  static const Color danger = Color(0xFFFF5C7A);
  static const Color warn = Color(0xFFFFC857);
  static const Color text = Color(0xFFE6EDF3);
  static const Color muted = Color(0xFF8B949E);

  @override
  Widget build(BuildContext context) {
    final colorScheme = const ColorScheme.dark(
      primary: accent,
      secondary: accent,
      surface: surface,
      error: danger,
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: text,
      onError: Colors.white,
    );

    return MaterialApp(
      title: 'Apex Agent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: bg,
        appBarTheme: const AppBarTheme(
          backgroundColor: bg,
          foregroundColor: text,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardTheme(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF1F2A37)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceAlt,
          labelStyle: const TextStyle(color: muted),
          hintStyle: const TextStyle(color: muted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF263241)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF263241)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: accent, width: 1.5),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: text,
            side: const BorderSide(color: Color(0xFF2B3A4D)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: surfaceAlt,
          selectedColor: accentSoft,
          labelStyle: const TextStyle(color: text),
          side: const BorderSide(color: Color(0xFF2B3A4D)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        dividerColor: const Color(0xFF1F2A37),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF0D131B),
          indicatorColor: accent.withOpacity(0.18),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              color: selected ? accent : muted,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(color: selected ? accent : muted);
          }),
        ),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await PlatformService.requestPostNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const AgentChatScreen(),
      const WorkflowBuilderScreen(),
      const UniversalAutoReplyScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: SafeArea(child: screens[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy),
            label: 'Agent',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_tree_outlined),
            selectedIcon: Icon(Icons.account_tree),
            label: 'Workflows',
          ),
          NavigationDestination(
            icon: Icon(Icons.reply_all_outlined),
            selectedIcon: Icon(Icons.reply_all),
            label: 'Auto-Reply',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
