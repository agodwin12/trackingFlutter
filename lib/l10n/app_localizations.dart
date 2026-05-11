import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('fr'),
    Locale('en')
  ];

  /// No description provided for @appName.
  ///
  /// In fr, this message translates to:
  /// **'Recouvrement'**
  String get appName;

  /// No description provided for @navHome.
  ///
  /// In fr, this message translates to:
  /// **'Accueil'**
  String get navHome;

  /// No description provided for @navHistory.
  ///
  /// In fr, this message translates to:
  /// **'Historique'**
  String get navHistory;

  /// No description provided for @navProfile.
  ///
  /// In fr, this message translates to:
  /// **'Profil'**
  String get navProfile;

  /// No description provided for @loadingLeaseData.
  ///
  /// In fr, this message translates to:
  /// **'Chargement des données de leasing...'**
  String get loadingLeaseData;

  /// No description provided for @retry.
  ///
  /// In fr, this message translates to:
  /// **'Réessayer'**
  String get retry;

  /// No description provided for @errorRequestTimedOut.
  ///
  /// In fr, this message translates to:
  /// **'Délai dépassé. Veuillez réessayer.'**
  String get errorRequestTimedOut;

  /// No description provided for @errorConnection.
  ///
  /// In fr, this message translates to:
  /// **'Erreur de connexion : {error}'**
  String errorConnection(String error);

  /// No description provided for @errorFailedToLoadLeases.
  ///
  /// In fr, this message translates to:
  /// **'Échec du chargement des données de leasing ({code})'**
  String errorFailedToLoadLeases(int code);

  /// No description provided for @logout.
  ///
  /// In fr, this message translates to:
  /// **'Déconnexion'**
  String get logout;

  /// No description provided for @logoutConfirmTitle.
  ///
  /// In fr, this message translates to:
  /// **'Se déconnecter'**
  String get logoutConfirmTitle;

  /// No description provided for @logoutConfirmMessage.
  ///
  /// In fr, this message translates to:
  /// **'Êtes-vous sûr de vouloir vous déconnecter ?'**
  String get logoutConfirmMessage;

  /// No description provided for @cancel.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get cancel;

  /// No description provided for @recouvrementTitle.
  ///
  /// In fr, this message translates to:
  /// **'RECOUVREMENT'**
  String get recouvrementTitle;

  /// No description provided for @proxymGroup.
  ///
  /// In fr, this message translates to:
  /// **'PROXYM GROUP'**
  String get proxymGroup;

  /// No description provided for @statusPaid.
  ///
  /// In fr, this message translates to:
  /// **'Payé'**
  String get statusPaid;

  /// No description provided for @statusPartial.
  ///
  /// In fr, this message translates to:
  /// **'Partiel'**
  String get statusPartial;

  /// No description provided for @statusUnpaid.
  ///
  /// In fr, this message translates to:
  /// **'Impayé'**
  String get statusUnpaid;

  /// No description provided for @statusHoliday.
  ///
  /// In fr, this message translates to:
  /// **'Férié'**
  String get statusHoliday;

  /// No description provided for @statusNoLease.
  ///
  /// In fr, this message translates to:
  /// **'Sans leasing'**
  String get statusNoLease;

  /// No description provided for @statusUpcoming.
  ///
  /// In fr, this message translates to:
  /// **'À venir'**
  String get statusUpcoming;

  /// No description provided for @statTotalDue.
  ///
  /// In fr, this message translates to:
  /// **'Total Dû'**
  String get statTotalDue;

  /// No description provided for @statTotalPaid.
  ///
  /// In fr, this message translates to:
  /// **'Total Payé'**
  String get statTotalPaid;

  /// No description provided for @statUnpaid.
  ///
  /// In fr, this message translates to:
  /// **'Impayé'**
  String get statUnpaid;

  /// No description provided for @summaryTitle.
  ///
  /// In fr, this message translates to:
  /// **'RÉSUMÉ DES PAIEMENTS'**
  String get summaryTitle;

  /// No description provided for @localTime.
  ///
  /// In fr, this message translates to:
  /// **'HEURE LOCALE'**
  String get localTime;

  /// No description provided for @nextPayIn.
  ///
  /// In fr, this message translates to:
  /// **'PROCHAIN PAIEMENT'**
  String get nextPayIn;

  /// No description provided for @hrsMinSec.
  ///
  /// In fr, this message translates to:
  /// **'h : min : s'**
  String get hrsMinSec;

  /// No description provided for @sectionTodayPayments.
  ///
  /// In fr, this message translates to:
  /// **'PAIEMENTS DU JOUR'**
  String get sectionTodayPayments;

  /// No description provided for @sectionOutstandingPayments.
  ///
  /// In fr, this message translates to:
  /// **'PAIEMENTS EN ATTENTE'**
  String get sectionOutstandingPayments;

  /// No description provided for @pendingPayments.
  ///
  /// In fr, this message translates to:
  /// **'Paiements en attente'**
  String get pendingPayments;

  /// No description provided for @echeances.
  ///
  /// In fr, this message translates to:
  /// **'échéances'**
  String get echeances;

  /// No description provided for @mainContract.
  ///
  /// In fr, this message translates to:
  /// **'Contrat principal'**
  String get mainContract;

  /// No description provided for @subContract.
  ///
  /// In fr, this message translates to:
  /// **'Sous-contrat'**
  String get subContract;

  /// No description provided for @payAll.
  ///
  /// In fr, this message translates to:
  /// **'Tout payer'**
  String get payAll;

  /// No description provided for @todayLease.
  ///
  /// In fr, this message translates to:
  /// **'LEASING DU JOUR'**
  String get todayLease;

  /// No description provided for @due.
  ///
  /// In fr, this message translates to:
  /// **'Échéance :'**
  String get due;

  /// No description provided for @paid.
  ///
  /// In fr, this message translates to:
  /// **'Payé :'**
  String get paid;

  /// No description provided for @remaining.
  ///
  /// In fr, this message translates to:
  /// **'Restant :'**
  String get remaining;

  /// No description provided for @tapToPayNow.
  ///
  /// In fr, this message translates to:
  /// **'Appuyer pour payer'**
  String get tapToPayNow;

  /// No description provided for @unpaidLeasesTitle.
  ///
  /// In fr, this message translates to:
  /// **'Leasings Impayés'**
  String get unpaidLeasesTitle;

  /// No description provided for @unpaidLeasesPending.
  ///
  /// In fr, this message translates to:
  /// **'{count} paiement{plural} en attente'**
  String unpaidLeasesPending(int count, String plural);

  /// No description provided for @pay.
  ///
  /// In fr, this message translates to:
  /// **'Payer'**
  String get pay;

  /// No description provided for @contrat.
  ///
  /// In fr, this message translates to:
  /// **'Contrat #{id}'**
  String contrat(int id);

  /// No description provided for @historyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Historique des Leasings'**
  String get historyTitle;

  /// No description provided for @historySubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Calendrier & relevés de paiement'**
  String get historySubtitle;

  /// No description provided for @tabCalendar.
  ///
  /// In fr, this message translates to:
  /// **'Calendrier'**
  String get tabCalendar;

  /// No description provided for @tabRecords.
  ///
  /// In fr, this message translates to:
  /// **'Relevés'**
  String get tabRecords;

  /// No description provided for @statDaysPaid.
  ///
  /// In fr, this message translates to:
  /// **'Jours Payés'**
  String get statDaysPaid;

  /// No description provided for @statMissed.
  ///
  /// In fr, this message translates to:
  /// **'Manqués'**
  String get statMissed;

  /// No description provided for @statTotalPaidShort.
  ///
  /// In fr, this message translates to:
  /// **'Total Payé'**
  String get statTotalPaidShort;

  /// No description provided for @days.
  ///
  /// In fr, this message translates to:
  /// **'{n} jours'**
  String days(int n);

  /// No description provided for @allUpToDate.
  ///
  /// In fr, this message translates to:
  /// **'Tous les paiements sont à jour !'**
  String get allUpToDate;

  /// No description provided for @nextPaymentDue.
  ///
  /// In fr, this message translates to:
  /// **'Prochain Paiement Dû'**
  String get nextPaymentDue;

  /// No description provided for @amount.
  ///
  /// In fr, this message translates to:
  /// **'Montant'**
  String get amount;

  /// No description provided for @legendPaid.
  ///
  /// In fr, this message translates to:
  /// **'Payé'**
  String get legendPaid;

  /// No description provided for @legendUnpaid.
  ///
  /// In fr, this message translates to:
  /// **'Impayé'**
  String get legendUnpaid;

  /// No description provided for @legendPartial.
  ///
  /// In fr, this message translates to:
  /// **'Partiel'**
  String get legendPartial;

  /// No description provided for @legendToday.
  ///
  /// In fr, this message translates to:
  /// **'Aujourd\'hui'**
  String get legendToday;

  /// No description provided for @detailExpected.
  ///
  /// In fr, this message translates to:
  /// **'Attendu'**
  String get detailExpected;

  /// No description provided for @detailPaid.
  ///
  /// In fr, this message translates to:
  /// **'Payé'**
  String get detailPaid;

  /// No description provided for @detailRemaining.
  ///
  /// In fr, this message translates to:
  /// **'Restant'**
  String get detailRemaining;

  /// No description provided for @detailReference.
  ///
  /// In fr, this message translates to:
  /// **'Référence'**
  String get detailReference;

  /// No description provided for @detailPaidAt.
  ///
  /// In fr, this message translates to:
  /// **'Payé le'**
  String get detailPaidAt;

  /// No description provided for @detailMethod.
  ///
  /// In fr, this message translates to:
  /// **'Méthode'**
  String get detailMethod;

  /// No description provided for @payNowAmount.
  ///
  /// In fr, this message translates to:
  /// **'Payer {amount} XAF maintenant'**
  String payNowAmount(String amount);

  /// No description provided for @noRecordsYet.
  ///
  /// In fr, this message translates to:
  /// **'Aucun relevé'**
  String get noRecordsYet;

  /// No description provided for @allRecords.
  ///
  /// In fr, this message translates to:
  /// **'TOUS LES RELEVÉS'**
  String get allRecords;

  /// No description provided for @summaryRecords.
  ///
  /// In fr, this message translates to:
  /// **'Relevés'**
  String get summaryRecords;

  /// No description provided for @summaryPaid.
  ///
  /// In fr, this message translates to:
  /// **'Payés'**
  String get summaryPaid;

  /// No description provided for @summaryUnpaid.
  ///
  /// In fr, this message translates to:
  /// **'Impayés'**
  String get summaryUnpaid;

  /// No description provided for @summaryPartial.
  ///
  /// In fr, this message translates to:
  /// **'Partiels'**
  String get summaryPartial;

  /// No description provided for @payLeaseTitle.
  ///
  /// In fr, this message translates to:
  /// **'Payer le Leasing'**
  String get payLeaseTitle;

  /// No description provided for @payLeaseSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Sélectionner les leasings à payer'**
  String get payLeaseSubtitle;

  /// No description provided for @allCaughtUp.
  ///
  /// In fr, this message translates to:
  /// **'Tout est à jour !'**
  String get allCaughtUp;

  /// No description provided for @noOutstandingLeases.
  ///
  /// In fr, this message translates to:
  /// **'Vous n\'avez aucun paiement de leasing en attente.'**
  String get noOutstandingLeases;

  /// No description provided for @backToDashboard.
  ///
  /// In fr, this message translates to:
  /// **'Retour au tableau de bord'**
  String get backToDashboard;

  /// No description provided for @sectionOutstandingLeases.
  ///
  /// In fr, this message translates to:
  /// **'LEASINGS EN ATTENTE'**
  String get sectionOutstandingLeases;

  /// No description provided for @deselectAll.
  ///
  /// In fr, this message translates to:
  /// **'Tout désélectionner'**
  String get deselectAll;

  /// No description provided for @selectAll.
  ///
  /// In fr, this message translates to:
  /// **'Tout sélectionner'**
  String get selectAll;

  /// No description provided for @leasesSelected.
  ///
  /// In fr, this message translates to:
  /// **'{count} leasing{plural} sélectionné{plural}'**
  String leasesSelected(int count, String plural);

  /// No description provided for @totalToPay.
  ///
  /// In fr, this message translates to:
  /// **'Total à payer'**
  String get totalToPay;

  /// No description provided for @sectionMobileMoneyNumber.
  ///
  /// In fr, this message translates to:
  /// **'NUMÉRO MOBILE MONEY'**
  String get sectionMobileMoneyNumber;

  /// No description provided for @mobileMoneyNumber.
  ///
  /// In fr, this message translates to:
  /// **'Numéro Mobile Money'**
  String get mobileMoneyNumber;

  /// No description provided for @auto.
  ///
  /// In fr, this message translates to:
  /// **'Auto'**
  String get auto;

  /// No description provided for @sectionPaymentMethod.
  ///
  /// In fr, this message translates to:
  /// **'MÉTHODE DE PAIEMENT'**
  String get sectionPaymentMethod;

  /// No description provided for @mtnMobileMoney.
  ///
  /// In fr, this message translates to:
  /// **'MTN Mobile Money'**
  String get mtnMobileMoney;

  /// No description provided for @mtnTagline.
  ///
  /// In fr, this message translates to:
  /// **'Payer avec MTN MoMo'**
  String get mtnTagline;

  /// No description provided for @orangeMoney.
  ///
  /// In fr, this message translates to:
  /// **'Orange Money'**
  String get orangeMoney;

  /// No description provided for @orangeTagline.
  ///
  /// In fr, this message translates to:
  /// **'Payer avec Orange Money'**
  String get orangeTagline;

  /// No description provided for @paygateInfo.
  ///
  /// In fr, this message translates to:
  /// **'PayGate s\'ouvrira dans l\'application. Gardez votre téléphone accessible pour la demande de paiement.'**
  String get paygateInfo;

  /// No description provided for @selectAtLeastOneLease.
  ///
  /// In fr, this message translates to:
  /// **'Sélectionnez au moins un leasing'**
  String get selectAtLeastOneLease;

  /// No description provided for @selectPaymentMethod.
  ///
  /// In fr, this message translates to:
  /// **'Sélectionnez une méthode de paiement'**
  String get selectPaymentMethod;

  /// No description provided for @payVia.
  ///
  /// In fr, this message translates to:
  /// **'Payer {amount} XAF via {provider}'**
  String payVia(String amount, String provider);

  /// No description provided for @closePaymentTitle.
  ///
  /// In fr, this message translates to:
  /// **'Fermer le paiement ?'**
  String get closePaymentTitle;

  /// No description provided for @closePaymentMessage.
  ///
  /// In fr, this message translates to:
  /// **'Si vous fermez maintenant, votre paiement pourrait ne pas être confirmé. Êtes-vous sûr ?'**
  String get closePaymentMessage;

  /// No description provided for @stay.
  ///
  /// In fr, this message translates to:
  /// **'Rester'**
  String get stay;

  /// No description provided for @closeAnyway.
  ///
  /// In fr, this message translates to:
  /// **'Fermer quand même'**
  String get closeAnyway;

  /// No description provided for @failedToLoadPaymentPage.
  ///
  /// In fr, this message translates to:
  /// **'Échec du chargement de la page de paiement'**
  String get failedToLoadPaymentPage;

  /// No description provided for @checkConnectionRetry.
  ///
  /// In fr, this message translates to:
  /// **'Vérifiez votre connexion et réessayez.'**
  String get checkConnectionRetry;

  /// No description provided for @goBack.
  ///
  /// In fr, this message translates to:
  /// **'Retour'**
  String get goBack;

  /// No description provided for @confirmingPayment.
  ///
  /// In fr, this message translates to:
  /// **'Confirmation du paiement'**
  String get confirmingPayment;

  /// No description provided for @waitingForProvider.
  ///
  /// In fr, this message translates to:
  /// **'En attente de confirmation par {provider}.\nCela prend généralement quelques secondes.'**
  String waitingForProvider(String provider);

  /// No description provided for @checkingIn.
  ///
  /// In fr, this message translates to:
  /// **'Vérification dans {seconds}s (tentative {attempt}/{max})'**
  String checkingIn(int seconds, int attempt, int max);

  /// No description provided for @doNotCloseApp.
  ///
  /// In fr, this message translates to:
  /// **'Ne fermez pas l\'application.\nVotre paiement est en cours de traitement.'**
  String get doNotCloseApp;

  /// No description provided for @summaryAmount.
  ///
  /// In fr, this message translates to:
  /// **'Montant'**
  String get summaryAmount;

  /// No description provided for @summaryMethod.
  ///
  /// In fr, this message translates to:
  /// **'Méthode'**
  String get summaryMethod;

  /// No description provided for @summaryLeases.
  ///
  /// In fr, this message translates to:
  /// **'{count} paiement{plural}'**
  String summaryLeases(int count, String plural);

  /// No description provided for @summaryReference.
  ///
  /// In fr, this message translates to:
  /// **'Référence'**
  String get summaryReference;

  /// No description provided for @summaryStatus.
  ///
  /// In fr, this message translates to:
  /// **'Statut'**
  String get summaryStatus;

  /// No description provided for @paymentConfirmed.
  ///
  /// In fr, this message translates to:
  /// **'Paiement Confirmé !'**
  String get paymentConfirmed;

  /// No description provided for @paymentConfirmedSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'{count} leasing{plural} payé{plural2} avec succès via {provider}.'**
  String paymentConfirmedSubtitle(
      int count, String plural, String plural2, String provider);

  /// No description provided for @amountPaid.
  ///
  /// In fr, this message translates to:
  /// **'Montant Payé'**
  String get amountPaid;

  /// No description provided for @leasesConfirmed.
  ///
  /// In fr, this message translates to:
  /// **'{count} confirmé{plural}'**
  String leasesConfirmed(int count, String plural);

  /// No description provided for @confirmed.
  ///
  /// In fr, this message translates to:
  /// **'✅ Confirmé'**
  String get confirmed;

  /// No description provided for @stillProcessing.
  ///
  /// In fr, this message translates to:
  /// **'Toujours en cours'**
  String get stillProcessing;

  /// No description provided for @stillProcessingSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Nous n\'avons pas encore pu confirmer votre paiement.\nCela peut prendre quelques minutes selon votre réseau.'**
  String get stillProcessingSubtitle;

  /// No description provided for @whatToDo.
  ///
  /// In fr, this message translates to:
  /// **'Que faire :'**
  String get whatToDo;

  /// No description provided for @timeoutStep1.
  ///
  /// In fr, this message translates to:
  /// **'1. Vérifiez vos SMS pour une confirmation de paiement'**
  String get timeoutStep1;

  /// No description provided for @timeoutStep2.
  ///
  /// In fr, this message translates to:
  /// **'2. Ouvrez l\'onglet Historique pour vérifier le statut'**
  String get timeoutStep2;

  /// No description provided for @timeoutStep3.
  ///
  /// In fr, this message translates to:
  /// **'3. En cas de doute, contactez votre partenaire'**
  String get timeoutStep3;

  /// No description provided for @checkHistory.
  ///
  /// In fr, this message translates to:
  /// **'Voir l\'historique'**
  String get checkHistory;

  /// No description provided for @profileTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mon Profil'**
  String get profileTitle;

  /// No description provided for @profileSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Infos du compte & contrat'**
  String get profileSubtitle;

  /// No description provided for @changePasswordTitle.
  ///
  /// In fr, this message translates to:
  /// **'Changer le mot de passe'**
  String get changePasswordTitle;

  /// No description provided for @changePasswordSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Mettre à jour vos identifiants de sécurité'**
  String get changePasswordSubtitle;

  /// No description provided for @sectionAccountInfo.
  ///
  /// In fr, this message translates to:
  /// **'INFORMATIONS DU COMPTE'**
  String get sectionAccountInfo;

  /// No description provided for @fieldFullName.
  ///
  /// In fr, this message translates to:
  /// **'Nom complet'**
  String get fieldFullName;

  /// No description provided for @fieldEmail.
  ///
  /// In fr, this message translates to:
  /// **'Email'**
  String get fieldEmail;

  /// No description provided for @fieldPhone.
  ///
  /// In fr, this message translates to:
  /// **'Téléphone'**
  String get fieldPhone;

  /// No description provided for @fieldCity.
  ///
  /// In fr, this message translates to:
  /// **'Ville'**
  String get fieldCity;

  /// No description provided for @fieldQuartier.
  ///
  /// In fr, this message translates to:
  /// **'Quartier'**
  String get fieldQuartier;

  /// No description provided for @sectionContractDetails.
  ///
  /// In fr, this message translates to:
  /// **'DÉTAILS DU CONTRAT'**
  String get sectionContractDetails;

  /// No description provided for @contractHeader.
  ///
  /// In fr, this message translates to:
  /// **'Contrat #{id} · {frequency}'**
  String contractHeader(int id, String frequency);

  /// No description provided for @repaymentProgress.
  ///
  /// In fr, this message translates to:
  /// **'Progression du remboursement'**
  String get repaymentProgress;

  /// No description provided for @paidAmount.
  ///
  /// In fr, this message translates to:
  /// **'Payé : {amount} XAF'**
  String paidAmount(String amount);

  /// No description provided for @remainingAmount.
  ///
  /// In fr, this message translates to:
  /// **'Restant : {amount} XAF'**
  String remainingAmount(String amount);

  /// No description provided for @contractTotalAmount.
  ///
  /// In fr, this message translates to:
  /// **'Montant Total'**
  String get contractTotalAmount;

  /// No description provided for @contractPerPayment.
  ///
  /// In fr, this message translates to:
  /// **'Par Paiement'**
  String get contractPerPayment;

  /// No description provided for @contractFrequency.
  ///
  /// In fr, this message translates to:
  /// **'Fréquence'**
  String get contractFrequency;

  /// No description provided for @contractStartDate.
  ///
  /// In fr, this message translates to:
  /// **'Date de début'**
  String get contractStartDate;

  /// No description provided for @contractEndDate.
  ///
  /// In fr, this message translates to:
  /// **'Date de fin'**
  String get contractEndDate;

  /// No description provided for @contractNextDue.
  ///
  /// In fr, this message translates to:
  /// **'Prochaine échéance'**
  String get contractNextDue;

  /// No description provided for @contractRegisteredBy.
  ///
  /// In fr, this message translates to:
  /// **'Enregistré par'**
  String get contractRegisteredBy;

  /// No description provided for @sectionSettings.
  ///
  /// In fr, this message translates to:
  /// **'PARAMÈTRES'**
  String get sectionSettings;

  /// No description provided for @settingsChangePassword.
  ///
  /// In fr, this message translates to:
  /// **'Changer le mot de passe'**
  String get settingsChangePassword;

  /// No description provided for @settingsNotifications.
  ///
  /// In fr, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// No description provided for @signOut.
  ///
  /// In fr, this message translates to:
  /// **'Se déconnecter'**
  String get signOut;

  /// No description provided for @signOutConfirmTitle.
  ///
  /// In fr, this message translates to:
  /// **'Se déconnecter'**
  String get signOutConfirmTitle;

  /// No description provided for @signOutConfirmMessage.
  ///
  /// In fr, this message translates to:
  /// **'Êtes-vous sûr de vouloir vous déconnecter ?'**
  String get signOutConfirmMessage;

  /// No description provided for @passwordHint.
  ///
  /// In fr, this message translates to:
  /// **'Utilisez au moins 8 caractères avec des lettres et des chiffres.'**
  String get passwordHint;

  /// No description provided for @sectionUpdatePassword.
  ///
  /// In fr, this message translates to:
  /// **'MODIFIER LE MOT DE PASSE'**
  String get sectionUpdatePassword;

  /// No description provided for @fieldCurrentPassword.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe actuel'**
  String get fieldCurrentPassword;

  /// No description provided for @fieldNewPassword.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau mot de passe'**
  String get fieldNewPassword;

  /// No description provided for @fieldConfirmPassword.
  ///
  /// In fr, this message translates to:
  /// **'Confirmer le nouveau mot de passe'**
  String get fieldConfirmPassword;

  /// No description provided for @updatePassword.
  ///
  /// In fr, this message translates to:
  /// **'Mettre à jour le mot de passe'**
  String get updatePassword;

  /// No description provided for @passwordUpdated.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe mis à jour avec succès.'**
  String get passwordUpdated;

  /// No description provided for @errorFillAllFields.
  ///
  /// In fr, this message translates to:
  /// **'Veuillez remplir tous les champs.'**
  String get errorFillAllFields;

  /// No description provided for @errorPasswordMismatch.
  ///
  /// In fr, this message translates to:
  /// **'Les nouveaux mots de passe ne correspondent pas.'**
  String get errorPasswordMismatch;

  /// No description provided for @errorPasswordTooShort.
  ///
  /// In fr, this message translates to:
  /// **'Le mot de passe doit contenir au moins 8 caractères.'**
  String get errorPasswordTooShort;

  /// No description provided for @appVersion.
  ///
  /// In fr, this message translates to:
  /// **'Fleetra v1.0.0 — PROXYM GROUP'**
  String get appVersion;

  /// No description provided for @languageToggleLabel.
  ///
  /// In fr, this message translates to:
  /// **'Langue'**
  String get languageToggleLabel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
