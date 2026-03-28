import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import 'dashboard_page.dart';
import 'profile_page.dart';
import 'reports_page.dart';
import 'settings_page.dart';

class HomeShellPage extends StatefulWidget {
  const HomeShellPage({super.key});

  @override
  State<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends State<HomeShellPage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    DashboardPage(),
    ReportsPage(),
    SettingsPage(),
    ProfilePage(),
  ];

  static const _titles = ['Dashboard', 'Reports', 'Settings', 'Profile'];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        centerTitle: true,
        title: Text(_titles[_selectedIndex]),
        actions: _selectedIndex == 1
            ? [
                PopupMenuButton<String>(
                  onSelected: (value) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$value (demo)')),
                    );
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'Export Report PDF', child: Text('Export Report PDF')),
                    PopupMenuItem(
                      value: 'Email Weekly Report',
                      child: Text('Email Weekly Report'),
                    ),
                    PopupMenuItem(value: 'Help & Support', child: Text('Help & Support')),
                  ],
                ),
              ]
            : const <Widget>[],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [AppColors.darkBackgroundTop, AppColors.darkBackgroundBottom]
                : const [AppColors.lightBackgroundTop, AppColors.lightBackgroundBottom],
            stops: const [0.15, 1.0],
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      Colors.white.withValues(alpha: 0.04),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.06),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.35),
                      Colors.transparent,
                      Colors.white.withValues(alpha: 0.12),
                    ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
          child: SafeArea(
            child: IndexedStack(index: _selectedIndex, children: _pages),
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (value) {
              setState(() {
                _selectedIndex = value;
              });
            },
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
              BottomNavigationBarItem(icon: Icon(Icons.assignment_rounded), label: 'Reports'),
              BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Settings'),
              BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
            ],
          ),
        ),
      ),
    );
  }
}
