import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import greet


def main():
    result = greet("AWS Transform")
    assert result["message"] == "Hello, AWS Transform!", result

    default_result = greet(None)
    assert default_result["message"] == "Hello, world!", default_result

    print("local-invoke: all assertions passed")


if __name__ == "__main__":
    main()
