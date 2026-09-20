// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'textbook.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Textbook _$TextbookFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Textbook', json, ($checkedConvert) {
      final val = Textbook(
        id: $checkedConvert('id', (v) => v as String),
        title: $checkedConvert('title', (v) => v as String),
        tagPath: $checkedConvert(
          'tagPath',
          (v) => (v as List<dynamic>).map((e) => e as String).toList(),
        ),
        providerName: $checkedConvert('providerName', (v) => v as String?),
        previewUrl: $checkedConvert('previewUrl', (v) => v as String?),
        updateTime: $checkedConvert(
          'updateTime',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
      );
      return val;
    });

Map<String, dynamic> _$TextbookToJson(Textbook instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'tagPath': instance.tagPath,
  'providerName': ?instance.providerName,
  'previewUrl': ?instance.previewUrl,
  'updateTime': ?instance.updateTime?.toIso8601String(),
};
