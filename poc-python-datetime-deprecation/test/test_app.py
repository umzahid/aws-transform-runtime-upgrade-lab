import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import current_utc_label


def main():
    label = current_utc_label()
    assert label.startswith("UTC: "), label

    timestamp_part = label[len("UTC: "):]
    assert re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}", timestamp_part), timestamp_part

    print("local-invoke: all assertions passed")


if __name__ == "__main__":
    main()
