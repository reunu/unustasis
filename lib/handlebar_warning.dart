import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../scooter_service.dart';

class HandlebarWarning extends StatefulWidget {
  const HandlebarWarning({
    super.key,
    required this.didNotUnlock,
  });

  final bool didNotUnlock;

  @override
  State<HandlebarWarning> createState() => _HandlebarWarningState();
}

class _HandlebarWarningState extends State<HandlebarWarning> {
  bool dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Lottie.asset(
            "assets/anim/handlebars.json",
            height: 160,
          ),
          const SizedBox(height: 24),
          Text(FlutterI18n.translate(context,
              "${widget.didNotUnlock ? "locked" : "unlocked"}_handlebar_alert_title")),
        ],
      ),
      content: SingleChildScrollView(
        child: ListBody(
          children: <Widget>[
            Text(FlutterI18n.translate(context,
                "${widget.didNotUnlock ? "locked" : "unlocked"}_handlebar_alert_body")),
            if (!widget.didNotUnlock)
              CheckboxListTile(
                contentPadding: EdgeInsets.all(0),
                dense: true,
                value: dontShowAgain,
                onChanged: (value) {
                  setState(() {
                    dontShowAgain = value ?? false;
                  });
                },
                title: Text(FlutterI18n.translate(
                    context, "unlocked_handlebar_alert_ignore")),
              )
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('OK'),
          onPressed: () {
            Navigator.of(context).pop(dontShowAgain);
          },
        ),
        TextButton(
          child: Text(FlutterI18n.translate(context,
              "${widget.didNotUnlock ? "locked" : "unlocked"}_handlebar_alert_action")),
          onPressed: () {
            if (widget.didNotUnlock) {
              context.read<ScooterService>().lock();
            } else {
              context.read<ScooterService>().unlock();
            }
            Navigator.of(context).pop(dontShowAgain);
          },
        ),
      ],
    );
  }
}
