package repository

import (
	"context"

	"coded/models"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

type UserRepo interface {
	FindByID(ctx context.Context, id primitive.ObjectID) (*models.User, error)
	FindByEmail(ctx context.Context, email string) (*models.User, error)
	FindByReferralCode(ctx context.Context, code string) (*models.User, error)
	Create(ctx context.Context, user *models.User) error
	Update(ctx context.Context, id primitive.ObjectID, update bson.M) (*mongo.UpdateResult, error)
	Delete(ctx context.Context, id primitive.ObjectID) error
	CountByField(ctx context.Context, field string, value interface{}) (int64, error)
	Search(ctx context.Context, filter bson.M, limit int64) ([]models.User, error)
	FindMany(ctx context.Context, filter bson.M) ([]models.User, error)
	FindWithFilterAndLimit(ctx context.Context, filter bson.M, limit int64, opts ...*options.FindOptions) ([]models.User, error)
}

type ChatRepo interface {
	FindByID(ctx context.Context, id primitive.ObjectID) (*models.Chat, error)
	FindByInviteCode(ctx context.Context, code string) (*models.Chat, error)
	FindExistingDM(ctx context.Context, participantIDs []primitive.ObjectID) (*models.Chat, error)
	Create(ctx context.Context, chat *models.Chat) error
	Update(ctx context.Context, id primitive.ObjectID, update bson.M) error
	AddParticipant(ctx context.Context, id, userID primitive.ObjectID) error
	RemoveParticipant(ctx context.Context, id, userID primitive.ObjectID) error
	PromoteAdmin(ctx context.Context, id, userID primitive.ObjectID) error
	CountParticipants(ctx context.Context, id, userID primitive.ObjectID) (int64, error)
	Aggregate(ctx context.Context, pipeline mongo.Pipeline) (*mongo.Cursor, error)
}

type MessageRepo interface {
	Create(ctx context.Context, msg *models.Message) error
	FindByID(ctx context.Context, id primitive.ObjectID) (*models.Message, error)
	FindByChat(ctx context.Context, chatID primitive.ObjectID, limit int64) (*mongo.Cursor, error)
	MarkRead(ctx context.Context, chatID, userID primitive.ObjectID) (*mongo.UpdateResult, error)
	FindUnreadByChat(ctx context.Context, chatID, userID primitive.ObjectID) ([]models.Message, error)
	UpdateOne(ctx context.Context, filter bson.M, update bson.M) (*mongo.UpdateResult, error)
}

type PostRepo interface {
	Create(ctx context.Context, post *models.Post) error
	Aggregate(ctx context.Context, pipeline mongo.Pipeline) (*mongo.Cursor, error)
}

type FavoriteRepo interface {
	Exists(ctx context.Context, userID, targetID primitive.ObjectID) (bool, error)
	Create(ctx context.Context, fav *models.Favorite) error
	Delete(ctx context.Context, userID, targetID primitive.ObjectID) (*mongo.DeleteResult, error)
	FindByUser(ctx context.Context, userID primitive.ObjectID, limit int64) ([]models.Favorite, error)
}

type SubscriptionRepo interface {
	Upsert(ctx context.Context, sub *models.PushSubscription) error
	FindByUser(ctx context.Context, userID primitive.ObjectID) (*models.PushSubscription, error)
	Delete(ctx context.Context, userID primitive.ObjectID) error
}
