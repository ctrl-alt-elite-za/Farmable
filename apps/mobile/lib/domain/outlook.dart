/// The small, exact slice of `GET /outlook` Market and the planner can share.
/// Decimal prices stay strings from the wire through the phone cache.
library;

import 'farm_records.dart';
import 'money.dart';

const supportedOutlookCrops = <String>{
  'butternut',
  'cabbage',
  'carrots',
  'green_beans',
  'onions',
  'potatoes',
  'spinach',
  'tomatoes',
};

class OutlookQuery {
  final String sectionId;
  final String crop;
  final int plantMonth;

  const OutlookQuery({
    required this.sectionId,
    required this.crop,
    required this.plantMonth,
  });

  /// The local planting is free text; only the contract's crop enum may go
  /// onto the wire. A missing planting date cannot become a guessed month.
  static OutlookQuery? fromSection(SectionSummary section) {
    final planting = section.planting;
    final plantedOn = planting?.plantedOn;
    if (planting == null || plantedOn == null) return null;
    final raw = planting.crop.trim().toLowerCase().replaceAll(' ', '_');
    final crop = switch (raw) {
      'tomato' => 'tomatoes',
      'carrot' => 'carrots',
      'green_bean' => 'green_beans',
      'onion' => 'onions',
      'potato' => 'potatoes',
      _ => raw,
    };
    if (!supportedOutlookCrops.contains(crop)) return null;
    return OutlookQuery(
      sectionId: section.id,
      crop: crop,
      plantMonth: plantedOn.month,
    );
  }

  String get cacheKey => '$sectionId|$crop|$plantMonth';
}

class CropOutlook {
  final String crop;
  final int plantMonth;
  final int harvestMonth;
  final DateTime forecastAsOf;
  final String dataKind;
  final String? warning;
  final DecimalString p10;
  final DecimalString p50;
  final DecimalString p90;

  const CropOutlook({
    required this.crop,
    required this.plantMonth,
    required this.harvestMonth,
    required this.forecastAsOf,
    required this.dataKind,
    required this.warning,
    required this.p10,
    required this.p50,
    required this.p90,
  });

  factory CropOutlook.fromJson(Map<String, Object?> json) {
    final range = json['price_range'];
    if (range is! Map) throw const FormatException('price_range');
    final prices = range.cast<String, Object?>();
    final crop = json['crop'];
    final month = json['plant_month'];
    final harvest = json['harvest_month'];
    final kind = json['data_kind'];
    final asOf = json['forecast_as_of'];
    if (crop is! String ||
        !supportedOutlookCrops.contains(crop) ||
        month is! int ||
        month < 1 ||
        month > 12 ||
        harvest is! int ||
        harvest < 1 ||
        harvest > 12 ||
        kind is! String ||
        !{'synthetic', 'historical', 'retrospective'}.contains(kind) ||
        asOf is! String ||
        json['currency'] != 'ZAR' ||
        (prices['unit'] != null && prices['unit'] != 'ZAR/kg')) {
      throw const FormatException('outlook');
    }
    final warning = json['warning'];
    if (warning != null && warning is! String) {
      throw const FormatException('warning');
    }
    return CropOutlook(
      crop: crop,
      plantMonth: month,
      harvestMonth: harvest,
      forecastAsOf: DateTime.parse(asOf).toUtc(),
      dataKind: kind,
      warning: warning as String?,
      p10: DecimalString(_decimal(prices, 'p10')),
      p50: DecimalString(_decimal(prices, 'p50')),
      p90: DecimalString(_decimal(prices, 'p90')),
    );
  }

  Map<String, Object?> toJson() => {
    'crop': crop,
    'plant_month': plantMonth,
    'harvest_month': harvestMonth,
    'forecast_as_of': forecastAsOf.toIso8601String(),
    'data_kind': dataKind,
    'warning': warning,
    'currency': 'ZAR',
    'price_range': {
      'p10': p10.raw,
      'p50': p50.raw,
      'p90': p90.raw,
      'unit': 'ZAR/kg',
    },
  };

  String get kindLabel => switch (dataKind) {
    'synthetic' => 'Demonstration estimate',
    'retrospective' => 'Retrospective estimate',
    _ => 'Historical estimate',
  };

  String get priceRangeLabel => 'R${p10.trimmed}–R${p90.trimmed} per kg';

  static String _decimal(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || !RegExp(r'^[+-]?\d+(?:\.\d+)?$').hasMatch(value)) {
      throw FormatException(key);
    }
    return value;
  }
}

class SavedOutlook {
  final CropOutlook value;
  final DateTime fetchedAt;

  const SavedOutlook(this.value, this.fetchedAt);
}

enum OutlookSource { fresh, savedOffline, savedAfterRequest, noSavedOutlook }

class OutlookResult {
  final SavedOutlook? saved;
  final OutlookSource source;

  const OutlookResult(this.saved, this.source);

  String ageLabel(DateTime now) {
    final at = saved?.fetchedAt;
    if (at == null) return '';
    final age = now.difference(at);
    if (age.isNegative || age.inMinutes < 1) return 'saved just now';
    if (age.inHours < 1) {
      return 'saved ${age.inMinutes} ${age.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    }
    if (age.inDays < 1) {
      return 'saved ${age.inHours} ${age.inHours == 1 ? 'hour' : 'hours'} ago';
    }
    return 'saved ${age.inDays} ${age.inDays == 1 ? 'day' : 'days'} ago';
  }
}
