"""Inline-CSS, mobile-friendly email bodies. Each template returns (html, text)."""

_FOOTER_TEXT = (
    "This is an automated message from Almanac. Replies to this address are not "
    "monitored. Need help? Contact support at [support contact placeholder]."
)
_FOOTER_HTML = (
    '<p style="margin:24px 0 0;font-size:12px;color:#6b7280;">'
    "This is an automated message from Almanac. Replies to this address are not "
    "monitored. Need help? Contact support at [support contact placeholder]."
    "</p>"
)
_WRAPPER_OPEN = (
    '<div style="font-family:Arial,Helvetica,sans-serif;max-width:480px;'
    'margin:0 auto;padding:24px;color:#111827;">'
    '<p style="font-size:20px;font-weight:bold;margin:0 0 16px;">Almanac</p>'
)
_WRAPPER_CLOSE = "</div>"


def otp_email(code: str, expires_in_minutes: int = 10) -> tuple[str, str]:
    html = (
        f"{_WRAPPER_OPEN}"
        '<p style="margin:0 0 16px;">Your verification code is:</p>'
        f'<p style="font-size:32px;font-weight:bold;letter-spacing:4px;'
        f'margin:0 0 16px;">{code}</p>'
        f'<p style="margin:0 0 16px;">This code expires in {expires_in_minutes} minutes.</p>'
        '<p style="margin:0 0 16px;">If you didn\'t request this, you can ignore this email.</p>'
        f"{_FOOTER_HTML}"
        f"{_WRAPPER_CLOSE}"
    )
    text = (
        f"Your verification code is: {code}\n\n"
        f"This code expires in {expires_in_minutes} minutes.\n\n"
        "If you didn't request this, you can ignore this email.\n\n"
        f"{_FOOTER_TEXT}"
    )
    return html, text


def notification_email(
    title: str, message: str, button_text: str | None = None, button_url: str | None = None
) -> tuple[str, str]:
    button_html = ""
    button_text_line = ""
    if button_text and button_url:
        button_html = (
            f'<p style="margin:0 0 16px;"><a href="{button_url}" '
            'style="display:inline-block;padding:10px 20px;background:#111827;'
            'color:#ffffff;text-decoration:none;border-radius:4px;">'
            f"{button_text}</a></p>"
        )
        button_text_line = f"\n{button_text}: {button_url}\n"
    html = (
        f"{_WRAPPER_OPEN}"
        f'<p style="font-size:16px;font-weight:bold;margin:0 0 16px;">{title}</p>'
        f'<p style="margin:0 0 16px;">{message}</p>'
        f"{button_html}"
        f"{_FOOTER_HTML}"
        f"{_WRAPPER_CLOSE}"
    )
    text = f"{title}\n\n{message}\n{button_text_line}\n{_FOOTER_TEXT}"
    return html, text
