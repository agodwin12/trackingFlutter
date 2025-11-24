// lib/src/screens/onboarding/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utility/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  String _selectedLanguage = 'en';

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language') ?? 'en';
    });
    debugPrint('✅ Onboarding screen loaded language preference: $_selectedLanguage');
  }

  List<OnboardingPage> get _pages => [
    OnboardingPage(
      title: _selectedLanguage == 'en'
          ? 'Welcome to PROXYM TRACKING'
          : 'Bienvenue sur PROXYM TRACKING',
      description: _selectedLanguage == 'en'
          ? 'Track your vehicle in real-time and monitor every movement with precision.'
          : 'Suivez votre véhicule en temps réel et surveillez chaque mouvement avec précision.',
      image: 'assets/onboarding1.png',
      backgroundColor: AppColors.primaryLight,
    ),
    OnboardingPage(
      title: _selectedLanguage == 'en'
          ? 'Real-Time Location'
          : 'Localisation en temps réel',
      description: _selectedLanguage == 'en'
          ? 'Get live updates of your vehicle\'s location with accurate GPS tracking.'
          : 'Obtenez des mises à jour en direct de la position de votre véhicule avec un suivi GPS précis.',
      image: 'assets/onboarding2.jpg',
      backgroundColor: AppColors.success.withOpacity(0.1),
    ),
    OnboardingPage(
      title: _selectedLanguage == 'en'
          ? 'Trip History & Analytics'
          : 'Historique et analyse des trajets',
      description: _selectedLanguage == 'en'
          ? 'View detailed trip history, statistics, and driving patterns.'
          : 'Consultez l\'historique détaillé des trajets, les statistiques et les habitudes de conduite.',
      image: 'assets/onboarding3.jpg',
      backgroundColor: AppColors.info.withOpacity(0.1),
    ),
    OnboardingPage(
      title: _selectedLanguage == 'en'
          ? 'Ready to Start?'
          : 'Prêt à commencer ?',
      description: _selectedLanguage == 'en'
          ? 'Let\'s begin your journey with smart vehicle tracking!'
          : 'Commençons votre voyage avec un suivi intelligent de véhicule !',
      image: 'assets/onboarding4.jpg',
      backgroundColor: AppColors.primary.withOpacity(0.2),
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _skipOnboarding() {
    _completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Skip Button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.all(AppSizes.spacingM),
                child: TextButton(
                  onPressed: _skipOnboarding,
                  child: Text(
                    _selectedLanguage == 'en' ? 'Skip' : 'Passer',
                    style: AppTypography.body2.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

            // PageView
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  return _buildPage(_pages[index]);
                },
              ),
            ),

            // Pagination Dots
            Padding(
              padding: EdgeInsets.symmetric(vertical: AppSizes.spacingL),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pages.length,
                      (index) => _buildDot(index),
                ),
              ),
            ),

            // Next Button
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSizes.spacingL,
                0,
                AppSizes.spacingL,
                AppSizes.spacingXL,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _nextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _currentPage == _pages.length - 1
                        ? AppColors.primary
                        : AppColors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusL),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _currentPage == _pages.length - 1
                            ? (_selectedLanguage == 'en' ? 'Get Started' : 'Commencer')
                            : (_selectedLanguage == 'en' ? 'Next' : 'Suivant'),
                        style: AppTypography.button.copyWith(
                          color: _currentPage == _pages.length - 1
                              ? AppColors.black
                              : AppColors.white,
                        ),
                      ),
                      SizedBox(width: AppSizes.spacingS),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: _currentPage == _pages.length - 1
                            ? AppColors.black
                            : AppColors.white,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(OnboardingPage page) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.spacingL),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Image Container
          Container(
            height: MediaQuery.of(context).size.height * 0.45,
            width: double.infinity,
            decoration: BoxDecoration(
              color: page.backgroundColor,
              borderRadius: BorderRadius.circular(AppSizes.radiusXL),
            ),
            child: Center(
              child: Image.asset(
                page.image,
                height: 250,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  // Fallback icon if image not found
                  return Container(
                    padding: EdgeInsets.all(AppSizes.spacingXL),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.directions_car_rounded,
                      size: 120,
                      color: AppColors.primary,
                    ),
                  );
                },
              ),
            ),
          ),

          SizedBox(height: AppSizes.spacingXL + 8),

          // Title
          Text(
            page.title,
            style: AppTypography.h1.copyWith(
              fontSize: 28,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: AppSizes.spacingM),

          // Description
          Text(
            page.description,
            style: AppTypography.body2.copyWith(
              height: 1.6,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: EdgeInsets.symmetric(horizontal: AppSizes.spacingXS / 2),
      width: _currentPage == index ? 32 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: _currentPage == index
            ? AppColors.primary
            : AppColors.border,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class OnboardingPage {
  final String title;
  final String description;
  final String image;
  final Color backgroundColor;

  OnboardingPage({
    required this.title,
    required this.description,
    required this.image,
    required this.backgroundColor,
  });
}