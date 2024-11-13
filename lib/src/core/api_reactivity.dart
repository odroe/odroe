import '../reactivity/_internal/warn.dart';
import '../reactivity/_internal/writable_ref_impl.dart';
import '../reactivity/types.dart';
import 'oncecall.dart';

WritableRef<T> ref<T>(T value) {
  if (value is Ref) {
    warn("Cannot wrap another ref into a ref. Did you accidentally nest them?");
  }

  return oncecall(() => WritableRefImpl(value));
}
