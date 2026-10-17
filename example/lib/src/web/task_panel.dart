import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import '../tasks/create_task.dart';
import '../tasks/task.dart';

/// The task list of the home page as one swappable block: the list, and for
/// a signed-in visitor the form and a delete button per task.
///
/// The page renders it inside the document, and `TaskFragments` answers it
/// alone, so htmx replaces `#tasks` with the new state.
final class TaskPanel extends StatelessComponent {
  /// The panel of [tasks]; [editable] adds the htmx form and buttons.
  const TaskPanel({
    required this.tasks,
    required this.editable,
    this.draft = '',
    this.error,
    super.key,
  });

  /// The tasks to list.
  final List<Task> tasks;

  /// Whether the visitor may add and delete tasks.
  final bool editable;

  /// The title typed into the form, kept after a refusal.
  final String draft;

  /// Why the last submit was refused, if it was.
  final String? error;

  @override
  Component build(BuildContext context) => section(id: 'tasks', [
    ul([for (final task in tasks) _item(task)]),
    if (editable) _form(),
  ]);

  Component _item(Task task) {
    final title = task.done ? '${task.title} (done)' : task.title;
    if (!editable) return li([Component.text(title)]);
    return li([
      Component.text(title),
      button(
        type: ButtonType.button,
        attributes: {
          'hx-delete': '/fragments/tasks/${task.id}',
          'hx-target': '#tasks',
          'hx-swap': 'outerHTML',
        },
        [Component.text('Delete')],
      ),
    ]);
  }

  Component _form() => form(
    attributes: {
      'hx-post': '/fragments/tasks',
      'hx-target': '#tasks',
      'hx-swap': 'outerHTML',
    },
    [
      input(
        type: InputType.text,
        name: 'title',
        value: draft,
        // One over the limit, so the browser can still send a title the
        // server refuses with 422 (the demo of that path).
        attributes: {'maxlength': '${CreateTask.maxTitleLength + 1}'},
      ),
      button(type: ButtonType.submit, [Component.text('Add')]),
      if (error case final message?)
        p(classes: 'error', [Component.text(message)]),
    ],
  );
}
