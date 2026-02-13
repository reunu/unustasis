import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/log_helper.dart';
import '../helper_widgets/header.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  late final Future<PackageInfo> _packageInfoFuture = PackageInfo.fromPlatform();

  List<Widget> supportItems() => [
        Header(FlutterI18n.translate(context, "support_faqs")),
        Divider(
          indent: 16,
          endIndent: 16,
          height: 24,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        const FaqWidget(),
        Divider(
          indent: 16,
          endIndent: 16,
          height: 24,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        Header(
          FlutterI18n.translate(context, "support_garages"),
          subtitle: FlutterI18n.translate(context, "support_garages_description"),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: GarageWidget(),
        ),
        Divider(
          indent: 16,
          endIndent: 16,
          height: 24,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        Header(FlutterI18n.translate(context, "support_get_help")),
        Divider(
          indent: 16,
          endIndent: 16,
          height: 24,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        ListTile(
          leading: const Icon(Icons.build_outlined),
          title: Text(FlutterI18n.translate(
            context,
            "support_replacement_parts",
          )),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            launchUrl(Uri.parse("https://shop.unumotors.com/collections/all"));
          },
        ),
        Divider(
          indent: 16,
          endIndent: 16,
          height: 24,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        ListTile(
          leading: const Icon(Icons.contact_support_outlined),
          title: Text(FlutterI18n.translate(context, "support_contact_emco")),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            launchUrl(Uri.parse("https://unumotors.com/en-de/service-hub/"));
            // alternative:
            // final Email email = Email(
            //   subject: "Unu Scooter support",
            //   recipients: ['unu@emco-eroller.de'],
            //   isHTML: false,
            // );
            // await FlutterEmailSender.send(email);
          },
        ),
        Divider(
          indent: 16,
          endIndent: 16,
          height: 24,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: Text(FlutterI18n.translate(context, "settings_report")),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            LogHelper.startBugReport(context);
          },
        ),
        Divider(
          indent: 16,
          endIndent: 16,
          height: 24,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        ListTile(
          leading: const Icon(Icons.discord_outlined),
          title: const Text("Unu Community"),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            launchUrl(Uri.parse("https://discord.gg/UEPGY8AG9V"));
          },
        ),
        Divider(
          indent: 16,
          endIndent: 16,
          height: 24,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        Header(FlutterI18n.translate(context, "stats_settings_section_about")),
        Divider(
          indent: 16,
          endIndent: 16,
          height: 24,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(FlutterI18n.translate(context, "settings_privacy_policy")),
          onTap: () {
            launchUrl(
              Uri.parse("https://unumotors.com/de-de/privacy-policy-of-unu-app/"),
            );
          },
          trailing: const Icon(Icons.chevron_right),
        ),
        Divider(
          indent: 16,
          endIndent: 16,
          height: 24,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        FutureBuilder<PackageInfo>(
          future: _packageInfoFuture,
          builder: (context, packageInfo) {
            return ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(FlutterI18n.translate(context, "settings_app_version")),
              subtitle: Text(
                packageInfo.hasData ? "${packageInfo.data!.version} (${packageInfo.data!.buildNumber})" : "...",
              ),
            );
          },
        ),
        Divider(
          indent: 16,
          endIndent: 16,
          height: 24,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        FutureBuilder<PackageInfo>(
          future: _packageInfoFuture,
          builder: (context, packageInfo) {
            return ListTile(
              leading: const Icon(Icons.code_rounded),
              title: Text(FlutterI18n.translate(context, "settings_licenses")),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                showLicensePage(
                  context: context,
                  applicationName: packageInfo.hasData ? packageInfo.data!.appName : "unustasis",
                  applicationVersion: packageInfo.hasData ? packageInfo.data!.version : "?.?.?",
                );
              },
            );
          },
        ),
        Divider(
          indent: 16,
          endIndent: 16,
          height: 24,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, 'stats_title_support')),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: ListView.builder(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom),
        shrinkWrap: true,
        itemCount: supportItems().length,
        itemBuilder: (context, index) => supportItems()[index],
      ),
    );
  }
}

class FaqWidget extends StatelessWidget {
  const FaqWidget({super.key});

  // get the right FAQs
  Future<Map<String, dynamic>> getSupportMap({
    required BuildContext context,
    required String languageCode,
  }) async {
    String data = await DefaultAssetBundle.of(context).loadString("assets/faq_$languageCode.json");
    return jsonDecode(data);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: getSupportMap(
          context: context,
          languageCode: FlutterI18n.currentLocale(context)!.languageCode,
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: SizedBox(
                height: 40,
                width: 40,
                child: CircularProgressIndicator(),
              ),
            );
          }
          Map<String, dynamic> faq = snapshot.data!;
          return ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: faq.length,
            separatorBuilder: (context, index) => Divider(
              indent: 16,
              endIndent: 16,
              height: 24,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
            ),
            itemBuilder: (context, index) {
              MapEntry category = faq.entries.elementAt(index);
              return ExpansionTile(
                shape: const RoundedRectangleBorder(),
                expansionAnimationStyle: AnimationStyle(
                  duration: Durations.medium4,
                  curve: Curves.easeInOutCubicEmphasized,
                ),
                initiallyExpanded: false,
                maintainState: false,
                iconColor: Theme.of(context).colorScheme.onSurface,
                leading: index == 0
                    ? const Icon(Icons.bluetooth)
                    : index == 1
                        ? const Icon(Icons.question_answer_outlined)
                        : const Icon(Icons.info_outline),
                tilePadding: const EdgeInsets.only(left: 20, right: 20),
                title: Text(
                  category.key.toString(),
                ),
                childrenPadding: EdgeInsets.zero,
                children: [
                  for (MapEntry question in category.value.entries)
                    ExpansionTile(
                        shape: const RoundedRectangleBorder(),
                        expansionAnimationStyle: AnimationStyle(
                          duration: Durations.medium4,
                          curve: Curves.easeInOutCubicEmphasized,
                        ),
                        maintainState: false,
                        iconColor: Theme.of(context).colorScheme.onSurface,
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                        tilePadding: const EdgeInsets.only(left: 32, right: 16, top: 8, bottom: 8),
                        title: Text(question.key.toString()),
                        childrenPadding: EdgeInsets.zero,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(32, 0, 16, 16),
                            child: Text(
                              question.value.toString(),
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                            ),
                          )
                        ]),
                ],
              );
            },
          );
        });
  }
}

class GarageWidget extends StatelessWidget {
  const GarageWidget({super.key});

  Future<List<Garage>> getGarages() async {
    final response = await http.get(Uri.parse('https://reunu.github.io/unustasis-data/garages.json'));
    if (response.statusCode == 200) {
      List<dynamic> garages = jsonDecode(utf8.decode(response.bodyBytes));
      return garages.map((garage) => Garage.fromJson(garage)).toList();
    } else {
      Logger("GarageWidget").severe('Failed to load garages', response.toString());
      throw Exception('Failed to load garages');
    }
  }

  Future<List<Garage>> getClosestGarages() async {
    // check for GPS permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const PermissionDeniedException("Location permissions are/were denied");
      }
    }
    // get both location and garage data
    List<dynamic> result = await Future.wait({
      getGarages(),
      Geolocator.getLastKnownPosition(),
    });
    // organize results
    List<Garage> garages = result[0] as List<Garage>;
    Position currentPosition = result[1] as Position;

    // set the distance of each garage
    for (Garage garage in garages) {
      double distance = Geolocator.distanceBetween(
          currentPosition.latitude, currentPosition.longitude, garage.location.latitude, garage.location.longitude);
      garage.distance = distance;
    }
    // sort by distance
    garages.sort((a, b) => a.distance!.compareTo(b.distance!));
    // only return the 3 closest garages
    return garages.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: FutureBuilder(
        future: getClosestGarages(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.search_off_outlined, size: 40),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Text(
                    FlutterI18n.translate(context, "support_garages_none"),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: SizedBox(
                height: 40,
                width: 40,
                child: CircularProgressIndicator(),
              ),
            );
          }
          List<Garage> garages = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: garages.length,
            itemBuilder: (context, index) => _GarageTile(garage: garages[index]),
          );
        },
      ),
    );
  }
}

class _GarageTile extends StatelessWidget {
  const _GarageTile({
    required this.garage,
  });

  final Garage garage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.7,
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Text(
              garage.name,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 8),
            Text("${garage.street}, ${garage.city}", overflow: TextOverflow.ellipsis),
            Text(FlutterI18n.translate(context, "support_garage_distance",
                translationParams: {"dist": (garage.distance! / 1000).toStringAsFixed(1)})),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.onSurface,
                      foregroundColor: Theme.of(context).colorScheme.surface,
                    ),
                    onPressed: () {
                      MapsLauncher.launchQuery("${garage.name} ${garage.street}, ${garage.zipCode}");
                    },
                    label: Text(FlutterI18n.translate(context, "support_garage_map")),
                    icon: const Icon(Icons.map_outlined),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.onSurface,
                      foregroundColor: Theme.of(context).colorScheme.surface,
                    ),
                    onPressed: () {
                      launchUrl(Uri(
                        scheme: 'tel',
                        path: garage.phone,
                      ));
                    },
                    label: Text(FlutterI18n.translate(context, "support_garage_call")),
                    icon: const Icon(Icons.phone_outlined),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class Garage {
  String name;
  String phone;
  String street;
  String city;
  String country;
  String countryCode;
  String zipCode;
  LatLng location;
  double? distance;

  Garage({
    required this.name,
    required this.phone,
    required this.street,
    required this.city,
    required this.country,
    required this.countryCode,
    required this.zipCode,
    required this.location,
  });

  factory Garage.fromJson(Map<String, dynamic> json) {
    try {
      return Garage(
        name: json["name"]?.isNotEmpty == true ? json['name'] : "Unnamed",
        phone: json["Phone"]?.isNotEmpty == true ? json['Phone'].toString() : "Unknown",
        street: json["ShippingStreet"]?.isNotEmpty == true ? json['ShippingStreet'] : "Unknown street",
        city: json["ShippingCity"]?.isNotEmpty == true ? json['ShippingCity'] : "Unknown city",
        country: json["ShippingCountry"]?.isNotEmpty == true ? json['ShippingCountry'] : "Unknown country",
        countryCode: json["ShippingCountryCode"]?.isNotEmpty == true ? json['ShippingCountryCode'] : "??",
        zipCode: json["ShippingPostalCode"]?.isNotEmpty == true ? json['ShippingPostalCode'].toString() : "?????",
        location: LatLng(
          double.parse(json['ShippingLatitude']?.isNotEmpty == true ? json['ShippingLatitude'] : "0"),
          double.parse(json['ShippingLongitude']?.isNotEmpty == true ? json['ShippingLongitude'] : "0"),
        ),
      );
    } catch (e) {
      Logger("Garage").severe("Malformed garage", e);
      Logger("Garage").severe(e.toString());
      Logger("Garage").severe(json.toString());
      rethrow;
    }
  }
}
