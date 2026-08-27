"""Toy app for the AWS Transform Python version-upgrade POC."""


def greet(name: str | None) -> dict[str, str]:
    display_name = name if name else "world"
    return {"message": f"Hello, {display_name}!"}
