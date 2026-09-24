from typing import Protocol


class EmailSender(Protocol):
    """Provider-agnostic email transport. Swap the implementation, not the callers."""

    def send(self, to: str, subject: str, html: str, text: str) -> bool:
        """Send one email; return whether it was accepted for delivery.

        Implementations retry transient failures internally and must not
        raise for an ordinary delivery failure - only for misuse (calling
        before configuration is available). Never log ``to``/``subject``/
        ``html``/``text`` verbatim; the caller controls what is safe to log.
        """
        ...
