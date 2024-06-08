class Demo {
  get hashCode => Object.hashAll([runtimeType]);
}

main() {
  final a = Demo();
  final b = Demo();

  print((1, a).hashCode);
  print((1, b).hashCode);
}
