package notify

import (
	"context"
	"crypto/tls"
	"fmt"
	"log/slog"
	"net/http"
	"net/smtp"
	"os"
	"strings"
)

type EmailConfig struct {
	Host     string
	Port     int
	Username string
	Password string
	From     string
	Enabled  bool
}

type SMSConfig struct {
	AccountSid string
	AuthToken  string
	From       string
	Enabled    bool
}

type Notifier struct {
	email  EmailConfig
	sms    SMSConfig
	logger *slog.Logger
}

func NewNotifier() *Notifier {
	email := EmailConfig{
		Host:     os.Getenv("SMTP_HOST"),
		Port:     getEnvInt("SMTP_PORT", 587),
		Username: os.Getenv("SMTP_USER"),
		Password: os.Getenv("SMTP_PASS"),
		From:     os.Getenv("SMTP_FROM"),
		Enabled:  os.Getenv("SMTP_HOST") != "",
	}

	sms := SMSConfig{
		AccountSid: os.Getenv("TWILIO_ACCOUNT_SID"),
		AuthToken:  os.Getenv("TWILIO_AUTH_TOKEN"),
		From:       os.Getenv("TWILIO_PHONE"),
		Enabled:    os.Getenv("TWILIO_ACCOUNT_SID") != "",
	}

	return &Notifier{
		email:  email,
		sms:    sms,
		logger: slog.Default(),
	}
}

func getEnvInt(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		var n int
		fmt.Sscanf(v, "%d", &n)
		return n
	}
	return def
}

type FavoriteNotification struct {
	FavoriterID   string
	FavoriterName string
	TargetID      string
	TargetEmail   string
	TargetPhone   string
}

func (n *Notifier) OnFavorite(ctx context.Context, fn FavoriteNotification) {
	if n.email.Enabled && fn.TargetEmail != "" {
		n.sendEmail(fn)
	}
	if n.sms.Enabled && fn.TargetPhone != "" {
		n.sendSMS(fn)
	}
}

func (n *Notifier) sendEmail(fn FavoriteNotification) {
	body := buildFavoriteEmail(fn)

	auth := smtp.PlainAuth("", n.email.Username, n.email.Password, n.email.Host)

	tlsConfig := &tls.Config{
		InsecureSkipVerify: false,
		ServerName:         n.email.Host,
	}

	conn, err := tls.Dial("tcp", fmt.Sprintf("%s:%d", n.email.Host, n.email.Port), tlsConfig)
	if err != nil {
		n.logger.Error("email dial failed", "to", fn.TargetEmail, "error", err)
		return
	}
	defer conn.Close()

	client, err := smtp.NewClient(conn, n.email.Host)
	if err != nil {
		n.logger.Error("email client failed", "to", fn.TargetEmail, "error", err)
		return
	}
	defer client.Quit()

	if err = client.Auth(auth); err != nil {
		n.logger.Error("email auth failed", "to", fn.TargetEmail, "error", err)
		return
	}

	fromAddr := strings.Split(n.email.From, "@")
	toAddr := strings.Split(fn.TargetEmail, "@")

	if err = client.Mail(fromAddr[0]); err != nil {
		n.logger.Error("email mail from failed", "to", fn.TargetEmail, "error", err)
		return
	}
	if err = client.Rcpt(toAddr[0]); err != nil {
		n.logger.Error("email rcpt failed", "to", fn.TargetEmail, "error", err)
		return
	}

	wc, err := client.Data()
	if err != nil {
		n.logger.Error("email data failed", "to", fn.TargetEmail, "error", err)
		return
	}
	_, err = wc.Write([]byte(body))
	if err != nil {
		n.logger.Error("email write failed", "to", fn.TargetEmail, "error", err)
		return
	}
	err = wc.Close()
	if err != nil {
		n.logger.Error("email close failed", "to", fn.TargetEmail, "error", err)
		return
	}

	n.logger.Info("email sent", "to", fn.TargetEmail)
}

func (n *Notifier) sendSMS(fn FavoriteNotification) {
	smsBody := fmt.Sprintf("Someone favorited you! %s wants to connect.", fn.FavoriterName)
	to := fn.TargetPhone

	url := "https://api.twilio.com/2010-04-01/Accounts/" + n.sms.AccountSid + "/Messages.json"

	data := fmt.Sprintf("To=%s&From=%s&Body=%s", to, n.sms.From, smsBody)

	req, err := http.NewRequestWithContext(context.Background(), "POST", url, strings.NewReader(data))
	if err != nil {
		n.logger.Error("sms request failed", "to", to, "error", err)
		return
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Authorization", "Basic "+basicAuth(n.sms.AccountSid, n.sms.AuthToken))

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		n.logger.Error("sms send failed", "to", to, "error", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		n.logger.Info("sms sent", "to", to)
	} else {
		n.logger.Error("sms unexpected status", "to", to, "status", resp.StatusCode)
	}
}

func basicAuth(accountSid, authToken string) string {
	return fmt.Sprintf("%s:%s", accountSid, authToken)
}

func buildFavoriteEmail(fn FavoriteNotification) string {
	return fmt.Sprintf("Subject: Someone favorited you on Zukaping!\r\n\r\n"+
		"Hi,\r\n\r\n"+
		"%s just favorited your profile!\r\n\r\n"+
		"Head over to your dashboard to see who likes you.\r\n\r\n"+
		"--\r\nZukaping Team\r\n", fn.FavoriterName)
}