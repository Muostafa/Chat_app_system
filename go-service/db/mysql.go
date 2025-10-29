package db

import (
	"database/sql"
	"fmt"
	"log"
	"os"

	_ "github.com/go-sql-driver/mysql"
)

var DB *sql.DB

// InitDB initializes the MySQL database connection
func InitDB() error {
	dsn := os.Getenv("MYSQL_DSN")
	if dsn == "" {
		dsn = "root:password@tcp(localhost:3306)/chat_system_development?parseTime=true"
	}

	var err error
	DB, err = sql.Open("mysql", dsn)
	if err != nil {
		return fmt.Errorf("failed to open database: %v", err)
	}

	// Set connection pool settings
	DB.SetMaxOpenConns(25)
	DB.SetMaxIdleConns(5)

	// Test connection
	if err = DB.Ping(); err != nil {
		return fmt.Errorf("failed to ping database: %v", err)
	}

	log.Println("MySQL connected successfully")
	return nil
}

// GetChatApplicationID gets the chat application ID by token
func GetChatApplicationID(token string) (int64, error) {
	var id int64
	err := DB.QueryRow("SELECT id FROM chat_applications WHERE token = ?", token).Scan(&id)
	if err == sql.ErrNoRows {
		return 0, fmt.Errorf("chat application not found")
	}
	if err != nil {
		return 0, fmt.Errorf("database query error: %v", err)
	}
	return id, nil
}

// GetChatID gets the chat ID by application ID and chat number
func GetChatID(chatApplicationID int64, chatNumber int64) (int64, error) {
	var id int64
	query := "SELECT id FROM chats WHERE chat_application_id = ? AND number = ?"
	err := DB.QueryRow(query, chatApplicationID, chatNumber).Scan(&id)
	if err == sql.ErrNoRows {
		return 0, fmt.Errorf("chat not found")
	}
	if err != nil {
		return 0, fmt.Errorf("database query error: %v", err)
	}
	return id, nil
}

// CloseDB closes the database connection
func CloseDB() error {
	if DB != nil {
		return DB.Close()
	}
	return nil
}
