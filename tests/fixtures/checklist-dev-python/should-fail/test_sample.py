"""A module with a leftover debug statement."""

import pdb


def add(a, b):
    pdb.set_trace()
    return a + b
