# Oncecall

Oncecall is a memoization tool for use in the build method of Widgets.

## Installation

Run the following command:

```bash
dart pub add oncecall
```

Or add to your `pubspec.yaml` file:

```yaml
dependencies:
  oncecall: latest
```

## Usage

```dart
class MyWidget extends StatelessWidget {
    const MyWidget({super.key});

    Widget build(BuildContext context) {
        final value = oncecall(context, () {
            // This function will only be executed once, even if the widget rebuilds
            return expensiveComputation();
        });

        return OtherWidget(value);
    }
}
```
