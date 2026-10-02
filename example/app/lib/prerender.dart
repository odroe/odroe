/// Dynamic application locations that must be included in static builds.
Future<Iterable<Uri>> prerenderLocations() async => <Uri>[
  Uri(path: '/docs/getting-started'),
  Uri(path: '/docs/routing'),
  Uri(path: '/posts/42'),
];
