class Page extends StatelessWidget {
  Widget build(BuildContext context) {
    final page = usePage(context);
    print(page.data); // 'Server loaded data';

    ...
  }
}
