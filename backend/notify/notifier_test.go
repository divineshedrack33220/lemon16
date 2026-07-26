package notify

import (
	"context"
	"log/slog"
	"net/smtp"
	"os"
	"testing"
)

func TestNewNotifier_EnabledEmail(t *testing.T) {
	os.Setenv("SMTP_HOST", "smtp.example.com")
	os.Setenv("SMTP_PORT", "587")
	os.Setenv("SMTP_USER", "user@example.com")
	os.Setenv("SMTP_PASS", "password")
	os.Setenv("SMTP_FROM", "noreply@example.com")
	defer func() {
		os.Unsetenv("SMTP_HOST")
		os.Unsetenv("SMTP_PORT")
		os.Unsetenv("SMTP_USER")
		os.Unsetenv("SMTP_PASS")
		os.Unsetenv("SMTP_FROM")
	}()

	n := NewNotifier()
	if !n.email.Enabled {
		t.Error("expected email to be enabled")
	}
	if n.email.Host != "smtp.example.com" {
		t.Errorf("expected host=smtp.example.com, got %s", n.email.Host)
	}
	if n.email.Port != 587 {
		t.Errorf("expected port=587, got %d", n.email.Port)
	}
}

func TestNewNotifier_DisabledEmail(t *testing.T) {
	os.Unsetenv("SMTP_HOST")
	defer os.Unsetenv("SMTP_HOST")

	n := NewNotifier()
	if n.email.Enabled {
		t.Error("expected email to be disabled")
	}
}

func TestNewNotifier_EnabledSMS(t *testing.T) {
	os.Setenv("TWILIO_ACCOUNT_SID", "AC123")
	os.Setenv("TWILIO_AUTH_TOKEN", "token")
	os.Setenv("TWILIO_PHONE", "+15551112222")
	defer func() {
		os.Unsetenv("TWILIO_ACCOUNT_SID")
		os.Unsetenv("TWILIO_AUTH_TOKEN")
		os.Unsetenv("TWILIO_PHONE")
	}()

	n := NewNotifier()
	if !n.sms.Enabled {
		t.Error("expected SMS to be enabled")
	}
	if n.sms.From != "+15551112222" {
		t.Errorf("expected from=+15551112222, got %s", n.sms.From)
	}
}

func TestNewNotifier_DisabledSMS(t *testing.T) {
	os.Unsetenv("TWILIO_ACCOUNT_SID")
	defer os.Unsetenv("TWILIO_ACCOUNT_SID")

	n := NewNotifier()
	if n.sms.Enabled {
		t.Error("expected SMS to be disabled")
	}
}

func TestBuildFavoriteEmail(t *testing.T) {
	email := buildFavoriteEmail(FavoriteNotification{
		FavoriterName: "John Doe",
	})

	if email == "" {
		t.Error("expected non-empty email body")
	}
	if !contains(email, "John Doe") {
		t.Error("expected email to contain favoriter name")
	}
	if !contains(email, "Zukaping") {
		t.Error("expected email to contain brand name")
	}
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && searchString(s, substr)
}

func searchString(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

func TestNotifier_OnFavorite_WithNilNotifier(t *testing.T) {
	n := &Notifier{}

	fn := FavoriteNotification{
		FavoriterName: "Test User",
		TargetEmail:   "target@example.com",
		TargetPhone:   "+15550001111",
	}

	n.OnFavorite(context.Background(), fn)
}

func TestNotifier_OnFavorite_EmailDisabled(t *testing.T) {
	n := &Notifier{
		email: EmailConfig{Enabled: false},
		sms:   SMSConfig{Enabled: false},
	}

	fn := FavoriteNotification{
		FavoriterName: "Test User",
		TargetEmail:   "target@example.com",
	}

	n.OnFavorite(context.Background(), fn)
}

func TestNotifier_OnFavorite_SMSDisabled(t *testing.T) {
	n := &Notifier{
		email: EmailConfig{Enabled: false},
		sms:   SMSConfig{Enabled: false},
	}

	fn := FavoriteNotification{
		FavoriterName: "Test User",
		TargetPhone:   "+15550001111",
	}

	n.OnFavorite(context.Background(), fn)
}

func TestNotifier_sendEmail_InvalidHost(t *testing.T) {
	n := &Notifier{
		logger: slog.Default(),
		email: EmailConfig{
			Host:     "invalid-host-that-does-not-exist.local",
			Port:     587,
			Username: "user",
			Password: "pass",
			From:     "from@test.com",
			Enabled:  true,
		},
	}

	fn := FavoriteNotification{
		FavoriterName: "Test User",
		TargetEmail:   "target@example.com",
	}

	n.sendEmail(fn)
}

func TestAuthenticator(t *testing.T) {
	accountSid := "AC123"
	authToken := "token"
	result := basicAuth(accountSid, authToken)

	expected := accountSid + ":" + authToken
	if result != expected {
		t.Errorf("expected %s, got %s", expected, result)
	}
}

func TestNotifier_GetEnvInt(t *testing.T) {
	os.Setenv("TEST_PORT", "2525")
	defer os.Unsetenv("TEST_PORT")

	if v := getEnvInt("TEST_PORT", 587); v != 2525 {
		t.Errorf("expected 2525, got %d", v)
	}

	if v := getEnvInt("NONEXISTENT_KEY", 42); v != 42 {
		t.Errorf("expected 42, got %d", v)
	}
}

func TestSendmailInterface(t *testing.T) {
	_ = smtp.SendMail
}