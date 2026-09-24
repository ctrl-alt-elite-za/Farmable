from typing import Protocol


class DeliveryUnknown(Exception):
    """The provider may have accepted the message before the transport failed."""


class EmailSender(Protocol):
    """Provider-agnostic email transport. Swap the implementation, not the callers."""

    def send(self, to: str, subject: str, html: str, text: str) -> bool:
        """Send one email; return whether it was accepted for delivery.

        Implementations retry transient failures known to precede submission
        and must raise ``DeliveryUnknown`` when submission may have been
        accepted before the transport failed. Never log ``to``/``subject``/
        ``html``/``text`` verbatim; the caller controls what is safe to log.
        """
        ...
