"""Toy app for the second AWS Transform Python version-upgrade POC."""
import datetime


def current_utc_label():
    now = datetime.datetime.now(datetime.timezone.utc)
    return "UTC: {}".format(now.isoformat())
