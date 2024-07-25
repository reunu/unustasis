import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class Analytics extends StatefulWidget {
  final Widget child;
  const Analytics({super.key, required this.child});

  static AnalyticsState of(BuildContext context) {
    return context.findAncestorStateOfType<AnalyticsState>()!;
  }

  @override
  AnalyticsState createState() => AnalyticsState();
}

class AnalyticsState extends State<Analytics> {
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  bool? _consentGiven;

  @override
  void initState() {
    super.initState();
    getConsent();
  }

  Future<bool?> getConsent() async {
    if (_consentGiven != null) {
      return _consentGiven;
    }
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? consented = prefs.getBool('analyticsConsentGiven');
    setState(() {
      _consentGiven = consented;
    });
    return consented;
  }

  void promptConsent(BuildContext context) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(FlutterI18n.translate(context, "analytics_title")),
              content: RichText(
                  text: TextSpan(
                children: [
                  TextSpan(
                    text: FlutterI18n.translate(context, "analytics_body"),
                  ),
                  TextSpan(
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                    text: "LINK GOES HERE", // TODO: Add link
                    recognizer: TapGestureRecognizer()
                      ..onTap = () async {
                        Uri url = Uri(
                          scheme: 'https',
                          host: 'dart.dev',
                          path: 'guides/libraries/library-tour',
                        );
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url);
                        }
                      },
                  ),
                ],
              )),
              actions: [
                TextButton(
                  child: Text(FlutterI18n.translate(context, "analytics_no")),
                  onPressed: () => setConsent(false),
                ),
                TextButton(
                  child: Text(FlutterI18n.translate(context, "analytics_yes")),
                  onPressed: () => setConsent(true),
                ),
              ],
            ));
  }

  Future<void> setConsent(bool consent) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('analyticsConsentGiven', consent);
    setState(() {
      _consentGiven = consent;
    });
  }

  void logEvent(String name, {Map<String, Object>? parameters}) {
    if (_consentGiven == true) {
      _analytics.logEvent(name: name, parameters: parameters);
    }
  }

  void setUserProperty(String name, String value) {
    if (_consentGiven == true) {
      _analytics.setUserProperty(name: name, value: value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
