/// Adapter-neutral server runtime.
///
/// {@canonicalFor function.ServerFunction}
/// {@canonicalFor function.ServerFunctionBinding}
/// {@canonicalFor function.ServerFunctionContext}
/// {@canonicalFor function.ServerFunctionHandler}
library;

export 'odroe.dart';
export 'src/rpc/function.dart'
    show
        NoServerInput,
        ServerFunction,
        ServerFunctionBinding,
        ServerFunctionContext,
        ServerFunctionHandler,
        ValueDecoder,
        ValueEncoder;
export 'src/rpc/serializer.dart' show SerializationAdapter, Serializer;
export 'src/server/render.dart';
export 'src/server/error_reporter.dart' show ServerErrorHandler;
export 'src/server/server.dart';
export 'src/server/context.dart';
export 'src/server/http.dart';
export 'src/server/invocation.dart'
    show
        ServerInvocation,
        ServerInvocationErrorHandler,
        ServerInvocationHandler;
export 'src/server/middleware.dart' show Middleware, Next;
export 'src/server/route.dart';
