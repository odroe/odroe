import 'oncecall.dart';
import 'reactivity/types.dart';
import 'reactivity/writable_ref_impl.dart';
import 'warn.dart';

bool isRef(v) => v is Ref;

WritableRef<T> ref<T>(T value) {
  assert(value is! Ref);
  if (isRef(value)) {
    warn('Cannot wrap another ref into a ref. Did you accidentally nest them?');
  }

  return oncecall(() => WritableRefImpl(value));
}
