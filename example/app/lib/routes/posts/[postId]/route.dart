import 'package:odroe/route.dart';

typedef Params = ({int postId});
typedef Search = ({bool preview, List<String> tags});

final route = AppRoute<Params, Search, NoData>(
  params: const PathParams<Params>.schema(),
  search: const SearchParams<Search>.schema(
    defaults: (preview: false, tags: <String>[]),
  ),
  document: (context) => RouteDocument(
    title: 'Post ${context.params.postId}',
    description: 'Odroe post ${context.params.postId}.',
    canonical: '/posts/${context.params.postId}',
    meta: <DocumentMeta>[
      DocumentMeta.property('og:type', 'article'),
      DocumentMeta.property('og:title', 'Post ${context.params.postId}'),
    ],
    jsonLd: <Object?>[
      <String, Object?>{
        '@context': 'https://schema.org',
        '@type': 'Article',
        'headline': 'Post ${context.params.postId}',
      },
    ],
    body: HtmlElement(
      'article',
      children: <HtmlNode>[
        HtmlElement(
          'h2',
          children: <HtmlNode>[HtmlText('Post ${context.params.postId}')],
        ),
        const HtmlElement(
          'p',
          children: <HtmlNode>[
            HtmlText('This content is readable before Flutter starts.'),
          ],
        ),
      ],
    ),
  ),
);
