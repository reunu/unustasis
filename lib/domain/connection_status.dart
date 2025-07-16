import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

/// Represents the connection status of a scooter
enum ConnectionStatus {
  none,     // No scooter selected
  ble,      // Connected via Bluetooth only
  cloud,    // Connected via cloud only
  both,     // Connected via both BLE and cloud
  offline,  // Scooter selected but no connection available
}

extension ConnectionStatusExtension on ConnectionStatus {
  /// Get display text for the connection status
  String name(BuildContext context) {
    switch (this) {
      case ConnectionStatus.none:
        return FlutterI18n.translate(context, "connection_status_none");
      case ConnectionStatus.ble:
        return FlutterI18n.translate(context, "connection_status_ble");
      case ConnectionStatus.cloud:
        return FlutterI18n.translate(context, "connection_status_cloud");
      case ConnectionStatus.both:
        return FlutterI18n.translate(context, "connection_status_both");
      case ConnectionStatus.offline:
        return FlutterI18n.translate(context, "connection_status_offline");
    }
  }
  
  /// Get description for the connection status
  String description(BuildContext context) {
    switch (this) {
      case ConnectionStatus.none:
        return FlutterI18n.translate(context, "connection_status_desc_none");
      case ConnectionStatus.ble:
        return FlutterI18n.translate(context, "connection_status_desc_ble");
      case ConnectionStatus.cloud:
        return FlutterI18n.translate(context, "connection_status_desc_cloud");
      case ConnectionStatus.both:
        return FlutterI18n.translate(context, "connection_status_desc_both");
      case ConnectionStatus.offline:
        return FlutterI18n.translate(context, "connection_status_desc_offline");
    }
  }
  
  /// Get color for the connection status
  Color color(BuildContext context) {
    switch (this) {
      case ConnectionStatus.none:
        return Theme.of(context).colorScheme.surfaceContainer;
      case ConnectionStatus.ble:
        return Theme.of(context).colorScheme.primary;
      case ConnectionStatus.cloud:
        return Theme.of(context).colorScheme.primary.withOpacity(0.7);
      case ConnectionStatus.both:
        return Theme.of(context).colorScheme.primary;
      case ConnectionStatus.offline:
        return Theme.of(context).colorScheme.error;
    }
  }
  
  /// Check if any connection is available
  bool get isConnected => this == ConnectionStatus.ble || 
                         this == ConnectionStatus.cloud || 
                         this == ConnectionStatus.both;
  
  /// Check if BLE is available
  bool get hasBLE => this == ConnectionStatus.ble || this == ConnectionStatus.both;
  
  /// Check if cloud is available
  bool get hasCloud => this == ConnectionStatus.cloud || this == ConnectionStatus.both;
}