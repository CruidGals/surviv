"""Official MAD (Military Audio Dataset) class order from the reference implementation."""

from typing import Tuple

# Index matches CSV `label` column 0..6 (see kaen2891/military_audio_dataset main.py: cls_list)
MAD_CLASS_NAMES: Tuple[str, ...] = (
    "Communication",
    "Shooting",
    "Footsteps",
    "Shelling",
    "Vehicle",
    "Helicopter",
    "Fighter",
)


def names_for_num_classes(num_classes: int) -> Tuple[str, ...]:
    if num_classes <= len(MAD_CLASS_NAMES):
        return MAD_CLASS_NAMES[:num_classes]
    return tuple(f"Class {i}" for i in range(num_classes))
