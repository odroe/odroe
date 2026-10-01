/// Platform-neutral asynchronous server-state for Dart and Flutter apps.
library;

export 'src/query/cancellation.dart';
export 'src/query/cache.dart' hide replaceQueryCacheEntry;
export 'src/query/client.dart';
export 'src/query/hydration.dart';
export 'src/query/infinite.dart';
export 'src/query/key.dart';
export 'src/query/managers.dart';
export 'src/query/module.dart';
export 'src/query/mutation.dart';
export 'src/query/observer.dart';
export 'src/query/options.dart' hide dispatchQueryEnsure, dispatchQueryFetch;
export 'src/query/persistence.dart';
export 'src/query/query.dart'
    hide
        adoptHydratedQuery,
        fetchHydratedQuery,
        readHydratedQueryState,
        setHydratedQueryState;
export 'src/query/state.dart';
