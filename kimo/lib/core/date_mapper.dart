import 'package:cloud_firestore/cloud_firestore.dart';

DateTime dateFromAny(dynamic value, {DateTime? fallback}) {
  if (value == null) return fallback ?? DateTime.now();
  if (value is DateTime) return value;
  if (value is Timestamp) return value.toDate();
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) {
    return DateTime.tryParse(value) ?? fallback ?? DateTime.now();
  }
  return fallback ?? DateTime.now();
}

Object dateToFirestore(DateTime value) => Timestamp.fromDate(value);

Object? nullableDateToFirestore(DateTime? value) =>
    value == null ? null : Timestamp.fromDate(value);
