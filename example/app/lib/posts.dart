typedef Post = ({int id, String title});

typedef CreatePost = ({String title});

typedef PostPage = ({List<Post> items, int? nextCursor});

enum PostSort { newest, oldest }

typedef ListPostsInput = ({
  int? cursor,
  List<int> ids,
  int limit,
  PostSort sort,
});
