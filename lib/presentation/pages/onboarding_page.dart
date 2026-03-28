import 'package:flutter/material.dart';

import '../widgets/glass_card.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  final List<_OnboardingItem> _items = const [
    _OnboardingItem(
      title: 'Realtime Stress Insight',
      description: 'Monitor GSR and EMG signals continuously from wearable IoT sensors.',
      icon: Icons.monitor_heart_outlined,
    ),
    _OnboardingItem(
      title: 'Clinical-Grade Dashboard',
      description: 'Track trends, status levels, and medical summaries in one clean workspace.',
      icon: Icons.insights_outlined,
    ),
    _OnboardingItem(
      title: 'Personalized Health Reports',
      description: 'Generate stress snapshots and weekly summaries to support intervention.',
      icon: Icons.assignment_outlined,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onContinue,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _items.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GlassCard(
                        padding: const EdgeInsets.all(28),
                        child: Icon(item.icon, size: 90),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        item.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        item.description,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _items.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: _currentPage == index ? 26 : 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: _currentPage == index
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.primary.withValues(alpha: 0.28),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _currentPage == _items.length - 1
                    ? widget.onContinue
                    : () {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOut,
                        );
                      },
                child: Text(_currentPage == _items.length - 1 ? 'Get Started' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingItem {
  const _OnboardingItem({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;
}
