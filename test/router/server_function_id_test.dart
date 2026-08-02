import 'dart:io';

import 'package:odroe/src/router_compiler/compiler.dart';
import 'package:test/test.dart';

void main() {
  group('ServerFunction wire id', () {
    late _RouteProject project;

    setUp(() {
      project = _RouteProject.create();
    });

    tearDown(() {
      project.dispose();
    });

    test('uses an explicit id on both sides and keeps it after a rename', () {
      project.writeFunctions(
        _serverFunction(name: 'readPost', id: "'posts.read'"),
      );
      final before = project.compile();

      expect(before.diagnostics, isEmpty);
      expect(before.source, contains('id: "posts.read"'));
      expect(
        before.serverSource,
        contains('"posts.read": ServerFunctionBinding('),
      );
      expect(before.source, contains('get readPost'));

      project.writeFunctions(
        _serverFunction(name: 'renamedReadPost', id: "'posts.read'"),
      );
      final after = project.compile();

      expect(after.diagnostics, isEmpty);
      expect(after.source, contains('id: "posts.read"'));
      expect(
        after.serverSource,
        contains('"posts.read": ServerFunctionBinding('),
      );
      expect(after.source, contains('get renamedReadPost'));
      expect(
        after.source,
        isNot(contains('lib/routes/server.dart#renamedReadPost')),
      );
    });

    test('rejects duplicate explicit ids', () {
      project.writeFunctions('''
${_serverFunction(name: 'readPost', id: "'posts.read'")}
${_serverFunction(name: 'updatePost', id: "'posts.read'")}
''');

      final output = project.compile();
      final messages = output.diagnostics
          .map((diagnostic) => diagnostic.message)
          .join('\n')
          .toLowerCase();

      expect(output.hasErrors, isTrue);
      expect(messages, contains('duplicate id'));
      expect(messages, contains('posts.read'));
    });

    test('rejects explicit and fallback collisions across route files', () {
      project.writeFunctions(
        _serverFunction(
          name: 'rootFunction',
          id: "'lib/routes/child/server.dart#readChild'",
        ),
      );
      project.writeChildFunctions(_serverFunction(name: 'readChild'));

      final output = project.compile();
      final messages = output.diagnostics
          .map((diagnostic) => diagnostic.message)
          .join('\n');

      expect(output.hasErrors, isTrue);
      expect(messages, contains('lib/routes/child/server.dart#readChild'));
      expect(messages, contains('rootFunction'));
      expect(messages, contains('readChild'));
      expect(messages, contains('lib/routes/server.dart'));
    });

    test('accepts adjacent string literals', () {
      project.writeFunctions(
        _serverFunction(name: 'readPost', id: "'posts.' 'read'"),
      );

      final output = project.compile();

      expect(output.diagnostics, isEmpty);
      expect(output.source, contains('id: "posts.read"'));
      expect(
        output.serverSource,
        contains('"posts.read": ServerFunctionBinding('),
      );
    });

    test('rejects non-literal and empty ids', () {
      project.writeFunctions('''
const functionId = 'posts.read';

${_serverFunction(name: 'readPost', id: 'functionId')}
''');
      var output = project.compile();

      expect(output.hasErrors, isTrue);
      expect(
        output.diagnostics.map((diagnostic) => diagnostic.message),
        contains('ServerFunction "readPost" id must be a string literal.'),
      );

      project.writeFunctions(_serverFunction(name: 'readPost', id: "''"));
      output = project.compile();

      expect(output.hasErrors, isTrue);
      expect(
        output.diagnostics.map((diagnostic) => diagnostic.message),
        contains('ServerFunction "readPost" id must not be empty.'),
      );
    });

    test('keeps the path-based id when id is omitted', () {
      project.writeFunctions(_serverFunction(name: 'readPost'));

      final output = project.compile();
      const fallback = 'lib/routes/server.dart#readPost';

      expect(output.diagnostics, isEmpty);
      expect(output.source, contains('id: "$fallback"'));
      expect(
        output.serverSource,
        contains('"$fallback": ServerFunctionBinding('),
      );
    });

    test('only scans ServerFunction from an Odroe server entrypoint', () {
      project.writeModelFile(
        'fake.dart',
        'final class ServerFunction<I, O> {}',
      );
      project.writeFunctions('''
final foreign = fake.ServerFunction<int, String>();
''', imports: "import '../fake.dart' as fake;");
      var output = project.compile();
      expect(output.diagnostics, isEmpty);
      expect(output.source, isNot(contains('get foreign')));

      project.writeFunctions('''
final class ServerFunction<I, O> {}
final local = ServerFunction<int, String>();
''');
      output = project.compile();
      expect(output.diagnostics, isEmpty);
      expect(output.source, isNot(contains('get local')));

      project.writeFunctions('''
Object ServerFunction<I, O>({required Object handler}) => Object();
final localFunction = ServerFunction<int, String>(handler: Object());
''');
      output = project.compile();
      expect(output.diagnostics, isEmpty);
      expect(output.source, isNot(contains('get localFunction')));

      project.writeFunctions('''
final readValue = server.ServerFunction<server.NoServerInput, String>(
  handler: (_) => 'ok',
);
''', imports: "import 'package:odroe/server.dart' as server;");
      output = project.compile();
      expect(output.diagnostics, isEmpty);
      expect(output.source, contains('get readValue'));

      project.writeModelFile('helpers.dart', 'void helper() {}');
      project.writeFunctions(
        '''
final sharedPrefix = api.ServerFunction<NoServerInput, String>(
  handler: (_) => 'ok',
);
''',
        imports: '''
import 'package:odroe/server.dart' as api show ServerFunction;
import '../helpers.dart' as api show helper;
''',
      );
      output = project.compile();
      expect(output.diagnostics, isEmpty);
      expect(output.source, contains('get sharedPrefix'));

      project.writeFunctions(
        '''
final hiddenBySecondShow = api.ServerFunction<NoServerInput, String>(
  handler: (_) => 'ok',
);
''',
        imports: '''
import 'package:odroe/server.dart' as api
    show ServerFunction, NoServerInput
    show NoServerInput;
''',
      );
      output = project.compile();
      expect(output.diagnostics, isEmpty);
      expect(output.source, isNot(contains('get hiddenBySecondShow')));

      project.writeModelFile(
        'fake.dart',
        'final class ServerFunction<I, O> {}',
      );
      project.writeFunctions(
        '''
final foreign = ServerFunction<int, String>();
''',
        imports: "import '../fake.dart' show ServerFunction;",
        serverImport: "import 'package:odroe/server.dart' hide ServerFunction;",
      );
      output = project.compile();
      expect(output.diagnostics, isEmpty);
      expect(output.source, isNot(contains('get foreign')));
    });

    test('rejects shadowed unprefixed protocol types', () {
      project.writeModelFile('fake.dart', '''
final class NoServerInput {}
final class ServerResponse {}
''');

      project.writeFunctions(
        _serverFunction(name: 'readValue', input: 'NoServerInput'),
        imports: "import '../fake.dart' show NoServerInput;",
        serverImport: "import 'package:odroe/server.dart' hide NoServerInput;",
      );
      var output = project.compile();
      expect(
        output.diagnostics.single.message,
        allOf(contains('NoServerInput'), contains('without an import prefix')),
      );

      project.writeFunctions(
        _serverFunction(name: 'rawValue', output: 'ServerResponse'),
        imports: "import '../fake.dart' show ServerResponse;",
        serverImport: "import 'package:odroe/server.dart' hide ServerResponse;",
      );
      output = project.compile();
      expect(
        output.diagnostics.single.message,
        allOf(contains('ServerResponse'), contains('without an import prefix')),
      );

      project.writeFunctions(
        _serverFunction(name: 'readValue', input: 'NoServerInput'),
        serverImport: "import 'package:odroe/server.dart' hide NoServerInput;",
      );
      output = project.compile();
      expect(
        output.diagnostics.single.message,
        contains('does not resolve to a visible Odroe protocol type'),
      );
    });

    test('rejects generated facade member collisions', () {
      project.writePage();
      project.writeFunctions(_serverFunction(name: 'to'));

      var output = project.compile();
      expect(
        output.diagnostics.single.message,
        allOf(contains('ServerFunction "to"'), contains('navigation method')),
      );

      project.writeFunctions(_serverFunction(name: 'child'));
      project.writeChildFunctions('');
      output = project.compile();
      expect(
        output.diagnostics.single.message,
        allOf(contains('ServerFunction "child"'), contains('child route')),
      );

      for (final name in <String>['toString', 'AppRoutes']) {
        project.writeFunctions(_serverFunction(name: name));
        output = project.compile();
        expect(
          output.diagnostics.single.message,
          allOf(contains('ServerFunction "$name"'), contains('conflicts')),
        );
      }
    });

    test('eagerly validates Iterable input before the handler starts', () {
      project.writeFunctions(
        _serverFunction(name: 'readValues', input: 'Iterable<int>'),
      );

      final output = project.compile();

      expect(output.diagnostics, isEmpty);
      expect(output.serverSource, contains('value as List'));
      expect(output.serverSource, contains('item as int'));
      expect(output.serverSource, contains('.toList(growable: false)'));
    });

    test('emits stream refs and collection codecs', () {
      final stream = _serverFunction(
        name: 'watchValues',
        input: 'NoServerInput',
        output: 'Stream<int>',
      );
      final collection = _serverFunction(
        name: 'doubleValues',
        input: 'List<int>',
        output: 'List<int>',
      );
      project.writeFunctions('$stream$collection');

      final output = project.compile();

      expect(output.diagnostics, isEmpty);
      expect(
        output.source,
        contains('ServerStreamFunctionRef<NoServerInput, int>'),
      );
      expect(
        output.source,
        contains('ServerFunctionRef<List<int>, List<int>>'),
      );
      expect(output.source, contains('decodeOutput: _decodedoubleValues'));
      expect(output.serverSource, contains('decodeInput: (value) =>'));
    });

    test('supports prefixed streams without forwarding dart:async', () {
      project.writeFunctions(
        _serverFunction(
          name: 'watchValues',
          input: 'NoServerInput',
          output: 'async.Stream<int>',
        ),
        imports: "import 'dart:async' as async;",
      );

      final output = project.compile();

      expect(output.diagnostics, isEmpty);
      expect(
        output.source,
        contains('ServerStreamFunctionRef<NoServerInput, int>'),
      );
      expect(output.source, isNot(contains("import 'dart:async'")));
      expect(output.serverSource, isNot(contains("import 'dart:async'")));

      project.writeFunctions(
        _serverFunction(
          name: 'watchValues',
          input: 'NoServerInput',
          output: 'Stream<int>?',
        ),
      );
      expect(
        project.compile().diagnostics.single.message,
        allOf(contains('Stream<int>?'), contains('must be non-null')),
      );

      for (final item in <String>['ServerResponse', 'void']) {
        project.writeFunctions(
          _serverFunction(
            name: 'watchValues',
            input: 'NoServerInput',
            output: 'Stream<$item>',
          ),
        );
        expect(
          project.compile().diagnostics.single.message,
          contains('only valid as direct output'),
        );
      }

      project.writeFunctions(
        _serverFunction(name: 'saveValue', input: 'FutureOr<int>'),
        imports: "import 'dart:async';",
      );
      expect(
        project.compile().diagnostics.single.message,
        contains('FutureOr<int> at FutureOr<int> is not a value wire type'),
      );

      project.writeFunctions(
        _serverFunction(name: 'saveValue', input: 'async.FutureOr<int>'),
        imports: "import 'dart:async' as async;",
      );
      expect(
        project.compile().diagnostics.single.message,
        contains('async.FutureOr<int> at async.FutureOr<int> is not a value'),
      );

      project.writeModelFile('fake.dart', 'final class Stream<T> {}');
      project.writeFunctions(
        _serverFunction(
          name: 'watchValues',
          input: 'NoServerInput',
          output: 'async.Stream<int>',
        ),
        imports: '''
import 'dart:async' if (dart.library.io) '../fake.dart' as async;
''',
      );
      expect(
        project.compile().diagnostics.single.message,
        contains('conditional import prefix "async"'),
      );

      project.writeFunctions(
        _serverFunction(
          name: 'watchValues',
          input: 'NoServerInput',
          output: 'async.Stream<int>',
        ),
        imports: "import 'dart:async' deferred as async;",
      );
      expect(
        project.compile().diagnostics.single.message,
        contains('deferred import prefix "async"'),
      );
    });

    test('keeps prefixed Uint8List imports singular', () {
      project.writeFunctions(
        _serverFunction(
          name: 'echoBytes',
          input: 'typed.Uint8List',
          output: 'typed.Uint8List',
        ),
        imports: "import 'dart:typed_data' as typed;",
      );

      final output = project.compile();

      expect(output.diagnostics, isEmpty);
      expect(
        RegExp('import "dart:typed_data"').allMatches(output.source),
        hasLength(1),
      );
      expect(
        output.source,
        contains('import "dart:typed_data" as root_typed_type;'),
      );
      expect(output.source, isNot(contains('import "dart:typed_data";')));

      project.writeFunctions(
        _serverFunction(name: 'echoBytes', input: 'typed.Uint8ClampedList'),
        imports: "import 'dart:typed_data' as typed;",
      );
      expect(
        project.compile().diagnostics.single.message,
        contains('Uint8ClampedList at typed.Uint8ClampedList has no built-in'),
      );

      project.writeSharedModels('''
import 'dart:typed_data' show Uint8List;
typedef Blob = ({Uint8List bytes});
''');
      project.writeFunctions(
        _serverFunction(name: 'readBlob', output: 'models.Blob'),
        imports: "import '../models.dart' as models;",
      );
      var recordOutput = project.compile();
      expect(recordOutput.diagnostics, isEmpty);
      expect(recordOutput.source, contains('import "dart:typed_data";'));
      expect(recordOutput.source, contains('record["bytes"] as Uint8List'));
      expect(
        recordOutput.serverSource,
        isNot(contains('import "dart:typed_data";')),
      );

      project.writeFunctions(
        _serverFunction(
          name: 'saveBlob',
          input: 'models.Blob',
          output: 'String',
        ),
        imports: "import '../models.dart' as models;",
      );
      recordOutput = project.compile();
      expect(recordOutput.diagnostics, isEmpty);
      expect(recordOutput.source, isNot(contains('import "dart:typed_data";')));
      expect(recordOutput.serverSource, contains('import "dart:typed_data";'));

      project.writeSharedModels('''
typedef OddField = ({String Uint8List});
''');
      project.writeFunctions(
        _serverFunction(name: 'readOdd', output: 'models.OddField'),
        imports: "import '../models.dart' as models;",
      );
      recordOutput = project.compile();
      expect(recordOutput.diagnostics, isEmpty);
      expect(recordOutput.source, isNot(contains('import "dart:typed_data";')));
      expect(
        recordOutput.serverSource,
        isNot(contains('import "dart:typed_data";')),
      );
    });

    test('keeps prefixed custom types in generated client refs', () {
      project.writeSharedType();
      project.writeFunctions(
        _serverFunction(
          name: 'normalizeToken',
          input: 'models.Token',
          output: 'models.Token',
        ),
        imports: "import '../models.dart' as models;",
      );

      final output = project.compile();

      expect(output.diagnostics, isEmpty);
      expect(
        output.source,
        contains('import "models.dart" as root_models_type;'),
      );
      expect(
        output.source,
        contains(
          'ServerFunctionRef<root_models_type.Token, '
          'root_models_type.Token>',
        ),
      );
      expect(output.serverSource, isNot(contains('import "models.dart"')));
    });

    test(
      'forwards route.dart record types even when a page hides its import',
      () {
        project.writeRoute('''
import 'package:odroe/router.dart';

typedef Post = ({int id, String title});
final route = AppRoute<NoParams, NoSearch, NoData>();
''');
        project.writePage();
        project.writeFunctions(
          _serverFunction(
            name: 'readPost',
            input: 'NoServerInput',
            output: 'definition.Post',
          ),
        );

        final output = project.compile();

        expect(output.diagnostics, isEmpty);
        expect(
          output.source,
          contains('import "routes/route.dart" as root_definition_type;'),
        );
        expect(
          output.source,
          contains(
            'ServerFunctionRef<NoServerInput, root_definition_type.Post>',
          ),
        );
        expect(
          output.serverSource,
          contains('import "routes/route.dart" as root_definition_type;'),
        );
      },
    );

    test('generates symmetric codecs for shared named records', () {
      project.writeSharedModels('''
typedef Details = ({String? author, List<int> scores});
typedef CreatePost = ({
  String title,
  List<String?> tags,
  Map<String, int?> metadata,
  Details? details,
});
typedef Post = ({int id, String title});
''');
      project.writeFunctions('''
${_serverFunction(name: 'createPost', input: 'models.CreatePost', output: 'models.Post')}
${_serverFunction(name: 'listPosts', input: 'NoServerInput', output: 'List<models.Post?>')}
${_serverFunction(name: 'watchPosts', input: 'NoServerInput', output: 'Stream<models.Post>')}
''', imports: "import '../models.dart' as models;");

      final output = project.compile();

      expect(output.diagnostics, isEmpty);
      expect(
        output.source,
        contains(
          'ServerFunctionRef<root_models_type.CreatePost, '
          'root_models_type.Post>',
        ),
      );
      expect(output.source, isNot(contains('static final ServerFunctionRef<')));
      expect(output.source, contains('static Object? _encodecreatePost('));
      expect(output.source, contains('static root_models_type.Post'));
      expect(output.source, contains('_decodecreatePost(Object? value)'));
      expect(output.source, contains('get createPost =>'));
      expect(output.source, contains('const ServerFunctionRef<'));
      expect(output.source, contains('encodeInput: _encodecreatePost'));
      expect(output.source, contains('decodeOutput: _decodecreatePost'));
      expect(output.source, contains('"title": value.title'));
      expect(output.source, contains('(root_models_type.Details? typed) =>'));
      expect(output.source, contains('"details":'));
      expect(output.source, contains('"scores": typed.scores'));
      expect(output.source, isNot(contains('typed.scores.map')));
      expect(output.source, contains('record["id"] as int'));
      expect(output.source, contains('record.length != 2'));
      expect(output.source, contains('!record.containsKey("title")'));
      expect(
        output.source,
        contains(
          'ServerStreamFunctionRef<NoServerInput, root_models_type.Post>',
        ),
      );
      expect(output.source, contains('item == null'));
      expect(output.serverSource, contains('decodeInput: (value) =>'));
      expect(output.serverSource, contains('encodeOutput: (value) =>'));
      expect(
        output.serverSource,
        contains('(root_models_type.Post typed) => <String, Object?>'),
      );
      expect(output.serverSource, contains('"id": typed.id'));
      expect(
        output.serverSource,
        contains('import "models.dart" as root_models_type;'),
      );
    });

    test('keeps codec helper names injective', () {
      project.writeSharedModels('typedef Post = ({int id});');
      project.writeFunctions('''
${_serverFunction(name: 'createPost', input: 'models.Post', output: 'models.Post')}
${_serverFunction(name: 'CreatePost', input: 'models.Post', output: 'models.Post')}
''', imports: "import '../models.dart' as models;");

      final output = project.compile();

      expect(output.diagnostics, isEmpty);
      expect(output.source, contains('_encodecreatePost'));
      expect(output.source, contains('_encodeCreatePost'));
      expect(output.source, contains('_decodecreatePost'));
      expect(output.source, contains('_decodeCreatePost'));
    });

    test('escapes interpolation in generated literals and import URIs', () {
      project.writeModelFile(
        r'$models.dart',
        r'typedef Dollar = ({String $value});',
      );
      project.writeFunctions(
        _serverFunction(
          name: 'saveDollar',
          id: r"r'posts.$read'",
          input: 'models.Dollar',
          output: 'models.Dollar',
        ),
        imports: r"import r'../$models.dart' as models;",
      );

      final output = project.compile();

      expect(output.diagnostics, isEmpty);
      expect(
        output.source,
        contains(r'import "\$models.dart" as root_models_type;'),
      );
      expect(output.source, contains(r'id: "posts.\$read"'));
      expect(output.source, contains(r'"\$value": value.$value'));
      expect(output.serverSource, contains(r'"posts.\$read":'));
      expect(output.serverSource, contains(r'"\$value": typed.$value'));
    });

    test('resolves non-generic alias chains around records', () {
      project.writeSharedModels('''
typedef Post = ({int id, String title});
typedef PublicPost = Post;
typedef Posts = List<PublicPost>;
''');
      project.writeFunctions(
        _serverFunction(
          name: 'listPosts',
          input: 'models.Posts',
          output: 'models.Posts',
        ),
        imports: "import '../models.dart' as models;",
      );

      final output = project.compile();

      expect(output.diagnostics, isEmpty);
      expect(
        output.source,
        contains(
          'ServerFunctionRef<root_models_type.Posts, '
          'root_models_type.Posts>',
        ),
      );
      expect(output.source, contains('encodeInput: _encodelistPosts'));
      expect(output.source, contains('decodeOutput: _decodelistPosts'));
      expect(output.source, contains('record["id"] as int'));
      expect(output.serverSource, contains('decodeInput: (value) =>'));
      expect(output.serverSource, contains('encodeOutput: (value) =>'));
    });

    test('keeps overlapping import prefixes token-bound', () {
      project.writeSharedModels('final class Token {}');
      project.writeModelFile('post_models.dart', 'typedef Post = ({int id});');
      project.writeFunctions(
        _serverFunction(
          name: 'readPost',
          input: 'NoServerInput',
          output: 'post_models.Post',
        ),
        imports: '''
import '../models.dart' as models;
import '../post_models.dart' as post_models;
''',
      );

      final output = project.compile();

      expect(output.diagnostics, isEmpty);
      expect(
        output.source,
        contains(
          'ServerFunctionRef<NoServerInput, root_post_models_type.Post>',
        ),
      );
      expect(output.source, isNot(contains('post_root_models_type.Post')));
      expect(
        output.serverSource,
        contains('import "post_models.dart" as root_post_models_type;'),
      );
    });

    test('keeps normalized generated import aliases unique', () {
      project.writeModelFile('posts.dart', 'typedef Post = ({int id});');
      project.writeModelFile('users.dart', 'typedef User = ({int id});');
      project.writeFunctions(
        '''
${_serverFunction(name: 'readPost', input: 'NoServerInput', output: 'postModels.Post')}
${_serverFunction(name: 'readUser', input: 'NoServerInput', output: 'post_models.User')}
''',
        imports: '''
import '../posts.dart' as postModels;
import '../users.dart' as post_models;
''',
      );

      final output = project.compile();

      expect(output.diagnostics, isEmpty);
      expect(
        output.source,
        contains('import "posts.dart" as root_post_models_type;'),
      );
      expect(
        output.source,
        contains('import "users.dart" as root_post_models_type_2;'),
      );
      expect(output.source, contains('root_post_models_type.Post'));
      expect(output.source, contains('root_post_models_type_2.User'));
    });

    test('rejects shared prefixes instead of guessing a record library', () {
      project.writeSharedModels('typedef Post = ({int id});');
      project.writeModelFile('users.dart', 'typedef User = ({int id});');
      project.writeFunctions(
        _serverFunction(
          name: 'readPost',
          input: 'NoServerInput',
          output: 'models.Post',
        ),
        imports: '''
import '../models.dart' as models;
import '../users.dart' as models;
''',
      );

      expect(
        project.compile().diagnostics.single.message,
        allOf(contains('prefix "models"'), contains('multiple libraries')),
      );
    });

    test('rejects record types hidden by import combinators', () {
      project.writeSharedModels('typedef Post = ({int id});');
      project.writeFunctions(
        _serverFunction(
          name: 'readPost',
          input: 'NoServerInput',
          output: 'models.Post',
        ),
        imports: "import '../models.dart' as models hide Post;",
      );

      expect(
        project.compile().diagnostics.single.message,
        allOf(contains('does not expose Post'), contains('prefix "models"')),
      );
    });

    test('rejects conditional imports for wire types', () {
      project.writeModelFile('models_stub.dart', 'typedef Post = ({int id});');
      project.writeModelFile('models_io.dart', 'typedef Post = ({int id});');
      project.writeFunctions(
        _serverFunction(
          name: 'readPost',
          input: 'NoServerInput',
          output: 'models.Post',
        ),
        imports: '''
import '../models_stub.dart'
    if (dart.library.io) '../models_io.dart' as models;
''',
      );

      expect(
        project.compile().diagnostics.single.message,
        allOf(contains('conditional import prefix'), contains('wire types')),
      );
    });

    test('rejects missing and malformed project wire imports', () {
      project.writeFunctions(
        _serverFunction(
          name: 'readPost',
          input: 'NoServerInput',
          output: 'models.Post',
        ),
        imports: "import '../missing.dart' as models;",
      );
      expect(
        project.compile().diagnostics.single.message,
        contains('missing wire import ../missing.dart'),
      );

      project.writeFunctions(
        _serverFunction(
          name: 'readPost',
          input: 'NoServerInput',
          output: 'models.Post',
        ),
        imports: "import 'package:' as models;",
      );
      expect(
        project.compile().diagnostics.single.message,
        contains('outside the project'),
      );
    });

    test('only accepts record field classes declared in the same source', () {
      project.writeSharedModels('''
final class Money {}
typedef LocalInvoice = ({Money total});
''');
      project.writeFunctions(
        _serverFunction(name: 'readInvoice', output: 'models.LocalInvoice'),
        imports: "import '../models.dart' as models;",
      );

      var output = project.compile();
      expect(output.diagnostics, isEmpty);
      expect(
        output.source,
        contains('record["total"] as root_models_type.Money'),
      );

      project.writeModelFile('money.dart', 'final class Money {}');
      project.writeSharedModels('''
import 'money.dart';
typedef ImportedInvoice = ({Money total});
''');
      project.writeFunctions(
        _serverFunction(name: 'readInvoice', output: 'models.ImportedInvoice'),
        imports: "import '../models.dart' as models;",
      );

      output = project.compile();
      expect(
        output.diagnostics.single.message,
        allOf(
          contains('models.ImportedInvoice.total'),
          contains('declared in the same source file'),
        ),
      );
    });

    test('resolves local declarations before same-named core types', () {
      project.writeSharedModels('''
final class DateTime {}
typedef Post = ({DateTime createdAt});
''');
      project.writeFunctions(
        _serverFunction(name: 'readPost', output: 'models.Post'),
        imports: "import '../models.dart' as models;",
      );

      var output = project.compile();
      expect(output.diagnostics, isEmpty);
      expect(
        output.source,
        contains('record["createdAt"] as root_models_type.DateTime'),
      );

      project.writeModelFile('custom.dart', 'final class DateTime {}');
      project.writeSharedModels('''
import 'custom.dart' show DateTime;
typedef Post = ({DateTime createdAt});
''');
      output = project.compile();
      expect(
        output.diagnostics.single.message,
        allOf(contains('imported type DateTime'), contains('same source file')),
      );

      project.writeSharedModels('''
typedef String = int;
typedef Weird = Map<String, int>;
typedef Envelope = ({Weird data});
''');
      project.writeFunctions(
        _serverFunction(name: 'readValue', output: 'models.Envelope'),
        imports: "import '../models.dart' as models;",
      );
      expect(
        project.compile().diagnostics.single.message,
        allOf(contains('Map<dart:core String, T>'), contains('shadowed key')),
      );
    });

    test('rejects server-file types that shadow protocol built-ins', () {
      project.writeFunctions('''
final class Stream<T> {}
${_serverFunction(name: 'watchValues', input: 'NoServerInput', output: 'Stream<int>')}
''');

      var output = project.compile();
      expect(
        output.diagnostics.single.message,
        allOf(contains('Stream'), contains('without an import prefix')),
      );

      project.writeModelFile('custom.dart', 'final class Stream<T> {}');
      project.writeFunctions(
        _serverFunction(
          name: 'watchValues',
          input: 'NoServerInput',
          output: 'Stream<int>',
        ),
        imports: "import '../custom.dart' show Stream;",
      );
      output = project.compile();
      expect(
        output.diagnostics.single.message,
        allOf(contains('Stream'), contains('without an import prefix')),
      );

      project.writeModelFile('safe.dart', 'final class Safe {}');
      project.writeFunctions(
        _serverFunction(
          name: 'watchValues',
          input: 'NoServerInput',
          output: 'Stream<int>',
        ),
        imports: '''
import '../safe.dart' if (dart.library.io) '../custom.dart';
''',
      );
      output = project.compile();
      expect(
        output.diagnostics.single.message,
        allOf(contains('Stream'), contains('without an import prefix')),
      );
    });

    test('rejects wire types hidden behind re-exports and parts', () {
      project.writeModelFile('post.dart', 'typedef Post = ({int id});');

      FileRouteOutput compileWithModels(String models) {
        project.writeSharedModels(models);
        project.writeFunctions(
          _serverFunction(
            name: 'readPost',
            input: 'NoServerInput',
            output: 'models.Post',
          ),
          imports: "import '../models.dart' as models;",
        );
        return project.compile();
      }

      expect(
        compileWithModels("export 'post.dart';").diagnostics.single.message,
        allOf(contains('not declared directly'), contains('re-exports')),
      );

      project.writeModelFile('post.dart', '''
part of 'models.dart';
typedef Post = ({int id});
''');
      expect(
        compileWithModels("part 'post.dart';").diagnostics.single.message,
        allOf(contains('not declared directly'), contains('parts')),
      );

      project.writeFunctions(
        _serverFunction(
          name: 'readPost',
          input: 'NoServerInput',
          output: 'models.Post',
        ),
        imports: "import '../post.dart' as models;",
      );
      expect(
        project.compile().diagnostics.single.message,
        contains('is a part file and cannot be imported directly'),
      );
    });

    test('rejects platform-specific wire imports and model libraries', () {
      project.writeFunctions(
        _serverFunction(
          name: 'readFile',
          input: 'NoServerInput',
          output: 'io.File',
        ),
        imports: "import 'dart:io' as io;",
      );
      expect(
        project.compile().diagnostics.single.message,
        allOf(contains('dart:io'), contains('client and server targets')),
      );

      project.writeSharedModels('final class Box<T> {}');
      project.writeFunctions(
        _serverFunction(name: 'readBox', output: 'models.Box<int>'),
        imports: "import '../models.dart' as models;",
      );
      expect(project.compile().diagnostics, isEmpty);

      project.writeFunctions(
        _serverFunction(
          name: 'readBox',
          input: 'NoServerInput',
          output: 'models.Box<io.File>',
        ),
        imports: '''
import 'dart:io' as io;
import '../models.dart' as models;
''',
      );
      expect(
        project.compile().diagnostics.single.message,
        allOf(
          contains('type argument 1'),
          contains('dart:io'),
          contains('client and server targets'),
        ),
      );

      FileRouteOutput compileModel(String directive) {
        project.writeSharedModels('''
$directive
typedef Post = ({int id});
''');
        project.writeFunctions(
          _serverFunction(name: 'readPost', output: 'models.Post'),
          imports: "import '../models.dart' as models;",
        );
        return project.compile();
      }

      for (final uri in <String>[
        'dart:cli',
        'dart:concurrent',
        'dart:ffi',
        'dart:html',
        'dart:indexed_db',
        'dart:io',
        'dart:isolate',
        'dart:js_interop_unsafe',
        'dart:svg',
        'dart:ui',
        'dart:web_audio',
        'dart:web_gl',
      ]) {
        expect(
          compileModel("import '$uri';").diagnostics.single.message,
          allOf(contains(uri), contains('shared wire libraries must compile')),
        );
      }
      expect(
        compileModel("export 'dart:io';").diagnostics.single.message,
        contains('shared wire libraries must compile'),
      );
      project.writeModelFile('safe.dart', 'final class Safe {}');
      expect(
        compileModel(
          "import 'safe.dart' if (dart.library.io) 'dart:io';",
        ).diagnostics.single.message,
        allOf(
          contains('dart:io'),
          contains('shared wire libraries must compile'),
        ),
      );
      expect(
        compileModel(
          "import 'package:odroe/server_io.dart';",
        ).diagnostics.single.message,
        contains('shared wire libraries must compile'),
      );
    });

    test('enforces prefixed protocol built-in placement', () {
      project.writeFunctions(
        _serverFunction(
          name: 'rawResponse',
          input: 'NoServerInput',
          output: 'server.ServerResponse',
        ),
        imports: "import 'package:odroe/server.dart' as server;",
      );
      var output = project.compile();
      expect(output.diagnostics, isEmpty);
      expect(
        output.source,
        contains('ServerFunctionRef<NoServerInput, ServerResponse>'),
      );

      project.writeFunctions(
        _serverFunction(
          name: 'invalidResponses',
          input: 'NoServerInput',
          output: 'List<rpc.ServerResponse>',
        ),
        imports: "import 'package:odroe/rpc.dart' as rpc;",
      );
      output = project.compile();
      expect(
        output.diagnostics.single.message,
        contains('ServerResponse is only valid as direct output'),
      );

      project.writeFunctions(
        _serverFunction(
          name: 'coreValues',
          input: 'NoServerInput',
          output: 'core.List<int>',
        ),
        imports: "import 'dart:core' as core;",
      );
      expect(
        project.compile().diagnostics.single.message,
        contains('core wire types must be unprefixed'),
      );

      project.writeFunctions(
        _serverFunction(
          name: 'hostResponse',
          input: 'NoServerInput',
          output: 'io.ServerResponse',
        ),
        imports: "import 'package:odroe/server_io.dart' as io;",
      );
      output = project.compile();
      expect(output.diagnostics, isEmpty);
      expect(
        output.source,
        contains('ServerFunctionRef<NoServerInput, ServerResponse>'),
      );
      expect(output.source, isNot(contains('server_io.dart')));

      project.writeFunctions(
        _serverFunction(
          name: 'invalidHostType',
          input: 'NoServerInput',
          output: 'io.IoServer',
        ),
        imports: "import 'package:odroe/server_io.dart' as io;",
      );
      expect(
        project.compile().diagnostics.single.message,
        contains('server-only type io.IoServer'),
      );
    });

    test('rejects unsupported record typedef shapes precisely', () {
      project.writeSharedModels('''
typedef Positional = (int, String);
typedef Box<T> = ({T value});
typedef RecursiveA = ({RecursiveB value});
typedef RecursiveB = ({RecursiveA value});
typedef AsyncField = ({Future<String> value});
typedef NullableAlias = ({int id})?;
typedef Post = ({int id});
typedef MaybePost = Post?;
typedef PrivateField = ({String _token});
''');

      FileRouteOutput compile(String type) {
        project.writeFunctions(
          _serverFunction(name: 'readValue', output: type),
          imports: "import '../models.dart' as models;",
        );
        return project.compile();
      }

      expect(
        compile('models.Positional').diagnostics.single.message,
        contains('positional record typedef models.Positional'),
      );
      expect(
        compile('models.Box<int>').diagnostics.single.message,
        contains('generic record typedef models.Box'),
      );
      expect(
        compile('models.RecursiveA').diagnostics.single.message,
        contains('RecursiveA -> RecursiveB -> RecursiveA'),
      );
      expect(
        compile('models.AsyncField').diagnostics.single.message,
        allOf(
          contains('models.AsyncField.value'),
          contains('not a value wire type'),
        ),
      );
      expect(
        compile('models.NullableAlias').diagnostics.single.message,
        allOf(
          contains('nullable record typedef models.NullableAlias'),
          contains('models.NullableAlias?'),
        ),
      );
      expect(
        compile('models.MaybePost').diagnostics.single.message,
        allOf(
          contains('nullable record alias target'),
          contains('models.MaybePost?'),
        ),
      );
      expect(
        compile('models.PrivateField').diagnostics.single.message,
        allOf(contains('private record field _token'), contains('public')),
      );
      expect(
        compile('({int id, String title})').diagnostics.single.message,
        contains('inline record'),
      );
    });
  });
}

String _serverFunction({
  required String name,
  String? id,
  String input = 'int',
  String output = 'String',
}) =>
    '''
final $name = ServerFunction<$input, $output>(
  ${id == null ? '' : 'id: $id,'}
  handler: (_) => throw UnimplementedError(),
);
''';

final class _RouteProject {
  _RouteProject._(this.root, this.serverFile);

  factory _RouteProject.create() {
    final root = Directory.systemTemp.createTempSync(
      'odroe-server-function-id-',
    );
    final routes = Directory('${root.path}/lib/routes')
      ..createSync(recursive: true);
    File('${routes.path}/route.dart').writeAsStringSync('''
import 'package:odroe/router.dart';

final route = AppRoute<NoParams, NoSearch, NoData>();
''');
    return _RouteProject._(root, File('${routes.path}/server.dart'));
  }

  final Directory root;
  final File serverFile;

  void writeFunctions(
    String functions, {
    String imports = '',
    String serverImport = "import 'package:odroe/server.dart';",
  }) {
    serverFile.writeAsStringSync('''
import 'package:odroe/router.dart';
$serverImport
$imports

import 'route.dart' as definition;

final route = definition.route.server();

$functions
''');
  }

  void writeRoute(String source) =>
      File('${root.path}/lib/routes/route.dart').writeAsStringSync(source);

  void writePage() {
    File('${root.path}/lib/routes/page.dart').writeAsStringSync('''
import 'route.dart' as definition;

final route = definition.route.page();
''');
  }

  void writeSharedType() {
    writeSharedModels('final class Token { const Token(); }\n');
  }

  void writeSharedModels(String source) =>
      writeModelFile('models.dart', source);

  void writeModelFile(String name, String source) =>
      File('${root.path}/lib/$name').writeAsStringSync(source);

  void writeChildFunctions(String functions) {
    final routes = Directory('${root.path}/lib/routes/child')
      ..createSync(recursive: true);
    File('${routes.path}/route.dart').writeAsStringSync('''
import 'package:odroe/router.dart';

final route = AppRoute<NoParams, NoSearch, NoData>();
''');
    File('${routes.path}/server.dart').writeAsStringSync('''
import 'package:odroe/router.dart';
import 'package:odroe/server.dart';

import 'route.dart' as definition;

final route = definition.route.server();

$functions
''');
  }

  FileRouteOutput compile() => FileRouteCompiler(projectRoot: root).compile();

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}
