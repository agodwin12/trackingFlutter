import 'package:flutter/material.dart';

class ModernBottomNavbar extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onItemTap;
  final int vehicleId;

  const ModernBottomNavbar({
    Key? key,
    required this.selectedIndex,
    required this.onItemTap,
     required this.vehicleId,
  }) : super(key: key);

  @override
  State<ModernBottomNavbar> createState() => _ModernBottomNavbarState();
}

class _ModernBottomNavbarState extends State<ModernBottomNavbar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleTap(int index) {
    _animationController.forward().then((_) {
      _animationController.reverse();
      widget.onItemTap(index);
      _navigateToScreen(index);
    });
  }

  void _navigateToScreen(int index) {
    String routeName;
    switch (index) {
      case 0:
        routeName = '/dashboard';
        break;
      case 1:
        routeName = '/track';
        break;
      case 2:
        routeName = '/trips';
        break;
      case 3:
        routeName = '/profile';
        break;
      default:
        return;
    }

    Navigator.pushNamed(
        context,
        routeName,
      arguments: widget.vehicleId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF410F).withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, -5),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 10),
            spreadRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Container(
          height: 70,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                icon: Icons.dashboard_rounded,
                label: 'Dashboard',
                index: 0,
                isSelected: widget.selectedIndex == 0,
              ),
              _buildNavItem(
                icon: Icons.map_rounded,
                label: 'Track',
                index: 1,
                isSelected: widget.selectedIndex == 1,
              ),
              _buildNavItem(
                icon: Icons.route_rounded,
                label: 'Trips',
                index: 2,
                isSelected: widget.selectedIndex == 2,
              ),
              _buildNavItem(
                icon: Icons.person_rounded,
                label: 'Profile',
                index: 3,
                isSelected: widget.selectedIndex == 3,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
    required bool isSelected,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _handleTap(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon Container
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                padding: EdgeInsets.all(isSelected ? 6 : 5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFFF410F).withOpacity(0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: isSelected ? 24 : 22,
                  color: isSelected
                      ? const Color(0xFFFF410F)
                      : const Color(0xFF9EA2AD),
                ),
              ),
              const SizedBox(height: 3),
              // Label
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                style: TextStyle(
                  fontSize: isSelected ? 10.5 : 9.5,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? const Color(0xFFFF410F)
                      : const Color(0xFF9EA2AD),
                  letterSpacing: 0.2,
                  height: 1.0,
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Active Indicator Dot
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.only(top: 1.5),
                height: 2.5,
                width: isSelected ? 18 : 0,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF410F),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}