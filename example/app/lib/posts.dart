typedef Post = ({int id, String title});

typedef CreatePost = ({String title});

typedef PostPage = ({List<Post> items, int? nextCursor});

typedef ListPostsInput = ({int? cursor, List<int> ids, int limit, String sort});
