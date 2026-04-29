"""
Email service for sending magic link authentication emails.

Supports SMTP configuration via environment variables.
"""
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from typing import Optional
import logging
from app.core.config import settings

logger = logging.getLogger(__name__)


class EmailService:
    """Service for sending emails via SMTP."""

    def __init__(self):
        """Initialize email service with settings from config."""
        self.smtp_host = settings.smtp_host
        self.smtp_port = settings.smtp_port
        self.smtp_user = settings.smtp_user
        self.smtp_password = settings.smtp_password
        self.smtp_from_email = settings.smtp_from_email
        self.smtp_use_tls = settings.smtp_use_tls

    def is_configured(self) -> bool:
        """Check if email service is properly configured."""
        return bool(
            self.smtp_host
            and self.smtp_user
            and self.smtp_password
            and self.smtp_from_email
        )

    def send_magic_link_email(
        self, email: str, token: str, base_url: str = "http://localhost:8000"
    ) -> bool:
        """
        Send magic link email to user.

        Args:
            email: Recipient email address
            token: Magic link token
            base_url: Base URL for the magic link (default: localhost)

        Returns:
            True if email was sent successfully, False otherwise
        """
        if not self.is_configured():
            logger.warning("Email service not configured. Cannot send magic link.")
            return False

        try:
            # Create magic link URL
            magic_link = f"{base_url}/api/auth/magic-link/verify?token={token}"

            # Create email message
            msg = MIMEMultipart("alternative")
            msg["Subject"] = "Sign in to ReKall"
            msg["From"] = self.smtp_from_email
            msg["To"] = email

            # Create HTML email body
            html_body = f"""
            <!DOCTYPE html>
            <html>
            <head>
                <style>
                    body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
                    .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
                    .button {{ display: inline-block; padding: 12px 24px; background-color: #007bff; 
                              color: white; text-decoration: none; border-radius: 5px; margin: 20px 0; }}
                    .button:hover {{ background-color: #0056b3; }}
                    .footer {{ margin-top: 30px; font-size: 12px; color: #666; }}
                </style>
            </head>
            <body>
                <div class="container">
                    <h2>Sign in to ReKall</h2>
                    <p>Click the button below to sign in to your ReKall account. This link will expire in 15 minutes.</p>
                    <a href="{magic_link}" class="button">Sign In</a>
                    <p>Or copy and paste this link into your browser:</p>
                    <p style="word-break: break-all; color: #666;">{magic_link}</p>
                    <div class="footer">
                        <p>If you didn't request this email, you can safely ignore it.</p>
                        <p>This link will expire in 15 minutes.</p>
                    </div>
                </div>
            </body>
            </html>
            """

            # Create plain text version
            text_body = f"""
            Sign in to ReKall

            Click the link below to sign in to your ReKall account. This link will expire in 15 minutes.

            {magic_link}

            If you didn't request this email, you can safely ignore it.
            """

            # Attach both versions
            msg.attach(MIMEText(text_body, "plain"))
            msg.attach(MIMEText(html_body, "html"))

            # Send email via SMTP
            with smtplib.SMTP(self.smtp_host, self.smtp_port) as server:
                if self.smtp_use_tls:
                    server.starttls()
                server.login(self.smtp_user, self.smtp_password)
                server.send_message(msg)

            logger.info(f"Magic link email sent to {email}")
            return True

        except Exception as e:
            logger.error(f"Failed to send magic link email to {email}: {e}")
            return False

    def send_space_invitation_email(
        self,
        email: str,
        space_name: str,
        space_description: str,
        inviter_name: str,
        invitation_token: str,
        app_deep_link_url: str = "https://YOUR_DEEP_LINK_URL"
    ) -> bool:
        """
        Send space invitation email to user.

        Args:
            email: Recipient email address
            space_name: Name of the space being shared
            space_description: Description of the space
            inviter_name: Name of the person sending the invitation
            invitation_token: Invitation token for joining the space
            app_deep_link_url: Base URL for the mobile app deep link (default: https://recall.app)

        Returns:
            True if email was sent successfully, False otherwise
        """
        if not self.is_configured():
            logger.warning("Email service not configured. Cannot send space invitation.")
            return False

        try:
            # Create invitation deep link URL for mobile app
            invitation_link = f"{app_deep_link_url}/invite/{invitation_token}"

            # Create email message
            msg = MIMEMultipart("alternative")
            msg["Subject"] = f"{inviter_name} invited you to join '{space_name}' on ReKall"
            msg["From"] = self.smtp_from_email
            msg["To"] = email

            # Prepare description text
            description_html = f"<p><strong>About this space:</strong> {space_description}</p>" if space_description else ""
            description_text = f"\nAbout this space: {space_description}\n" if space_description else ""

            # Create HTML email body
            html_body = f"""
            <!DOCTYPE html>
            <html>
            <head>
                <style>
                    body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
                    .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
                    .header {{ background-color: #f8f9fa; padding: 20px; border-radius: 5px; margin-bottom: 20px; }}
                    .space-name {{ color: #007bff; font-size: 20px; font-weight: bold; margin: 10px 0; }}
                    .button {{ display: inline-block; padding: 12px 24px; background-color: #007bff;
                              color: white; text-decoration: none; border-radius: 5px; margin: 20px 0; }}
                    .button:hover {{ background-color: #0056b3; }}
                    .footer {{ margin-top: 30px; font-size: 12px; color: #666; border-top: 1px solid #ddd; padding-top: 20px; }}
                </style>
            </head>
            <body>
                <div class="container">
                    <div class="header">
                        <h2>You're invited to join a space on ReKall!</h2>
                        <p><strong>{inviter_name}</strong> has invited you to collaborate in:</p>
                        <div class="space-name">{space_name}</div>
                        {description_html}
                    </div>
                    <p>Click the button below to accept the invitation and join the space. This invitation will expire in 7 days.</p>
                    <a href="{invitation_link}" class="button">Accept Invitation</a>
                    <p>Or copy and paste this link into your browser:</p>
                    <p style="word-break: break-all; color: #666;">{invitation_link}</p>
                    <div class="footer">
                        <p><strong>What is ReKall?</strong></p>
                        <p>ReKall is a content organization platform that helps you save, organize, and rediscover content from across the web.</p>
                        <p>If you didn't expect this invitation, you can safely ignore this email.</p>
                        <p>This invitation will expire in 7 days.</p>
                    </div>
                </div>
            </body>
            </html>
            """

            # Create plain text version
            text_body = f"""
            You're invited to join a space on ReKall!

            {inviter_name} has invited you to collaborate in:
            {space_name}
            {description_text}
            Click the link below to accept the invitation and join the space. This invitation will expire in 7 days.

            {invitation_link}

            What is ReKall?
            ReKall is a content organization platform that helps you save, organize, and rediscover content from across the web.

            If you didn't expect this invitation, you can safely ignore this email.
            """

            # Attach both versions
            msg.attach(MIMEText(text_body, "plain"))
            msg.attach(MIMEText(html_body, "html"))

            # Send email via SMTP
            with smtplib.SMTP(self.smtp_host, self.smtp_port) as server:
                if self.smtp_use_tls:
                    server.starttls()
                server.login(self.smtp_user, self.smtp_password)
                server.send_message(msg)

            logger.info(f"Space invitation email sent to {email} for space '{space_name}'")
            return True

        except Exception as e:
            logger.error(f"Failed to send space invitation email to {email}: {e}")
            return False


# Global email service instance
email_service = EmailService()

