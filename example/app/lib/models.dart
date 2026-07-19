final class PostId {
  const PostId(this.value);

  final int value;

  @override
  bool operator ==(Object other) => other is PostId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
