import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/log_helper.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  Future<Map<String, dynamic>> getSupportMap({
    required BuildContext context,
    required String languageCode,
  }) async {
    String data = await DefaultAssetBundle.of(context)
        .loadString("assets/faq_$languageCode.json");
    return jsonDecode(data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          FlutterI18n.translate(context, "settings_support"),
        ),
        backgroundColor: Theme.of(context).colorScheme.onTertiary,
      ),
      body: FutureBuilder(
        future: getSupportMap(
          context: context,
          languageCode: FlutterI18n.currentLocale(context)!.languageCode,
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          Map<String, dynamic> faq = snapshot.data!;
          return Container(
            color: Theme.of(context).colorScheme.onTertiary,
            child: ListView.builder(
                itemCount: faq.length + 2,
                itemBuilder: (context, index) {
                  if (index == faq.length) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
                      child: OutlinedButton(
                        onPressed: () {
                          launchUrl(Uri.parse("https://discord.gg/UEPGY8AG9V"));
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.discord_outlined,
                                color:
                                    Theme.of(context).colorScheme.onBackground,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "Unu Community Discord",
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  if (index == faq.length + 1) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      child: OutlinedButton(
                        onPressed: () {
                          LogHelper.startBugReport(context);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.bug_report_outlined,
                                color:
                                    Theme.of(context).colorScheme.onBackground,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                FlutterI18n.translate(
                                    context, "settings_report"),
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  MapEntry category = faq.entries.elementAt(index);

                  return ExpansionTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    initiallyExpanded: true,
                    iconColor: Theme.of(context).colorScheme.onBackground,
                    tilePadding: const EdgeInsets.only(
                        left: 16, right: 16, top: 8, bottom: 8),
                    title: Text(
                      category.key.toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    children: [
                      for (MapEntry question in category.value.entries)
                        ExpansionTile(
                            iconColor:
                                Theme.of(context).colorScheme.onBackground,
                            backgroundColor:
                                Theme.of(context).colorScheme.background,
                            collapsedBackgroundColor:
                                Theme.of(context).colorScheme.onTertiary,
                            tilePadding: const EdgeInsets.only(
                                left: 32, right: 16, top: 8, bottom: 8),
                            title: Text(question.key.toString()),
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(32, 0, 16, 32),
                                child: Text(
                                  question.value.toString(),
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onBackground
                                          .withOpacity(0.6)),
                                ),
                              )
                            ]),
                    ],
                  );
                }),
          );
        },
      ),
    );
  }
}
