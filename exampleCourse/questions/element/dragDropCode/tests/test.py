from pl_helpers import name, points, not_repeated
from pl_unit_test import PLTestCaseWithPlot, PLTestCase
from code_feedback import Feedback
from functools import wraps


class Test(PLTestCase):
    @points(1)
    @name('Check return value')
    def test_0(self):
        print(self.st)
        user_val = Feedback.call_user(self.st.return_even)
        if user_val % 2 == 0:
            Feedback.set_score(1)
        else:
            Feedback.set_score(0)