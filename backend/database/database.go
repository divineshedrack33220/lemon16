package database

import (
	"context"
	"log/slog"
	"time"

	"coded/config"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

var (
	Client *mongo.Client
	DB     *mongo.Database
)

func ConnectDB(cfg *config.Config) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	clientOptions := options.Client().ApplyURI(cfg.MongoURI)

	// Connection pool tuning
	poolSize := uint64(50)
	if cfg.IsRender {
		poolSize = 20
	}
	clientOptions.SetMaxPoolSize(poolSize)
	clientOptions.SetMinPoolSize(5)
	clientOptions.SetMaxConnIdleTime(5 * time.Minute)
	clientOptions.SetRetryWrites(true)
	clientOptions.SetRetryReads(true)

	// Application name for MongoDB logs
	clientOptions.SetAppName("zukaping")

	client, err := mongo.Connect(ctx, clientOptions)
	if err != nil {
		return err
	}

	err = client.Ping(ctx, nil)
	if err != nil {
		return err
	}

	Client = client
	DB = client.Database(cfg.DatabaseName)

	slog.Info("connected to MongoDB",
		"database", cfg.DatabaseName,
		"max_pool_size", poolSize,
	)
	CreateIndexes()
	return nil
}

func Ping(ctx context.Context) error {
	if Client == nil {
		return mongo.ErrClientDisconnected
	}
	return Client.Ping(ctx, nil)
}

func GetCollection(collectionName string) *mongo.Collection {
	return DB.Collection(collectionName)
}

func CreateIndexes() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	usersColl := DB.Collection("users")
	usersIndexes := []mongo.IndexModel{
		{
			Keys:    bson.D{{Key: "email", Value: 1}},
			Options: options.Index().SetUnique(true),
		},
		{
			Keys:    bson.D{{Key: "username", Value: 1}},
			Options: options.Index().SetUnique(true).SetSparse(true),
		},
		{
			Keys: bson.D{{Key: "location", Value: "2dsphere"}},
		},
		{
			Keys: bson.D{{Key: "lastSeen", Value: -1}},
		},
	}

	chatsColl := DB.Collection("chats")
	chatsIndexes := []mongo.IndexModel{
		{
			Keys:    bson.D{{Key: "participants", Value: 1}},
			Options: options.Index().SetUnique(true).SetName("unique_participants"),
		},
		{
			Keys: bson.D{{Key: "lastMessageAt", Value: -1}},
		},
	}

	messagesColl := DB.Collection("messages")
	messagesIndexes := []mongo.IndexModel{
		{
			Keys: bson.D{{Key: "chatId", Value: 1}, {Key: "createdAt", Value: -1}},
		},
		{
			Keys: bson.D{{Key: "senderId", Value: 1}},
		},
		{
			Keys: bson.D{{Key: "createdAt", Value: -1}},
		},
	}

	favoritesColl := DB.Collection("favorites")
	favoritesIndexes := []mongo.IndexModel{
		{
			Keys:    bson.D{{Key: "userId", Value: 1}, {Key: "targetUserId", Value: 1}},
			Options: options.Index().SetUnique(true),
		},
		{
			Keys: bson.D{{Key: "createdAt", Value: -1}},
		},
	}

	postsColl := DB.Collection("posts")
	postsIndexes := []mongo.IndexModel{
		{
			Keys: bson.D{{Key: "userId", Value: 1}},
		},
		{
			Keys: bson.D{{Key: "createdAt", Value: -1}},
		},
		{
			Keys: bson.D{{Key: "category", Value: 1}},
		},
	}

	if _, err := usersColl.Indexes().CreateMany(ctx, usersIndexes); err != nil {
		slog.Error("failed to create users indexes", "error", err)
	}
	if _, err := chatsColl.Indexes().CreateMany(ctx, chatsIndexes); err != nil {
		slog.Error("failed to create chats indexes", "error", err)
	}
	if _, err := messagesColl.Indexes().CreateMany(ctx, messagesIndexes); err != nil {
		slog.Error("failed to create messages indexes", "error", err)
	}
	if _, err := favoritesColl.Indexes().CreateMany(ctx, favoritesIndexes); err != nil {
		slog.Error("failed to create favorites indexes", "error", err)
	}
	if _, err := postsColl.Indexes().CreateMany(ctx, postsIndexes); err != nil {
		slog.Error("failed to create posts indexes", "error", err)
	}

	slog.Info("database indexes created")
}
