package repository

import (
	"context"

	"coded/models"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

type SubscriptionRepository struct {
	coll *mongo.Collection
}

func (r *SubscriptionRepository) Upsert(ctx context.Context, sub *models.PushSubscription) error {
	_, err := r.coll.UpdateOne(
		ctx,
		bson.M{"userId": sub.UserID},
		bson.M{"$set": sub},
		options.Update().SetUpsert(true),
	)
	return err
}

func (r *SubscriptionRepository) FindByUser(ctx context.Context, userID primitive.ObjectID) (*models.PushSubscription, error) {
	var sub models.PushSubscription
	err := r.coll.FindOne(ctx, bson.M{"userId": userID}).Decode(&sub)
	if err != nil {
		return nil, err
	}
	return &sub, nil
}

func (r *SubscriptionRepository) Delete(ctx context.Context, userID primitive.ObjectID) error {
	_, err := r.coll.DeleteOne(ctx, bson.M{"userId": userID})
	return err
}

func (r *SubscriptionRepository) Collection() *mongo.Collection {
	return r.coll
}
