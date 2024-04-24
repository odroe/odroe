import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';
import 'package:odroe/store.dart';

typedef Todo = ({String name, bool completed});

final todosStore = writeable<List<Todo>>([
  (name: "Write my first post", completed: true),
  (name: 'Buy new groceries', completed: false),
  (name: 'Walk the dog', completed: false),
]);

Widget todo() => setup(() {
      final context = $context();
      final todos = $store(todosStore);

      return Scaffold(
        appBar: AppBar(title: const Text('Todo (vai Store)')),
        body: ListView(
          children: ListTile.divideTiles(
            context: context,
            tiles: [
              ...todos.map(_todoItem),
              _addTodo(),
            ],
          ).toList(),
        ),
      );
    });

Widget _todoItem(Todo todo) {
  void completed(bool? completed) {
    todosStore.update((todos) {
      return todos.map((e) {
        if (e.name == todo.name) {
          return (name: e.name, completed: completed ?? !todo.completed);
        }

        return e;
      }).toList();
    });
  }

  void remove() {
    todosStore.update(
      (value) => value.where((element) => element.name != todo.name).toList(),
    );
  }

  return ListTile(
    leading: Checkbox(
      value: todo.completed,
      onChanged: completed,
    ),
    title: Text(todo.name),
    trailing: IconButton(
      onPressed: remove,
      icon: const Icon(Icons.delete),
    ),
  );
}

Widget _addTodo() => setup(() {
      final controller = $computed(() => TextEditingController()).get();
      final error = $state<String?>(null);

      void addTask() {
        final task = controller.text;
        if (get(todosStore).map((e) => e.name).contains(task)) {
          return error.set('Task already exists');
        }

        todosStore
            .update((todos) => [...todos, (name: task, completed: false)]);
        error.set(null);
        controller.clear();
      }

      return ListTile(
        title: TextField(
          controller: controller,
          decoration: InputDecoration(
            errorText: error.get(),
            hintText: 'Please enter the task',
          ),
          onChanged: (_) => error.set(null),
        ),
        trailing: IconButton(
          onPressed: addTask,
          icon: const Icon(Icons.add),
        ),
      );
    });
