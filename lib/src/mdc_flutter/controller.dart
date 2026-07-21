import 'package:flutter/foundation.dart';

import '../mdc/ast.dart';
import '../mdc/parser.dart';

/// Owns MDC source and its latest parsed document for Flutter views.
///
/// The controller reparses the complete [source] after every effective source
/// change. Callers that create a controller must dispose it when it is no
/// longer used.
final class MdcDocumentController extends ChangeNotifier {
  /// Creates a controller and parses its initial [source].
  MdcDocumentController({
    String source = '',
    MdcParser parser = const MdcParser(),
  }) : _parser = parser,
       _source = source,
       _document = parser.parse(source);

  final MdcParser _parser;
  String _source;
  MdcDocument _document;

  /// The complete source used to produce [document].
  String get source => _source;

  /// The document produced by the latest successful parse.
  MdcDocument get document => _document;

  /// Replaces [source] and reparses the complete value.
  ///
  /// An equal source is ignored. If parsing fails, the previous source and
  /// document remain active and listeners are not notified.
  void replace(String source) {
    if (source == _source) return;
    final document = _parser.parse(source);
    _source = source;
    _document = document;
    notifyListeners();
  }

  /// Appends [chunk] and reparses the resulting complete source.
  ///
  /// No delimiter is inserted. An empty chunk is ignored.
  void append(String chunk) {
    if (chunk.isEmpty) return;
    replace('$_source$chunk');
  }
}
