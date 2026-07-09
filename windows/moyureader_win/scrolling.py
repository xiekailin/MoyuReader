from __future__ import annotations


STANDARD_WHEEL_STEP = 32
MINIMUM_FPS = 60
MAXIMUM_FPS = 240


def next_offset(
    current: float,
    wheel_delta_y: float,
    max_offset: float,
    precise: bool,
    wheel_step: float = STANDARD_WHEEL_STEP,
) -> float:
    multiplier = 1.0 if precise else wheel_step
    proposed = current - wheel_delta_y * multiplier
    return min(max(0.0, proposed), max(0.0, max_offset))


def smoothed_offset(
    current: float,
    target: float,
    response: float = 0.32,
    minimum_step: float = 0.75,
) -> float:
    distance = target - current
    if abs(distance) <= minimum_step:
        return target

    clamped_response = min(max(0.0, response), 1.0)
    proposed_step = distance * clamped_response
    signed_minimum = minimum_step if distance > 0 else -minimum_step
    step = signed_minimum if abs(proposed_step) < minimum_step else proposed_step
    proposed = current + step
    return min(proposed, target) if distance > 0 else max(proposed, target)


def animation_interval_ms(maximum_fps: int = MAXIMUM_FPS) -> int:
    fps = min(max(MINIMUM_FPS, maximum_fps), MAXIMUM_FPS)
    return max(1, round(1000 / fps))


def progress_percent(offset: float, max_offset: float) -> int:
    if max_offset <= 0:
        return 100
    clamped_offset = min(max(0.0, offset), max_offset)
    return round(clamped_offset / max_offset * 100)
