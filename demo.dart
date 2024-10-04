main() {
  final a = {};
  final b = a;
  print(a == b);

  a[1] = 2;

  print(b);
}
