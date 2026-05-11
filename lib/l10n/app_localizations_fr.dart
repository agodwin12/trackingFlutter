// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appName => 'Recouvrement';

  @override
  String get navHome => 'Accueil';

  @override
  String get navHistory => 'Historique';

  @override
  String get navProfile => 'Profil';

  @override
  String get loadingLeaseData => 'Chargement des données de leasing...';

  @override
  String get retry => 'Réessayer';

  @override
  String get errorRequestTimedOut => 'Délai dépassé. Veuillez réessayer.';

  @override
  String errorConnection(String error) {
    return 'Erreur de connexion : $error';
  }

  @override
  String errorFailedToLoadLeases(int code) {
    return 'Échec du chargement des données de leasing ($code)';
  }

  @override
  String get logout => 'Déconnexion';

  @override
  String get logoutConfirmTitle => 'Se déconnecter';

  @override
  String get logoutConfirmMessage =>
      'Êtes-vous sûr de vouloir vous déconnecter ?';

  @override
  String get cancel => 'Annuler';

  @override
  String get recouvrementTitle => 'RECOUVREMENT';

  @override
  String get proxymGroup => 'PROXYM GROUP';

  @override
  String get statusPaid => 'Payé';

  @override
  String get statusPartial => 'Partiel';

  @override
  String get statusUnpaid => 'Impayé';

  @override
  String get statusHoliday => 'Férié';

  @override
  String get statusNoLease => 'Sans leasing';

  @override
  String get statusUpcoming => 'À venir';

  @override
  String get statTotalDue => 'Total Dû';

  @override
  String get statTotalPaid => 'Total Payé';

  @override
  String get statUnpaid => 'Impayé';

  @override
  String get summaryTitle => 'RÉSUMÉ DES PAIEMENTS';

  @override
  String get localTime => 'HEURE LOCALE';

  @override
  String get nextPayIn => 'PROCHAIN PAIEMENT';

  @override
  String get hrsMinSec => 'h : min : s';

  @override
  String get sectionTodayPayments => 'PAIEMENTS DU JOUR';

  @override
  String get sectionOutstandingPayments => 'PAIEMENTS EN ATTENTE';

  @override
  String get pendingPayments => 'Paiements en attente';

  @override
  String get echeances => 'échéances';

  @override
  String get mainContract => 'Contrat principal';

  @override
  String get subContract => 'Sous-contrat';

  @override
  String get payAll => 'Tout payer';

  @override
  String get todayLease => 'LEASING DU JOUR';

  @override
  String get due => 'Échéance :';

  @override
  String get paid => 'Payé :';

  @override
  String get remaining => 'Restant :';

  @override
  String get tapToPayNow => 'Appuyer pour payer';

  @override
  String get unpaidLeasesTitle => 'Leasings Impayés';

  @override
  String unpaidLeasesPending(int count, String plural) {
    return '$count paiement$plural en attente';
  }

  @override
  String get pay => 'Payer';

  @override
  String contrat(int id) {
    return 'Contrat #$id';
  }

  @override
  String get historyTitle => 'Historique des Leasings';

  @override
  String get historySubtitle => 'Calendrier & relevés de paiement';

  @override
  String get tabCalendar => 'Calendrier';

  @override
  String get tabRecords => 'Relevés';

  @override
  String get statDaysPaid => 'Jours Payés';

  @override
  String get statMissed => 'Manqués';

  @override
  String get statTotalPaidShort => 'Total Payé';

  @override
  String days(int n) {
    return '$n jours';
  }

  @override
  String get allUpToDate => 'Tous les paiements sont à jour !';

  @override
  String get nextPaymentDue => 'Prochain Paiement Dû';

  @override
  String get amount => 'Montant';

  @override
  String get legendPaid => 'Payé';

  @override
  String get legendUnpaid => 'Impayé';

  @override
  String get legendPartial => 'Partiel';

  @override
  String get legendToday => 'Aujourd\'hui';

  @override
  String get detailExpected => 'Attendu';

  @override
  String get detailPaid => 'Payé';

  @override
  String get detailRemaining => 'Restant';

  @override
  String get detailReference => 'Référence';

  @override
  String get detailPaidAt => 'Payé le';

  @override
  String get detailMethod => 'Méthode';

  @override
  String payNowAmount(String amount) {
    return 'Payer $amount XAF maintenant';
  }

  @override
  String get noRecordsYet => 'Aucun relevé';

  @override
  String get allRecords => 'TOUS LES RELEVÉS';

  @override
  String get summaryRecords => 'Relevés';

  @override
  String get summaryPaid => 'Payés';

  @override
  String get summaryUnpaid => 'Impayés';

  @override
  String get summaryPartial => 'Partiels';

  @override
  String get payLeaseTitle => 'Payer le Leasing';

  @override
  String get payLeaseSubtitle => 'Sélectionner les leasings à payer';

  @override
  String get allCaughtUp => 'Tout est à jour !';

  @override
  String get noOutstandingLeases =>
      'Vous n\'avez aucun paiement de leasing en attente.';

  @override
  String get backToDashboard => 'Retour au tableau de bord';

  @override
  String get sectionOutstandingLeases => 'LEASINGS EN ATTENTE';

  @override
  String get deselectAll => 'Tout désélectionner';

  @override
  String get selectAll => 'Tout sélectionner';

  @override
  String leasesSelected(int count, String plural) {
    return '$count leasing$plural sélectionné$plural';
  }

  @override
  String get totalToPay => 'Total à payer';

  @override
  String get sectionMobileMoneyNumber => 'NUMÉRO MOBILE MONEY';

  @override
  String get mobileMoneyNumber => 'Numéro Mobile Money';

  @override
  String get auto => 'Auto';

  @override
  String get sectionPaymentMethod => 'MÉTHODE DE PAIEMENT';

  @override
  String get mtnMobileMoney => 'MTN Mobile Money';

  @override
  String get mtnTagline => 'Payer avec MTN MoMo';

  @override
  String get orangeMoney => 'Orange Money';

  @override
  String get orangeTagline => 'Payer avec Orange Money';

  @override
  String get paygateInfo =>
      'PayGate s\'ouvrira dans l\'application. Gardez votre téléphone accessible pour la demande de paiement.';

  @override
  String get selectAtLeastOneLease => 'Sélectionnez au moins un leasing';

  @override
  String get selectPaymentMethod => 'Sélectionnez une méthode de paiement';

  @override
  String payVia(String amount, String provider) {
    return 'Payer $amount XAF via $provider';
  }

  @override
  String get closePaymentTitle => 'Fermer le paiement ?';

  @override
  String get closePaymentMessage =>
      'Si vous fermez maintenant, votre paiement pourrait ne pas être confirmé. Êtes-vous sûr ?';

  @override
  String get stay => 'Rester';

  @override
  String get closeAnyway => 'Fermer quand même';

  @override
  String get failedToLoadPaymentPage =>
      'Échec du chargement de la page de paiement';

  @override
  String get checkConnectionRetry => 'Vérifiez votre connexion et réessayez.';

  @override
  String get goBack => 'Retour';

  @override
  String get confirmingPayment => 'Confirmation du paiement';

  @override
  String waitingForProvider(String provider) {
    return 'En attente de confirmation par $provider.\nCela prend généralement quelques secondes.';
  }

  @override
  String checkingIn(int seconds, int attempt, int max) {
    return 'Vérification dans ${seconds}s (tentative $attempt/$max)';
  }

  @override
  String get doNotCloseApp =>
      'Ne fermez pas l\'application.\nVotre paiement est en cours de traitement.';

  @override
  String get summaryAmount => 'Montant';

  @override
  String get summaryMethod => 'Méthode';

  @override
  String summaryLeases(int count, String plural) {
    return '$count paiement$plural';
  }

  @override
  String get summaryReference => 'Référence';

  @override
  String get summaryStatus => 'Statut';

  @override
  String get paymentConfirmed => 'Paiement Confirmé !';

  @override
  String paymentConfirmedSubtitle(
      int count, String plural, String plural2, String provider) {
    return '$count leasing$plural payé$plural2 avec succès via $provider.';
  }

  @override
  String get amountPaid => 'Montant Payé';

  @override
  String leasesConfirmed(int count, String plural) {
    return '$count confirmé$plural';
  }

  @override
  String get confirmed => '✅ Confirmé';

  @override
  String get stillProcessing => 'Toujours en cours';

  @override
  String get stillProcessingSubtitle =>
      'Nous n\'avons pas encore pu confirmer votre paiement.\nCela peut prendre quelques minutes selon votre réseau.';

  @override
  String get whatToDo => 'Que faire :';

  @override
  String get timeoutStep1 =>
      '1. Vérifiez vos SMS pour une confirmation de paiement';

  @override
  String get timeoutStep2 =>
      '2. Ouvrez l\'onglet Historique pour vérifier le statut';

  @override
  String get timeoutStep3 => '3. En cas de doute, contactez votre partenaire';

  @override
  String get checkHistory => 'Voir l\'historique';

  @override
  String get profileTitle => 'Mon Profil';

  @override
  String get profileSubtitle => 'Infos du compte & contrat';

  @override
  String get changePasswordTitle => 'Changer le mot de passe';

  @override
  String get changePasswordSubtitle =>
      'Mettre à jour vos identifiants de sécurité';

  @override
  String get sectionAccountInfo => 'INFORMATIONS DU COMPTE';

  @override
  String get fieldFullName => 'Nom complet';

  @override
  String get fieldEmail => 'Email';

  @override
  String get fieldPhone => 'Téléphone';

  @override
  String get fieldCity => 'Ville';

  @override
  String get fieldQuartier => 'Quartier';

  @override
  String get sectionContractDetails => 'DÉTAILS DU CONTRAT';

  @override
  String contractHeader(int id, String frequency) {
    return 'Contrat #$id · $frequency';
  }

  @override
  String get repaymentProgress => 'Progression du remboursement';

  @override
  String paidAmount(String amount) {
    return 'Payé : $amount XAF';
  }

  @override
  String remainingAmount(String amount) {
    return 'Restant : $amount XAF';
  }

  @override
  String get contractTotalAmount => 'Montant Total';

  @override
  String get contractPerPayment => 'Par Paiement';

  @override
  String get contractFrequency => 'Fréquence';

  @override
  String get contractStartDate => 'Date de début';

  @override
  String get contractEndDate => 'Date de fin';

  @override
  String get contractNextDue => 'Prochaine échéance';

  @override
  String get contractRegisteredBy => 'Enregistré par';

  @override
  String get sectionSettings => 'PARAMÈTRES';

  @override
  String get settingsChangePassword => 'Changer le mot de passe';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get signOutConfirmTitle => 'Se déconnecter';

  @override
  String get signOutConfirmMessage =>
      'Êtes-vous sûr de vouloir vous déconnecter ?';

  @override
  String get passwordHint =>
      'Utilisez au moins 8 caractères avec des lettres et des chiffres.';

  @override
  String get sectionUpdatePassword => 'MODIFIER LE MOT DE PASSE';

  @override
  String get fieldCurrentPassword => 'Mot de passe actuel';

  @override
  String get fieldNewPassword => 'Nouveau mot de passe';

  @override
  String get fieldConfirmPassword => 'Confirmer le nouveau mot de passe';

  @override
  String get updatePassword => 'Mettre à jour le mot de passe';

  @override
  String get passwordUpdated => 'Mot de passe mis à jour avec succès.';

  @override
  String get errorFillAllFields => 'Veuillez remplir tous les champs.';

  @override
  String get errorPasswordMismatch =>
      'Les nouveaux mots de passe ne correspondent pas.';

  @override
  String get errorPasswordTooShort =>
      'Le mot de passe doit contenir au moins 8 caractères.';

  @override
  String get appVersion => 'Fleetra v1.0.0 — PROXYM GROUP';

  @override
  String get languageToggleLabel => 'Langue';
}
