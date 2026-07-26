package repository

import (
	"context"

	"coded/models"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

type MessageRepository struct {
	coll *mongo.Collection
}

func (r *MessageRepository) Create(ctx context.Context, msg *models.Message) error {
	_, err := r.coll.InsertOne(ctx, msg)
	return err
}

func (r *MessageRepository) FindByID(ctx context.Context, id primitive.ObjectID) (*models.Message, error) {
	var msg models.Message
	err := r.coll.FindOne(ctx, bson.M{"_id": id}).Decode(&msg)
	if err != nil {
		return nil, err
	}
	return &msg, nil
}

func (r *MessageRepository) FindByChat(ctx context.Context, chatID primitive.ObjectID, limit int64) (*mongo.Cursor, error) {
	pipeline := mongo.Pipeline{
		{{Key: "$match", Value: bson.D{{Key: "chatId", Value: chatID}}}},
		{{Key: "$sort", Value: bson.D{{Key: "createdAt", Value: 1}}}},
		{{Key: "$limit", Value: limit}},
		{{Key: "$lookup", Value: bson.D{
			{Key: "from", Value: "users"},
			{Key: "localField", Value: "senderId"},
			{Key: "foreignField", Value: "_id"},
			{Key: "as", Value: "senderProfile"},
		}}},
		{{Key: "$unwind", Value: bson.D{
			{Key: "path", Value: "$senderProfile"},
			{Key: "preserveNullAndEmptyArrays", Value: true},
		}}},
	}
	return r.coll.Aggregate(ctx, pipeline)
}

func (r *MessageRepository) MarkRead(ctx context.Context, chatID, userID primitive.ObjectID) (*mongo.UpdateResult, error) {
	return r.coll.UpdateMany(
		ctx,
		bson.M{
			"chatId":   chatID,
			"senderId": bson.M{"$ne": userID},
			"isRead":   false,
		},
		bson.M{"$set": bson.M{"isRead": true}},
	)
}

func (r *MessageRepository) FindUnreadByChat(ctx context.Context, chatID, userID primitive.ObjectID) ([]models.Message, error) {
	cursor, err := r.coll.Find(ctx, bson.M{
		"chatId":   chatID,
		"senderId": bson.M{"$ne": userID},
		"isRead":   true,
	})
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)

	var messages []models.Message
	if err := cursor.All(ctx, &messages); err != nil {
		return nil, err
	}
	return messages, nil
}

func (r *MessageRepository) UpdateOne(ctx context.Context, filter bson.M, update bson.M) (*mongo.UpdateResult, error) {
	return r.coll.UpdateOne(ctx, filter, update)
}

func (r *MessageRepository) FindByUser(ctx context.Context, chatID, userID primitive.ObjectID, opts ...*options.FindOptions) (*mongo.Cursor, error) {
	return r.coll.Find(ctx, bson.M{"chatId": chatID, "senderId": userID}, opts...)
}

func (r *MessageRepository) Collection() *mongo.Collection {
	return r.coll
}
