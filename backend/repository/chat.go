package repository

import (
	"context"

	"coded/models"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

type ChatRepository struct {
	coll *mongo.Collection
}

func (r *ChatRepository) FindByID(ctx context.Context, id primitive.ObjectID) (*models.Chat, error) {
	var chat models.Chat
	err := r.coll.FindOne(ctx, bson.M{"_id": id}).Decode(&chat)
	if err != nil {
		return nil, err
	}
	return &chat, nil
}

func (r *ChatRepository) FindByInviteCode(ctx context.Context, code string) (*models.Chat, error) {
	var chat models.Chat
	err := r.coll.FindOne(ctx, bson.M{"inviteCode": code, "isGroup": true}).Decode(&chat)
	if err != nil {
		return nil, err
	}
	return &chat, nil
}

func (r *ChatRepository) FindExistingDM(ctx context.Context, participantIDs []primitive.ObjectID) (*models.Chat, error) {
	filter := bson.M{
		"participants": bson.M{
			"$all":  participantIDs,
			"$size": len(participantIDs),
		},
		"isGroup": bson.M{"$ne": true},
	}
	var chat models.Chat
	err := r.coll.FindOne(ctx, filter).Decode(&chat)
	if err != nil {
		return nil, err
	}
	return &chat, nil
}

func (r *ChatRepository) Create(ctx context.Context, chat *models.Chat) error {
	_, err := r.coll.InsertOne(ctx, chat)
	return err
}

func (r *ChatRepository) Update(ctx context.Context, id primitive.ObjectID, update bson.M) error {
	_, err := r.coll.UpdateOne(ctx, bson.M{"_id": id}, update)
	return err
}

func (r *ChatRepository) AddParticipant(ctx context.Context, id, userID primitive.ObjectID) error {
	_, err := r.coll.UpdateOne(ctx, bson.M{"_id": id}, bson.M{"$addToSet": bson.M{"participants": userID}})
	return err
}

func (r *ChatRepository) RemoveParticipant(ctx context.Context, id, userID primitive.ObjectID) error {
	_, err := r.coll.UpdateOne(ctx, bson.M{"_id": id}, bson.M{
		"$pull": bson.M{
			"participants": userID,
			"adminIds":     userID,
		},
	})
	return err
}

func (r *ChatRepository) PromoteAdmin(ctx context.Context, id, userID primitive.ObjectID) error {
	_, err := r.coll.UpdateOne(ctx, bson.M{"_id": id}, bson.M{"$addToSet": bson.M{"adminIds": userID}})
	return err
}

func (r *ChatRepository) CountParticipants(ctx context.Context, id, userID primitive.ObjectID) (int64, error) {
	return r.coll.CountDocuments(ctx, bson.M{"_id": id, "participants": userID})
}

func (r *ChatRepository) Aggregate(ctx context.Context, pipeline mongo.Pipeline) (*mongo.Cursor, error) {
	return r.coll.Aggregate(ctx, pipeline)
}

func (r *ChatRepository) Collection() *mongo.Collection {
	return r.coll
}
