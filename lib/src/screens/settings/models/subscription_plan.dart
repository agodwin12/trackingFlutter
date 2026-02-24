class SubscriptionPlan {
  final String id;
  final String nameEn;
  final String nameFr;
  final int months;
  final double price;
  final String? savingsEn;
  final String? savingsFr;

  SubscriptionPlan({
    required this.id,
    required this.nameEn,
    required this.nameFr,
    required this.months,
    required this.price,
    this.savingsEn,
    this.savingsFr,
  });
}

// Static data for the UI
final List<SubscriptionPlan> staticPlans = [
  SubscriptionPlan(
    id: '1_month',
    nameEn: '1 Month',
    nameFr: '1 Mois',
    months: 1,
    price: 5000,
  ),
  SubscriptionPlan(
    id: '3_months',
    nameEn: '3 Months',
    nameFr: '3 Mois',
    months: 3,
    price: 13500,
    savingsEn: 'Save 10%',
    savingsFr: 'Économisez 10%',
  ),
  SubscriptionPlan(
    id: '6_months',
    nameEn: '6 Months',
    nameFr: '6 Mois',
    months: 6,
    price: 25000,
    savingsEn: 'Save 15%',
    savingsFr: 'Économisez 15%',
  ),
  SubscriptionPlan(
    id: '1_year',
    nameEn: '1 Year',
    nameFr: '1 An',
    months: 12,
    price: 45000,
    savingsEn: 'Best Value - 25% Off',
    savingsFr: 'Meilleure offre - 25%',
  ),
];