import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:unustasis/domain/scooter_colors.dart';

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
      content: RadioGroup<int?>(
        groupValue: selectedValue,
        onChanged: (value) {
          setState(() {
            selectedValue = value!;
          });
        },
        child: Column(
          children: [
            _colorRadioTile(
              colorName: scooterColors[0]!.simpleName,
              colorValue: 0,
              color: scooterColors[0]!.displayColor,
              context: context,
            ),
            _colorRadioTile(
              colorName: scooterColors[1]!.simpleName,
              colorValue: 1,
              color: scooterColors[1]!.displayColor,
              context: context,
            ),
            _colorRadioTile(
              colorName: scooterColors[2]!.simpleName,
              colorValue: 2,
              color: scooterColors[2]!.displayColor,
              context: context,
            ),
            _colorRadioTile(
              colorName: scooterColors[3]!.simpleName,
              colorValue: 3,
              color: scooterColors[3]!.displayColor,
              context: context,
            ),
            _colorRadioTile(
              colorName: scooterColors[4]!.simpleName,
              colorValue: 4,
              color: scooterColors[4]!.displayColor,
              context: context,
            ),
            _colorRadioTile(
              colorName: scooterColors[5]!.simpleName,
              colorValue: 5,
              color: scooterColors[5]!.displayColor,
              context: context,
            ),
            _colorRadioTile(
              colorName: scooterColors[6]!.simpleName,
              colorValue: 6,
              color: scooterColors[6]!.displayColor,
              context: context,
            ),
            if (widget.scooterName == magic("Rpyvcfr"))
              _colorRadioTile(
                colorName: scooterColors[7]!.simpleName,
                colorValue: 7,
                color: scooterColors[7]!.displayColor,
                context: context,
              ),
            if (widget.scooterName == magic("Xbev"))
              _colorRadioTile(
                colorName: scooterColors[8]!.simpleName,
                colorValue: 8,
                color: scooterColors[8]!.displayColor,
                context: context,
              ),
            if (widget.scooterName == magic("Ubire"))
              _colorRadioTile(
                colorName: scooterColors[9]!.simpleName,
                colorValue: 9,
                color: scooterColors[9]!.displayColor,
                context: context,
              )
          ],
        ),
      ),
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
      RadioListTile<int?>(
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
