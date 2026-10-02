import 'package:flutter/widgets.dart';
import 'package:odroe/query_flutter.dart';

class CounterPage extends StatefulWidget {
  const CounterPage({required this.greeting, this.openDetails, super.key});

  final QueryOptions<String> greeting;
  final VoidCallback? openDetails;

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  var count = 0;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Existing count: $count'),
        GestureDetector(
          onTap: () => setState(() => count++),
          child: const Text('Increment'),
        ),
        QueryBuilder<String>(
          options: widget.greeting,
          builder: (_, result) => Text(
            result.hasData
                ? result.requireData
                : result.isError
                ? 'Could not load greeting'
                : 'Loading',
          ),
        ),
        if (widget.openDetails != null)
          GestureDetector(
            onTap: widget.openDetails,
            child: const Text('Open details'),
          ),
      ],
    ),
  );
}
