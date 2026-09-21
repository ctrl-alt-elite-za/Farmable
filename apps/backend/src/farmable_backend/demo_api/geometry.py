"""Approximate small-field area; not a survey or agronomic suitability assessment."""

import math
from decimal import ROUND_HALF_UP, Decimal

EARTH_RADIUS_M = 6_371_008.8
Point = tuple[float, float]


def boundary_area(ring: tuple[Point, ...]) -> Decimal:
    if ring[0] != ring[-1] or len(set(ring[:-1])) != len(ring) - 1:
        raise ValueError("Boundary must be closed with distinct corners")
    longitude, latitude = zip(*ring[:-1], strict=True)
    if max(longitude) - min(longitude) > 0.1 or max(latitude) - min(latitude) > 0.1:
        raise ValueError("Only small local field boundaries are supported")
    lon0, lat0 = sum(longitude) / len(longitude), sum(latitude) / len(latitude)
    scale = math.cos(math.radians(lat0))
    points = tuple(
        (
            EARTH_RADIUS_M * math.radians(lon - lon0) * scale,
            EARTH_RADIUS_M * math.radians(lat - lat0),
        )
        for lon, lat in ring
    )

    def orientation(a: Point, b: Point, c: Point) -> float:
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])

    def on_segment(a: Point, b: Point, c: Point) -> bool:
        return (
            min(a[0], b[0]) - 1e-7 <= c[0] <= max(a[0], b[0]) + 1e-7
            and min(a[1], b[1]) - 1e-7 <= c[1] <= max(a[1], b[1]) + 1e-7
        )

    def intersects(a: Point, b: Point, c: Point, d: Point) -> bool:
        turns = (
            orientation(a, b, c),
            orientation(a, b, d),
            orientation(c, d, a),
            orientation(c, d, b),
        )
        if turns[0] * turns[1] < 0 and turns[2] * turns[3] < 0:
            return True
        return any(
            abs(turn) <= 1e-7 and on_segment(start, end, corner)
            for turn, start, end, corner in (
                (turns[0], a, b, c),
                (turns[1], a, b, d),
                (turns[2], c, d, a),
                (turns[3], c, d, b),
            )
        )

    edges = tuple(zip(points[:-1], points[1:], strict=True))
    for i, (a, b) in enumerate(edges):
        for j in range(i + 1, len(edges)):
            if j == i + 1 or (i == 0 and j == len(edges) - 1):
                continue
            if intersects(a, b, *edges[j]):
                raise ValueError("Boundary cannot cross or touch itself")
    area = abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in edges)) / 2
    if not 1 <= area <= 1_000_000:
        raise ValueError("Boundary area must be between 1 and 1,000,000 square metres")
    return Decimal(str(area)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def example_rectangle(width: float, height: float, offset: float = 0) -> tuple[Point, ...]:
    lat = -25.413
    lon = 28.285 + math.degrees(offset / (EARTH_RADIUS_M * math.cos(math.radians(lat))))
    right = lon + math.degrees(width / (EARTH_RADIUS_M * math.cos(math.radians(lat))))
    top = lat + math.degrees(height / EARTH_RADIUS_M)
    return ((lon, lat), (right, lat), (right, top), (lon, top), (lon, lat))
