import 'dart:convert';

/// Encodes [value] as a non-interpolating Dart string literal.
String dartStringLiteral(String value) =>
    jsonEncode(value).replaceAll(r'$', r'\$');
