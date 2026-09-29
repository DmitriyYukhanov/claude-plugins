"""Checklist parsing. Run with the skill venv: python -m unittest test_tg_write (from this folder)."""
import unittest
from tg_write import parse_todo


class ParseTodo(unittest.TestCase):
    def test_title_tasks_and_marks(self):
        title, tasks = parse_todo("  Plan \n\n[x] done one\n[ ] open one\n[X]  upper done\nplain\n")
        self.assertEqual(title, "Plan")
        self.assertEqual(tasks, [("done one", True), ("open one", False), ("upper done", True), ("plain", False)])

    def test_bracket_text_that_is_not_a_mark_stays(self):
        self.assertEqual(parse_todo("T\n[x]ray scan\n[draft] notes")[1], [("[x]ray scan", False), ("[draft] notes", False)])

    def test_needs_a_task(self):
        for text in ("", "only title", "\n  \n", "T\n[x]", "T\n[ ]  "):
            with self.assertRaises(ValueError):
                parse_todo(text)

    def test_telegram_limits(self):
        self.assertEqual(len(parse_todo("T\n" + "\n".join(["a" * 100] * 30))[1]), 30)
        for text in ("T\n" + "t\n" * 31, "T\n" + "a" * 101, "a" * 256 + "\ntask"):
            with self.assertRaises(ValueError):
                parse_todo(text)


if __name__ == "__main__":
    unittest.main()
