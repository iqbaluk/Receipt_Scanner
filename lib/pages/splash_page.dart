part of '../main.dart';

class StartupSplashPage extends StatefulWidget {
  const StartupSplashPage({super.key});

  @override
  State<StartupSplashPage> createState() => _StartupSplashPageState();
}

class _StartupSplashPageState extends State<StartupSplashPage> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ProjectListPage()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.primary,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: colorScheme.onPrimary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: colorScheme.onPrimary.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Icon(
                    Icons.receipt_long,
                    size: 46,
                    color: colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Fast Flow AI Ltd',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '(Invoices Scanner)',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onPrimary.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 34),
                SizedBox(
                  width: 220,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(seconds: 2),
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(99),
                      backgroundColor:
                          colorScheme.onPrimary.withValues(alpha: 0.2),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
