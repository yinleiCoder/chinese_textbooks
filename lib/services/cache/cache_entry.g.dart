// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cache_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CacheEntry _$CacheEntryFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('CacheEntry', json, ($checkedConvert) {
  final val = CacheEntry(
    key: $checkedConvert('key', (v) => v as String),
    payload: $checkedConvert('payload', (v) => v as String),
    createdAt: $checkedConvert('createdAt', (v) => DateTime.parse(v as String)),
    expiresAt: $checkedConvert('expiresAt', (v) => DateTime.parse(v as String)),
    lastAccessedAt: $checkedConvert(
      'lastAccessedAt',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
    etag: $checkedConvert('etag', (v) => v as String?),
    lastModified: $checkedConvert('lastModified', (v) => v as String?),
    metadata: $checkedConvert(
      'metadata',
      (v) =>
          (v as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, e as String),
          ) ??
          const <String, String>{},
    ),
  );
  return val;
});

Map<String, dynamic> _$CacheEntryToJson(CacheEntry instance) =>
    <String, dynamic>{
      'key': instance.key,
      'payload': instance.payload,
      'createdAt': instance.createdAt.toIso8601String(),
      'expiresAt': instance.expiresAt.toIso8601String(),
      'lastAccessedAt': ?instance.lastAccessedAt?.toIso8601String(),
      'etag': ?instance.etag,
      'lastModified': ?instance.lastModified,
      'metadata': instance.metadata,
    };
