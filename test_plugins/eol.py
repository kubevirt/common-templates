import datetime

def osinfo_active(os):
    """Return true when the `os` is active. That means it was
       released and is not End-Of-Life for more than 6 months."""
    eol = os.eol_date
    min_eol = datetime.date.today() + datetime.timedelta(days=180)
    return os.release_date is not None and (eol is None or \
            datetime.date(year=eol.year, month=eol.month, day=eol.day) > min_eol)


class TestModule(object):
    '''OSinfo tests'''

    def tests(self):
        return {
            "osinfo_active": osinfo_active
        }

