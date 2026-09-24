"""Manual, one-off real send through the configured Gmail SMTP sender.

Never run in CI or as part of any automated check. Reads SMTP_* / EMAIL_FROM_*
from the environment (see .env.example) the same way the app does; this
script never prints the password or SMTP conversation.
"""

import argparse

from farmable_backend.email_templates import notification_email
from farmable_backend.integrations.email.gmail_smtp import GmailSmtpEmailSender
from farmable_backend.integrations.settings import ServiceSettings


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("to", help="Recipient email address for the one test send")
    args = parser.parse_args(argv)

    settings = ServiceSettings()
    sender = GmailSmtpEmailSender(settings)
    html, text = notification_email(
        "Almanac SMTP test",
        "This confirms Gmail SMTP is configured correctly for Almanac.",
    )
    ok = sender.send(args.to, "Almanac SMTP test", html, text)
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
