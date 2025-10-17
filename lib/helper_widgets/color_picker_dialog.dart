import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

class ColorPickerDialog extends StatefulWidget {
  final int initialValue;
  final String scooterName;

  const ColorPickerDialog({
    super.key,
    required this.initialValue,
    required this.scooterName,
  });

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late int selectedValue;

  @override
  void initState() {
    super.initState();
    selectedValue = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(FlutterI18n.translate(context, "settings_color")),
      scrollable: true,
      content: Builder(builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return RadioGroup<int?>(
            groupValue: selectedValue,
            onChanged: (value) {
              setState(() {
                selectedValue = value!;
              });
            },
            child: Column(
              children: [
                _colorRadioTile(
                  colorName: "black",
                  colorValue: 0,
                  color: Colors.black,
                  context: context,
                ),
                _colorRadioTile(
                  colorName: "white",
                  colorValue: 1,
                  color: Colors.white,
                  context: context,
                ),
                _colorRadioTile(
                  colorName: "green",
                  colorValue: 2,
                  color: Colors.green.shade900,
                  context: context,
                ),
                _colorRadioTile(
                  colorName: "gray",
                  colorValue: 3,
                  color: Colors.grey,
                  context: context,
                ),
                _colorRadioTile(
                  colorName: "orange",
                  colorValue: 4,
                  color: Colors.deepOrange.shade400,
                  context: context,
                ),
                _colorRadioTile(
                  colorName: "red",
                  colorValue: 5,
                  color: Colors.red,
                  context: context,
                ),
                _colorRadioTile(
                  colorName: "blue",
                  colorValue: 6,
                  color: Colors.blue,
                  context: context,
                ),
                if (widget.scooterName == magic("Rpyvcfr"))
                  _colorRadioTile(
                    colorName: "eclipse",
                    colorValue: 7,
                    color: Colors.grey.shade800,
                    context: context,
                  ),
                if (widget.scooterName == magic("Xbev"))
                  _colorRadioTile(
                    colorName: "idioteque",
                    colorValue: 8,
                    color: Colors.teal.shade200,
                    context: context,
                  ),
                if (widget.scooterName == magic("Ubire"))
                  _colorRadioTile(
                    colorName: "hover",
                    colorValue: 9,
                    color: Colors.lightBlue,
                    context: context,
                  )
              ],
            ),
          );
        });
      }),
      actions: [
        TextButton(
          child: Text(FlutterI18n.translate(context, "stats_rename_cancel")),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: Text(FlutterI18n.translate(context, "stats_rename_save")),
          onPressed: () {
            Navigator.of(context).pop(selectedValue);
          },
        ),
      ],
    );
  }

  Widget _colorRadioTile({
    required String colorName,
    required Color color,
    required int colorValue,
    required BuildContext context,
  }) =>
      RadioListTile(
        contentPadding: EdgeInsets.zero,
        value: colorValue,
        title: Text(FlutterI18n.translate(context, "color_$colorName")),
        secondary: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.fromBorderSide(
              BorderSide(color: Colors.grey.shade500, width: 1, strokeAlign: BorderSide.strokeAlignOutside),
            ),
          ),
        ),
      );

  String magic(String input) {
    return input.split('').map((char) {
      if (RegExp(r'[a-z]').hasMatch(char)) {
        return String.fromCharCode(((char.codeUnitAt(0) - 97 + 13) % 26) + 97);
      } else if (RegExp(r'[A-Z]').hasMatch(char)) {
        return String.fromCharCode(((char.codeUnitAt(0) - 65 + 13) % 26) + 65);
      } else {
        return char;
      }
    }).join('');
  }
}

/// Helper function to show the color picker dialog
Future<int?> showColorDialog(int initialValue, String scooterName, BuildContext context) {
  return showDialog<int>(
    context: context,
    builder: (BuildContext context) {
      return ColorPickerDialog(
        initialValue: initialValue,
        scooterName: scooterName,
      );
    },
  );
}
