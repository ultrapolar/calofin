# SPDX-License-Identifier: GPL-3.0-or-later
"""Tiny pure-Python stand-in for Blender's mathutils.

Implements just enough of Vector and Matrix for the exporter's geometry
code to run (and be tested) outside Blender.
"""

import math


class Vector:
    __slots__ = ("_v",)

    def __init__(self, seq):
        self._v = [float(c) for c in seq]

    @property
    def x(self):
        return self._v[0]

    @x.setter
    def x(self, value):
        self._v[0] = float(value)

    @property
    def y(self):
        return self._v[1]

    @y.setter
    def y(self, value):
        self._v[1] = float(value)

    @property
    def z(self):
        return self._v[2]

    @z.setter
    def z(self, value):
        self._v[2] = float(value)

    @property
    def length(self):
        return math.sqrt(sum(c * c for c in self._v))

    def __len__(self):
        return len(self._v)

    def __getitem__(self, i):
        return self._v[i]

    def __add__(self, other):
        return Vector(a + b for a, b in zip(self._v, other._v))

    def __sub__(self, other):
        return Vector(a - b for a, b in zip(self._v, other._v))

    def __mul__(self, scalar):
        return Vector(a * scalar for a in self._v)

    def __truediv__(self, scalar):
        return Vector(a / scalar for a in self._v)

    def __repr__(self):
        return "Vector(%s)" % (tuple(self._v),)


class Matrix:
    __slots__ = ("rows",)

    def __init__(self, rows):
        self.rows = [list(r) for r in rows]

    @classmethod
    def Identity(cls, size):
        return cls([[1.0 if i == j else 0.0 for j in range(size)]
                    for i in range(size)])

    @classmethod
    def Rotation(cls, angle, size, axis):
        assert size == 3 and axis == 'Z', "stub supports 3x3 Z rotation only"
        c, s = math.cos(angle), math.sin(angle)
        return cls([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])

    def __getitem__(self, i):
        return self.rows[i]

    def __matmul__(self, other):
        n = len(self.rows)
        if isinstance(other, Matrix):
            return Matrix(
                [[sum(self.rows[i][k] * other.rows[k][j] for k in range(n))
                  for j in range(n)] for i in range(n)]
            )
        # Vector: pad with 1.0 like Blender does for affine transforms,
        # return a vector of the input's length.
        values = list(other._v)
        m = len(values)
        values += [1.0] * (n - m)
        result = [sum(self.rows[i][k] * values[k] for k in range(n))
                  for i in range(n)]
        return Vector(result[:m] if m < n else result)

    def __repr__(self):
        return "Matrix(%r)" % (self.rows,)
