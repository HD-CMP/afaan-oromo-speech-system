"""
Error Tracking and Crash Reporting
Sentry integration for production error monitoring
"""
import os
import logging
import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.logging import LoggingIntegration
from typing import Optional

from src.config import get_settings

settings = get_settings()
logger = logging.getLogger(__name__)


def init_sentry(
    dsn: Optional[str] = None,
    environment: str = "production",
    enable_tracing: bool = True,
    traces_sample_rate: float = 0.1,
) -> bool:
    """
    Initialize Sentry for error tracking
    
    Args:
        dsn: Sentry DSN (from environment or parameter)
        environment: Environment name (production, staging, development)
        enable_tracing: Enable performance tracing
        traces_sample_rate: Sample rate for traces (0.0 to 1.0)
    
    Returns:
        True if initialized successfully
    """
    sentry_dsn = dsn or os.getenv('SENTRY_DSN')
    
    if not sentry_dsn or sentry_dsn == 'your-sentry-dsn-here':
        logger.warning("[SENTRY] No DSN configured, error tracking disabled")
        return False
    
    try:
        sentry_logging = LoggingIntegration(
            level=logging.INFO,
            event_level=logging.ERROR
        )
        
        sentry_sdk.init(
            dsn=sentry_dsn,
            integrations=[
                FastApiIntegration(),
                sentry_logging,
            ],
            traces_sample_rate=traces_sample_rate if enable_tracing else 0.0,
            environment=environment,
            release=f"{settings.APP_NAME}@{settings.APP_VERSION}",
            send_default_pii=False,
            attach_stacktrace=True,
            before_send=before_send_filter,
        )
        
        logger.info(f"[SENTRY] Initialized (env: {environment})")
        return True
        
    except Exception as e:
        logger.error(f"[SENTRY] Initialization failed: {e}")
        return False


def before_send_filter(event, hint):
    """
    Filter events before sending to Sentry
    
    Removes sensitive data and filters out certain errors
    """
    if 'exc_info' in hint:
        exc_type, exc_value, tb = hint['exc_info']
        
        if isinstance(exc_value, (KeyboardInterrupt, SystemExit)):
            return None
    
    if event.get('request'):
        headers = event['request'].get('headers', {})
        
        sensitive_headers = ['Authorization', 'Cookie', 'X-Api-Key']
        for header in sensitive_headers:
            if header in headers:
                headers[header] = '[Filtered]'
    
    if event.get('extra'):
        sensitive_keys = ['password', 'token', 'api_key', 'secret']
        for key in sensitive_keys:
            if key in event['extra']:
                event['extra'][key] = '[Filtered]'
    
    return event


def capture_exception(exception: Exception, context: Optional[dict] = None):
    """
    Manually capture an exception
    
    Args:
        exception: The exception to capture
        context: Additional context dictionary
    """
    try:
        with sentry_sdk.push_scope() as scope:
            if context:
                for key, value in context.items():
                    scope.set_context(key, value)
            
            sentry_sdk.capture_exception(exception)
    except Exception as e:
        logger.error(f"[SENTRY] Failed to capture exception: {e}")


def capture_message(message: str, level: str = "info", context: Optional[dict] = None):
    """
    Manually capture a message
    
    Args:
        message: The message to capture
        level: Severity level (debug, info, warning, error, fatal)
        context: Additional context dictionary
    """
    try:
        with sentry_sdk.push_scope() as scope:
            if context:
                for key, value in context.items():
                    scope.set_context(key, value)
            
            sentry_sdk.capture_message(message, level=level)
    except Exception as e:
        logger.error(f"[SENTRY] Failed to capture message: {e}")


def set_user_context(user_id: str, email: Optional[str] = None, ip_address: Optional[str] = None):
    """
    Set user context for error tracking
    
    Args:
        user_id: User identifier
        email: User email (optional)
        ip_address: User IP address (optional)
    """
    try:
        sentry_sdk.set_user({
            "id": user_id,
            "email": email,
            "ip_address": ip_address,
        })
    except Exception as e:
        logger.error(f"[SENTRY] Failed to set user context: {e}")


def add_breadcrumb(message: str, category: str = "default", level: str = "info", data: Optional[dict] = None):
    """
    Add a breadcrumb for error context
    
    Args:
        message: Breadcrumb message
        category: Category (navigation, http, etc.)
        level: Severity level
        data: Additional data dictionary
    """
    try:
        sentry_sdk.add_breadcrumb(
            message=message,
            category=category,
            level=level,
            data=data or {},
        )
    except Exception as e:
        logger.error(f"[SENTRY] Failed to add breadcrumb: {e}")


class ErrorTracker:
    """Error tracking context manager"""
    
    def __init__(self, operation_name: str, context: Optional[dict] = None):
        self.operation_name = operation_name
        self.context = context or {}
    
    def __enter__(self):
        add_breadcrumb(
            message=f"Starting: {self.operation_name}",
            category="operation",
            level="info",
            data=self.context
        )
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type is not None:
            add_breadcrumb(
                message=f"Failed: {self.operation_name}",
                category="operation",
                level="error",
                data={"error": str(exc_val)}
            )
            capture_exception(exc_val, context={"operation": self.operation_name, **self.context})
        else:
            add_breadcrumb(
                message=f"Completed: {self.operation_name}",
                category="operation",
                level="info"
            )
        
        return False


if __name__ == "__main__":
    print("="*60)
    print("ERROR TRACKING TEST")
    print("="*60)
    
    initialized = init_sentry(environment="development")
    print(f"Sentry initialized: {initialized}")
    
    if initialized:
        try:
            raise ValueError("Test error for Sentry")
        except Exception as e:
            capture_exception(e, context={"test": "error tracking"})
            print("Test error captured")
    
    print("="*60)
